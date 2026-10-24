import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../settings.dart';
import 'smtp_auth.dart';
import 'smtp_data.dart';
import 'smtp_exception.dart';
import 'smtp_reply.dart';
import 'smtp_wire.dart';

final Logger _log = Logger('plume.smtp');

/// Timeouts and TLS trust for SMTP connections.
final class SmtpConfig {
  const SmtpConfig({
    this.connectTimeout = const Duration(seconds: 30),
    this.replyTimeout = const Duration(minutes: 1),
    this.dataTimeout = const Duration(minutes: 10),
    this.clientName = '[127.0.0.1]',
    this.securityContext,
  });

  /// TCP connect plus TLS handshake.
  final Duration connectTimeout;

  /// Waiting for the greeting and for each command's reply.
  final Duration replyTimeout;

  /// Uploading the message, and separately waiting for the server's verdict
  /// after it: servers scan for spam and viruses before answering, which
  /// takes a while for large attachments (RFC 5321 suggests 10 minutes).
  final Duration dataTimeout;

  /// The name announced in EHLO. Like Thunderbird, an address literal
  /// rather than the real host name, which would leak into the Received
  /// header of every message.
  final String clientName;

  /// Certificates trusted for TLS. Null means the system's trusted roots;
  /// tests pass a context trusting their own self-signed certificate.
  /// Verification (chain and host name) is never switched off.
  final SecurityContext? securityContext;
}

/// One SMTP submission session (RFC 5321, 6409) over dart:io.
///
/// Typical use: [connect], [login], [send] (once per message), [quit], and
/// [destroy] in a `finally`. Failures are [SmtpException]s carrying an
/// [SmtpErrorKind] and a message meant for the user.
///
/// Security: [ConnectionSecurity.tls] negotiates TLS before anything else;
/// [ConnectionSecurity.startTls] requires the server to advertise STARTTLS
/// and never continues in plain text; [ConnectionSecurity.none] is refused
/// unless the host is local. Certificates are always fully verified.
final class SmtpClient {
  SmtpClient(this.endpoint, {this.config = const SmtpConfig()});

  final ServerEndpoint endpoint;
  final SmtpConfig config;

  SmtpWire? _wire;
  bool _destroyed = false;
  X509Certificate? _rejectedCertificate;
  Map<String, String> _extensions = const {};
  Set<String> _authMechanisms = const {};

  String get _host => endpoint.host;

  /// EHLO keywords (upper case) and their parameters, from the most recent
  /// EHLO. Empty after a HELO fallback.
  Map<String, String> get extensions => UnmodifiableMapView(_extensions);

  /// SASL mechanisms the server offers, upper case.
  Set<String> get authMechanisms => UnmodifiableSetView(_authMechanisms);

  /// Whether the session is encrypted.
  bool get isSecure => _wire?.isSecure ?? false;

  /// Connects, reads the greeting, says EHLO and, for STARTTLS, upgrades
  /// the connection and says EHLO again.
  Future<void> connect() async {
    if (_wire != null || _destroyed) throw StateError('SmtpClient.connect may only be called once');
    if (endpoint.security == ConnectionSecurity.none && !endpoint.isLocal) {
      throw SmtpException(
        SmtpErrorKind.insecure,
        'Plume only sends mail without encryption to a server on this computer. '
        'Choose SSL/TLS or STARTTLS for $_host.',
      );
    }
    try {
      final socket = await _open();
      if (_destroyed) {
        socket.destroy();
        throw _interrupted();
      }
      _wire = SmtpWire(socket, host: _host);
      _log.fine('Connected to $endpoint');
      final greeting = await _readReply(_deadline(config.replyTimeout));
      if (greeting.code != 220) {
        throw _rejected('The outgoing mail server $_host refused the connection', greeting);
      }
      await _hello();
      if (endpoint.security == ConnectionSecurity.startTls) await _startTls();
    } on Object {
      destroy();
      rethrow;
    }
  }

  /// Signs in with [username] and [password], preferring PLAIN and falling
  /// back to LOGIN when the server refuses PLAIN despite advertising it.
  Future<void> login(String username, String password) async {
    final offered = _authMechanisms;
    final mechanisms = <SaslMechanism>[
      if (offered.contains('PLAIN')) PlainMechanism(username, password),
      if (offered.contains('LOGIN')) LoginMechanism(username, password),
    ];
    if (mechanisms.isEmpty) {
      throw SmtpException(
        SmtpErrorKind.authUnavailable,
        offered.isEmpty
            ? '$_host does not accept a sign-in on port ${endpoint.port}. '
                  'Outgoing mail normally uses port 465 (SSL/TLS) or 587 (STARTTLS).'
            : '$_host only offers sign-in methods Plume does not support (${offered.join(', ')}).',
      );
    }
    for (final (i, mechanism) in mechanisms.indexed) {
      try {
        await authenticate(mechanism);
        return;
      } on SmtpException catch (e) {
        // 504: advertised, but not usable for this account or connection.
        if (e.reply?.code == 504 && i < mechanisms.length - 1) {
          _log.fine('${mechanism.name} was refused; trying ${mechanisms[i + 1].name}');
          continue;
        }
        rethrow;
      }
    }
  }

  /// Runs one SASL exchange (RFC 4954). Credentials never appear in logs.
  Future<void> authenticate(SaslMechanism mechanism) async {
    // Defense in depth: connect() already guarantees this.
    if (!isSecure && !endpoint.isLocal) {
      throw SmtpException(SmtpErrorKind.insecure, 'Refusing to send a password to $_host without encryption.');
    }
    final initial = mechanism.initialResponse;
    var reply = await _command(
      initial == null ? 'AUTH ${mechanism.name}' : 'AUTH ${mechanism.name} ${_base64(initial)}',
      logAs: 'AUTH ${mechanism.name}${initial == null ? '' : ' <redacted>'}',
    );
    var step = 0;
    while (reply.code == 334) {
      List<int> response;
      try {
        if (step >= 10) throw StateError('Too many challenges');
        final challenge = base64.decode(reply.lines.isEmpty ? '' : reply.lines.first.trim());
        response = mechanism.respond(challenge, step++);
      } on Object {
        // "*" cancels the exchange (RFC 4954 section 4).
        await _command('*').then((_) {}, onError: (Object _) {});
        throw SmtpException(SmtpErrorKind.protocol, '$_host sent an unexpected sign-in challenge.');
      }
      reply = await _command(_base64(response), logAs: '<redacted>');
    }
    if (reply.code == 235) {
      _log.fine('Signed in to $_host with ${mechanism.name}');
      return;
    }
    throw _authError(reply);
  }

  /// Sends one message: a single envelope from [from] to all [recipients].
  ///
  /// If the server refuses any recipient the transaction is reset and
  /// nothing is sent; the exception lists every refused address. When the
  /// connection drops after the message was uploaded the outcome is
  /// unknown; that is reported as [SmtpErrorKind.connectionLost].
  Future<void> send({required String from, required List<String> recipients, required Uint8List data}) async {
    checkEnvelope(from, recipients);
    final unique = LinkedHashSet<String>(
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (a) => a.toLowerCase().hashCode,
    )..addAll(recipients);

    final payload = SmtpPayload.encode(data);
    final params = <String>[];
    final limit = _sizeLimit;
    if (limit != null) {
      if (limit > 0 && payload.bytes.length > limit) {
        throw SmtpException(
          SmtpErrorKind.messageTooLarge,
          'The message is ${_megabytes(payload.bytes.length)}, but $_host accepts at most '
          '${_megabytes(limit)}. Remove some attachments and try again.',
        );
      }
      params.add('SIZE=${payload.bytes.length}');
    }
    if (payload.has8BitBody) {
      if (_extensions.containsKey('8BITMIME')) {
        params.add('BODY=8BITMIME');
      } else {
        // Nearly every server accepts it anyway; refusing to send would be
        // worse than the small risk of a mangled byte.
        _log.warning('$_host does not advertise 8BITMIME; sending 8-bit content anyway');
      }
    }
    final utf8Envelope = !_isAscii(from) || unique.any((r) => !_isAscii(r));
    if (utf8Envelope || payload.has8BitHeaders) {
      if (_extensions.containsKey('SMTPUTF8')) {
        params.add('SMTPUTF8');
      } else if (utf8Envelope) {
        throw SmtpException(
          SmtpErrorKind.invalidAddress,
          '$_host cannot send mail to or from addresses with non-Latin characters.',
        );
      }
    }

    final mail = await _command(
      'MAIL FROM:<$from>${params.isEmpty ? '' : ' ${params.join(' ')}'}',
      logAs: 'MAIL FROM:<…>${params.isEmpty ? '' : ' ${params.join(' ')}'}',
    );
    if (mail.code != 250) {
      if (mail.code == 530) throw _authError(mail);
      throw _rejected('The outgoing mail server $_host refused the sender $from', mail);
    }

    final refused = <(String, SmtpReply)>[];
    for (final recipient in unique) {
      final reply = await _command('RCPT TO:<$recipient>', logAs: 'RCPT TO:<…>');
      // 251 and 252: accepted, the server forwards or cannot verify.
      if (reply.code == 250 || reply.code == 251 || reply.code == 252) continue;
      if (reply.code == 421) throw _rejected('The outgoing mail server $_host closed the connection', reply);
      refused.add((recipient, reply));
    }
    if (refused.isNotEmpty) {
      await _reset();
      // One permanent refusal makes the whole send permanent: retrying
      // later would fail on that address again.
      final (_, reply) = refused.firstWhere((r) => r.$2.isPermanent, orElse: () => refused.first);
      final addresses = [for (final (a, _) in refused) a];
      throw SmtpException(
        SmtpErrorKind.recipientRejected,
        addresses.length == 1
            ? 'The server refused the recipient ${addresses.single} (${reply.message}). Nothing was sent.'
            : 'The server refused ${addresses.length} recipients: ${addresses.join(', ')} '
                  '(${reply.message}). Nothing was sent.',
        reply: reply,
        recipients: List.unmodifiable(addresses),
      );
    }

    final start = await _command('DATA');
    if (start.code != 354) {
      await _reset();
      throw _rejected('The outgoing mail server $_host refused the message', start);
    }
    final wire = _requireWire();
    try {
      _log.fine('Uploading ${payload.bytes.length} bytes');
      wire.write(payload.bytes);
      await wire.flush(_deadline(config.dataTimeout));
      final done = await _readReply(_deadline(config.dataTimeout));
      if (done.code != 250) throw _rejected('The outgoing mail server $_host refused the message', done);
    } on SmtpException catch (e) {
      if (e.kind != SmtpErrorKind.connectionLost && e.kind != SmtpErrorKind.timeout) rethrow;
      throw SmtpException(
        e.kind,
        'The connection to the outgoing mail server $_host was interrupted while sending the message.',
        cause: e.cause,
      );
    }
    _log.fine('Message accepted by $_host');
  }

  /// Ends the session politely. Never throws.
  Future<void> quit() async {
    final wire = _wire;
    if (wire == null || _destroyed) return;
    try {
      await _command('QUIT', timeout: const Duration(seconds: 5));
    } on SmtpException {
      // The server may already have hung up; that is fine.
    }
    await wire.close();
    _destroyed = true;
  }

  /// Closes the connection immediately. Safe to call at any time and more
  /// than once; an in-flight operation fails with
  /// [SmtpErrorKind.connectionLost].
  void destroy() {
    _destroyed = true;
    _wire?.destroy();
  }

  // Connection --------------------------------------------------------------

  Future<Socket> _open() async {
    final port = endpoint.port;
    final Future<Socket> connecting = endpoint.security == ConnectionSecurity.tls
        ? SecureSocket.connect(
            _host,
            port,
            context: config.securityContext,
            onBadCertificate: _onBadCertificate,
            timeout: config.connectTimeout,
          )
        : Socket.connect(_host, port, timeout: config.connectTimeout);
    try {
      // The socket's own timeout does not cover the TLS handshake.
      return await connecting.timeout(config.connectTimeout);
    } on TimeoutException {
      connecting.then((s) => s.destroy(), onError: (Object _) {}).ignore();
      throw SmtpException(SmtpErrorKind.timeout, 'The outgoing mail server $_host:$port did not respond in time.');
    } on Object catch (e) {
      throw _connectionError(e);
    }
  }

  /// Rejects every certificate the platform could not verify, remembering
  /// it so the failure can be reported as a certificate problem.
  bool _onBadCertificate(X509Certificate certificate) {
    _rejectedCertificate = certificate;
    return false;
  }

  Future<void> _hello() async {
    final reply = await _command('EHLO ${config.clientName}');
    if (reply.code == 250) {
      _parseExtensions(reply);
      return;
    }
    // Only a server that does not know EHLO gets HELO (RFC 5321 section
    // 3.2); it offers no extensions, so STARTTLS and AUTH will be missing.
    if (reply.code == 500 || reply.code == 502) {
      _log.fine('$_host refused EHLO; falling back to HELO');
      // HELO takes a domain, not an address literal.
      final helo = await _command('HELO localhost');
      if (helo.code == 250) {
        _extensions = const {};
        _authMechanisms = const {};
        return;
      }
      throw _rejected('The outgoing mail server $_host refused the greeting', helo);
    }
    throw _rejected('The outgoing mail server $_host refused the greeting', reply);
  }

  void _parseExtensions(SmtpReply reply) {
    final extensions = <String, String>{};
    final mechanisms = <String>{};
    for (final line in reply.lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final space = trimmed.indexOf(' ');
      final keyword = (space < 0 ? trimmed : trimmed.substring(0, space)).toUpperCase();
      final params = space < 0 ? '' : trimmed.substring(space + 1).trim();
      // Old servers (and Outlook) also announce "AUTH=LOGIN PLAIN".
      if (keyword == 'AUTH' || keyword.startsWith('AUTH=')) {
        final first = keyword.startsWith('AUTH=') ? keyword.substring(5) : '';
        mechanisms.addAll([first, ...params.toUpperCase().split(RegExp(r'\s+'))].where((m) => m.isNotEmpty));
        extensions.putIfAbsent('AUTH', () => params);
        continue;
      }
      extensions[keyword] = params;
    }
    _extensions = extensions;
    _authMechanisms = mechanisms;
  }

  Future<void> _startTls() async {
    if (!_extensions.containsKey('STARTTLS')) {
      throw SmtpException(
        SmtpErrorKind.startTlsUnavailable,
        '$_host does not offer STARTTLS, so the connection cannot be encrypted. '
        'Try SSL/TLS on port 465.',
      );
    }
    final reply = await _command('STARTTLS');
    if (reply.code != 220) {
      throw SmtpException(
        SmtpErrorKind.startTlsUnavailable,
        'The outgoing mail server $_host could not start encryption (${reply.message}).',
        reply: reply,
      );
    }
    final wire = _requireWire();
    if (wire.hasBufferedInput) {
      throw SmtpException(
        SmtpErrorKind.protocol,
        '$_host sent unexpected data before encryption started; the connection may have been tampered with.',
      );
    }
    try {
      await wire
          .upgrade(context: config.securityContext, onBadCertificate: _onBadCertificate)
          .timeout(config.connectTimeout);
    } on TimeoutException {
      wire.destroy();
      throw SmtpException(SmtpErrorKind.timeout, 'The outgoing mail server $_host did not respond in time.');
    } on SmtpException {
      rethrow;
    } on Object catch (e) {
      throw _connectionError(e);
    }
    _log.fine('STARTTLS negotiated with $_host');
    _extensions = const {};
    _authMechanisms = const {};
    // RFC 3207: forget everything learned before TLS and ask again.
    await _hello();
  }

  Future<void> _reset() async {
    try {
      await _command('RSET', timeout: const Duration(seconds: 10));
    } on SmtpException {
      // The transaction is abandoned either way.
    }
  }

  // Commands and replies ------------------------------------------------------

  SmtpWire _requireWire() {
    final wire = _wire;
    if (wire == null || _destroyed) throw _interrupted();
    return wire;
  }

  DateTime _deadline(Duration timeout) => DateTime.now().add(timeout);

  Future<SmtpReply> _command(String line, {String? logAs, Duration? timeout}) async {
    final wire = _requireWire();
    _log.finer('C: ${logAs ?? line}');
    wire.writeLine(line);
    final deadline = _deadline(timeout ?? config.replyTimeout);
    await wire.flush(deadline);
    return _readReply(deadline);
  }

  Future<SmtpReply> _readReply(DateTime deadline) async {
    final wire = _requireWire();
    final parser = SmtpReplyParser();
    while (true) {
      final line = await wire.readLine(deadline);
      try {
        final reply = parser.add(line);
        if (reply == null) continue;
        _log.finer('S: ${reply.code} ${reply.message}');
        return reply;
      } on FormatException {
        throw SmtpException(
          SmtpErrorKind.protocol,
          '$_host:${endpoint.port} is not an outgoing mail (SMTP) server${_identify(line)}.',
          serverText: line.length > 200 ? line.substring(0, 200) : line,
        );
      }
    }
  }

  /// Names the protocol a mistaken port speaks, to make the error useful.
  static String _identify(String line) {
    if (line.startsWith('* OK') || line.startsWith('* PREAUTH')) return ' (it is an IMAP server)';
    if (line.startsWith('+OK')) return ' (it is a POP3 server)';
    if (line.startsWith('HTTP/')) return ' (it is a web server)';
    return '';
  }

  // Errors --------------------------------------------------------------------

  SmtpException _interrupted() =>
      SmtpException(SmtpErrorKind.connectionLost, 'The connection to the outgoing mail server $_host was closed.');

  SmtpException _rejected(String what, SmtpReply reply) =>
      SmtpException(SmtpErrorKind.rejected, '$what: ${reply.message}', reply: reply);

  SmtpException _authError(SmtpReply reply) {
    if (reply.code == 504) {
      return SmtpException(
        SmtpErrorKind.authUnavailable,
        '$_host refused the sign-in method (${reply.message}).',
        reply: reply,
      );
    }
    if (reply.isTransient) {
      return SmtpException(
        SmtpErrorKind.rejected,
        '$_host could not check your password right now (${reply.message}). Try again later.',
        reply: reply,
      );
    }
    // 535 bad credentials, 534 (Gmail: app password required), 530 auth
    // required, 538 encryption required, or any 5.7.x security refusal.
    const authCodes = {530, 534, 535, 538};
    if (authCodes.contains(reply.code) || (reply.enhancedCode?.startsWith('5.7.') ?? false)) {
      return SmtpException(
        SmtpErrorKind.authFailed,
        '$_host did not accept the username or password: ${reply.message}',
        reply: reply,
      );
    }
    return _rejected('$_host refused the sign-in', reply);
  }

  SmtpException _connectionError(Object error) =>
      smtpConnectionError(error, endpoint, rejectedCertificate: _rejectedCertificate);

  // Helpers -------------------------------------------------------------------

  /// The SIZE limit, 0 when advertised without a number, null when absent.
  int? get _sizeLimit {
    final size = _extensions['SIZE'];
    if (size == null) return null;
    return int.tryParse(size.trim()) ?? 0;
  }

  /// Rejects anything that could break out of the angle brackets of an
  /// SMTP command (CR/LF injection) or is obviously not an address.
  static final RegExp _forbidden = RegExp(r'[\x00-\x20<>\x7F]');

  /// Throws [SmtpException] ([SmtpErrorKind.invalidAddress]) unless
  /// [from] and [recipients] can be sent; call it before connecting.
  static void checkEnvelope(String from, List<String> recipients) {
    if (recipients.isEmpty) {
      throw const SmtpException(SmtpErrorKind.invalidAddress, 'The message has no recipients.');
    }
    _checkAddress(from);
    recipients.forEach(_checkAddress);
  }

  static void _checkAddress(String address) {
    if (address.isEmpty || !address.contains('@') || _forbidden.hasMatch(address)) {
      throw SmtpException(SmtpErrorKind.invalidAddress, '"$address" is not a valid email address.');
    }
  }

  static bool _isAscii(String s) => s.codeUnits.every((c) => c < 0x80);

  static String _base64(List<int> bytes) => bytes.isEmpty ? '' : base64.encode(bytes);

  static String _megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Classifies a failure to connect or to negotiate TLS with [endpoint].
/// [rejectedCertificate] is the certificate the client refused, if any.
SmtpException smtpConnectionError(Object error, ServerEndpoint endpoint, {X509Certificate? rejectedCertificate}) {
  if (error is SmtpException) return error;
  final host = endpoint.host;
  final where = '$host:${endpoint.port}';
  if (error is TlsException) {
    final certificate = rejectedCertificate;
    if (certificate != null || error.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
      return SmtpException(
        SmtpErrorKind.certificate,
        'The security certificate of $host is not trusted'
        '${certificate == null ? '' : ' (issued to ${certificate.subject} by ${certificate.issuer})'}. '
        'The server may be misconfigured, or someone may be intercepting the connection.',
        cause: error,
      );
    }
    return SmtpException(
      SmtpErrorKind.tls,
      'Could not set up a secure connection to $where. Check that the security setting matches the port '
      '(465 uses SSL/TLS, 587 uses STARTTLS).',
      cause: error,
    );
  }
  if (error is SocketException) {
    if (error.message.startsWith('Failed host lookup')) {
      // EAI_AGAIN: the resolver itself was unreachable, so the network
      // is down rather than the name being wrong.
      if (error.osError?.errorCode == -3) {
        return SmtpException(
          SmtpErrorKind.unreachable,
          'Could not look up $host. Check your internet connection.',
          cause: error,
        );
      }
      return SmtpException(
        SmtpErrorKind.hostNotFound,
        'The outgoing mail server $host does not exist. Check the server name.',
        cause: error,
      );
    }
    if (error.osError?.errorCode == 110 || error.message.contains('timed out')) {
      return SmtpException(
        SmtpErrorKind.timeout,
        'The outgoing mail server $where did not respond in time.',
        cause: error,
      );
    }
  }
  return SmtpException(
    SmtpErrorKind.unreachable,
    'Could not connect to the outgoing mail server $where.',
    cause: error,
  );
}
