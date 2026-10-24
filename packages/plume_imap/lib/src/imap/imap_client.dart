import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../settings.dart';
import 'imap_connection.dart';
import 'imap_exception.dart';
import 'imap_fetch.dart';
import 'imap_response.dart';
import 'mutf7.dart';
import 'uid_set.dart';

final Logger _log = Logger('plume.imap');

/// Connection and protocol settings for [ImapClient].
final class ImapClientConfig {
  const ImapClientConfig({
    this.connectTimeout = const Duration(seconds: 20),
    this.responseTimeout = const Duration(seconds: 60),
    this.securityContext,
    this.clientId = const {'name': 'Plume', 'vendor': 'Plume'},
    this.maxLiteralSize = 256 << 20,
    this.idleRestart = const Duration(minutes: 25),
  });

  /// Covers TCP connect, TLS handshake and the greeting.
  final Duration connectTimeout;

  /// Longest silence tolerated while waiting for a response.
  final Duration responseTimeout;

  /// Trust roots for TLS. Null uses the system's; certificates are always
  /// verified, including the host name.
  final SecurityContext? securityContext;

  /// Sent with the ID command (RFC 2971) when the server supports it; some
  /// servers refuse to work without it.
  final Map<String, String> clientId;
  final int maxLiteralSize;

  /// IDLE is re-issued this often (RFC 2177: at least every 29 minutes).
  final Duration idleRestart;
}

/// A mailbox from LIST.
final class ImapMailboxInfo {
  const ImapMailboxInfo({
    required this.name,
    required this.encodedName,
    required this.delimiter,
    required this.attributes,
    this.status,
  });

  /// Decoded (Unicode) full name. INBOX is always `INBOX`.
  final String name;

  /// The name exactly as the server sent it, for use in commands.
  final String encodedName;
  final String? delimiter;

  /// Lower-cased attributes, e.g. `\noselect`, `\sent`, `\haschildren`.
  final Set<String> attributes;

  /// From LIST-STATUS, when requested and supported.
  final ImapMailboxStatus? status;

  bool get isSelectable => !attributes.contains(r'\noselect') && !attributes.contains(r'\nonexistent');

  bool has(String attribute) => attributes.contains(attribute.toLowerCase());

  ImapMailboxInfo withStatus(ImapMailboxStatus? status) => ImapMailboxInfo(
        name: name,
        encodedName: encodedName,
        delimiter: delimiter,
        attributes: attributes,
        status: status,
      );

  @override
  String toString() => 'ImapMailboxInfo($name ${attributes.join(' ')})';
}

/// STATUS data.
final class ImapMailboxStatus {
  const ImapMailboxStatus({this.messages, this.uidNext, this.uidValidity, this.unseen, this.highestModSeq});

  final int? messages;
  final int? uidNext;
  final int? uidValidity;
  final int? unseen;
  final int? highestModSeq;

  static ImapMailboxStatus parse(List<ImapValue> items) {
    int? get(String key) {
      for (var i = 0; i + 1 < items.length; i += 2) {
        if (items[i].text?.toUpperCase() == key) return items[i + 1].asInt;
      }
      return null;
    }

    return ImapMailboxStatus(
      messages: get('MESSAGES'),
      uidNext: get('UIDNEXT'),
      uidValidity: get('UIDVALIDITY'),
      unseen: get('UNSEEN'),
      highestModSeq: get('HIGHESTMODSEQ'),
    );
  }
}

/// The currently selected mailbox, kept up to date by unsolicited
/// responses.
final class ImapSelected {
  ImapSelected(this.name, {required this.readOnly});

  final String name;
  bool readOnly;
  int exists = 0;
  int? uidValidity;
  int? uidNext;
  int? highestModSeq;
  bool noModSeq = false;
  Set<String> flags = {};
  Set<String> permanentFlags = {};

  /// From a QRESYNC SELECT: UIDs expunged since the given modseq, and
  /// messages whose flags changed.
  UidSet vanished = UidSet.empty;
  final changed = <ImapFetch>[];
}

/// Mailbox change notifications (during IDLE or any command).
sealed class ImapEvent {
  const ImapEvent();
}

final class ImapExistsEvent extends ImapEvent {
  const ImapExistsEvent(this.count);
  final int count;
}

final class ImapExpungeEvent extends ImapEvent {
  const ImapExpungeEvent(this.sequence);
  final int sequence;
}

final class ImapVanishedEvent extends ImapEvent {
  const ImapVanishedEvent(this.uids);
  final UidSet uids;
}

final class ImapFlagsEvent extends ImapEvent {
  const ImapFlagsEvent(this.fetch);
  final ImapFetch fetch;
}

/// Result of a UID SEARCH.
final class ImapSearchResult {
  const ImapSearchResult(this.ids, {this.highestModSeq});

  final UidSet ids;
  final int? highestModSeq;
}

/// COPYUID / APPENDUID data (RFC 4315).
final class ImapCopyUid {
  const ImapCopyUid(this.uidValidity, this.mapping);

  final int uidValidity;

  /// Source UID → destination UID.
  final Map<int, int> mapping;

  static ImapCopyUid? parse(ResponseCode? code) {
    if (code == null || code.name != 'COPYUID') return null;
    final w = code.words;
    if (w.length < 3) return null;
    final uv = int.tryParse(w[0]);
    final src = _expandOrdered(w[1]);
    final dst = _expandOrdered(w[2]);
    if (uv == null || src.length != dst.length) return null;
    return ImapCopyUid(uv, {for (var i = 0; i < src.length; i++) src[i]: dst[i]});
  }

  /// Expands a set keeping its textual order (`304,319:320` → 304, 319,
  /// 320); ranges may be written high to low.
  static List<int> _expandOrdered(String set) {
    final out = <int>[];
    for (final piece in set.split(',')) {
      final colon = piece.indexOf(':');
      if (colon < 0) {
        final v = int.tryParse(piece);
        if (v != null) out.add(v);
        continue;
      }
      final a = int.tryParse(piece.substring(0, colon));
      final b = int.tryParse(piece.substring(colon + 1));
      if (a == null || b == null || (a - b).abs() > 1000000) continue;
      if (a <= b) {
        for (var v = a; v <= b; v++) {
          out.add(v);
        }
      } else {
        for (var v = a; v >= b; v--) {
          out.add(v);
        }
      }
    }
    return out;
  }
}

final class ImapAppendUid {
  const ImapAppendUid(this.uidValidity, this.uid);

  final int uidValidity;
  final int uid;

  static ImapAppendUid? parse(ResponseCode? code) {
    if (code == null || code.name != 'APPENDUID') return null;
    final w = code.words;
    if (w.length < 2) return null;
    final uv = int.tryParse(w[0]);
    final uid = int.tryParse(w[1]);
    return uv == null || uid == null ? null : ImapAppendUid(uv, uid);
  }
}

/// A SASL mechanism for AUTHENTICATE. [PlainSasl] is used for passwords;
/// [XOAuth2Sasl] is the seam for OAuth accounts.
abstract interface class ImapSaslMechanism {
  String get name;

  /// Initial client response (sent with SASL-IR, or after the first empty
  /// challenge), not yet base64-encoded.
  List<int> get initialResponse;

  /// Answers a later server challenge (decoded). The default for both
  /// mechanisms here is an empty response, which asks the server to finish
  /// with a tagged NO carrying its reason.
  List<int> respond(Uint8List challenge);
}

/// SASL PLAIN (RFC 4616).
final class PlainSasl implements ImapSaslMechanism {
  const PlainSasl(this.username, this.password);

  final String username;
  final String password;

  @override
  String get name => 'PLAIN';

  @override
  List<int> get initialResponse => utf8.encode('\u0000$username\u0000$password');

  @override
  List<int> respond(Uint8List challenge) => const [];
}

/// Google's XOAUTH2 (also supported by Microsoft and Yahoo).
final class XOAuth2Sasl implements ImapSaslMechanism {
  const XOAuth2Sasl(this.username, this.accessToken);

  final String username;
  final String accessToken;

  @override
  String get name => 'XOAUTH2';

  @override
  List<int> get initialResponse => utf8.encode('user=$username\u0001auth=Bearer $accessToken\u0001\u0001');

  @override
  List<int> respond(Uint8List challenge) => const [];
}

/// An IMAP4rev1 client over one connection, with the common extensions
/// (LITERAL+, SASL-IR, ID, ENABLE, CONDSTORE/QRESYNC, UTF8=ACCEPT,
/// SPECIAL-USE, LIST-STATUS, ESEARCH, MOVE, UIDPLUS, IDLE, NAMESPACE) and
/// Gmail's X-GM-EXT-1.
///
/// Not safe for interleaved multi-step use: callers serialize sequences
/// such as SELECT-then-FETCH themselves (the provider uses one lock per
/// connection). Single commands may be pipelined.
final class ImapClient {
  ImapClient._(this._conn, this.endpoint, this.config) {
    _conn.onUntagged = _onUntagged;
  }

  final ServerEndpoint endpoint;
  final ImapClientConfig config;
  final ImapConnection _conn;
  Set<String> _caps = {};
  final _enabled = <String>{};
  ImapSelected? _selected;
  bool _authenticated = false;
  final _events = StreamController<ImapEvent>.broadcast(sync: true);
  String _greetingText = '';

  /// Connects, secures the connection as [endpoint] requires, and reads
  /// the greeting and capabilities. Throws [ImapSecurityException] for
  /// plaintext to a remote host or a missing STARTTLS, and
  /// [ImapConnectionException] / [ImapTimeoutException] / socket and TLS
  /// exceptions when the server cannot be reached.
  static Future<ImapClient> connect(ServerEndpoint endpoint, {ImapClientConfig config = const ImapClientConfig()}) async {
    if (endpoint.security == ConnectionSecurity.none && !endpoint.isLocal) {
      throw const ImapSecurityException('Unencrypted connections are only allowed to this computer (localhost)');
    }
    final socket = await _openSocket(endpoint, config);
    final conn = ImapConnection(
      socket,
      responseTimeout: config.connectTimeout,
      maxLiteralSize: config.maxLiteralSize,
      debugName: endpoint.host,
    );
    final client = ImapClient._(conn, endpoint, config);
    try {
      await client._handshake();
    } catch (_) {
      conn.destroy();
      rethrow;
    }
    conn.responseTimeout = config.responseTimeout;
    return client;
  }

  static Future<Socket> _openSocket(ServerEndpoint endpoint, ImapClientConfig config) async {
    final task = await Socket.startConnect(endpoint.host, endpoint.port);
    final Socket raw;
    try {
      raw = await task.socket.timeout(config.connectTimeout);
    } on TimeoutException {
      task.cancel();
      throw ImapTimeoutException('Could not connect to ${endpoint.host}:${endpoint.port} in time');
    }
    if (endpoint.security != ConnectionSecurity.tls) return raw;
    final secure = SecureSocket.secure(raw, host: endpoint.host, context: config.securityContext);
    try {
      return await secure.timeout(config.connectTimeout);
    } on TimeoutException {
      secure.ignore();
      raw.destroy();
      throw const ImapTimeoutException('TLS handshake timed out');
    } catch (_) {
      raw.destroy();
      rethrow;
    }
  }

  Future<void> _handshake() async {
    final greeting = await _conn.greeting;
    _greetingText = greeting.text;
    if (greeting.status == 'BYE') throw ImapConnectionException('Server refused the connection: ${greeting.text}');
    if (greeting.status != 'OK' && greeting.status != 'PREAUTH') {
      throw const ImapProtocolException('The server did not send an IMAP greeting');
    }
    _authenticated = greeting.status == 'PREAUTH';
    _applyCapabilityCode(greeting.code);
    if (_caps.isEmpty) await refreshCapabilities();
    if (endpoint.security == ConnectionSecurity.startTls) {
      if (_authenticated) throw const ImapSecurityException('Server skipped authentication before STARTTLS');
      if (!_caps.contains('STARTTLS')) {
        throw const ImapSecurityException('The server does not offer STARTTLS', startTlsUnavailable: true);
      }
      final r = await _conn.send(ImapCommand('STARTTLS', ['STARTTLS']));
      if (!r.isOk) throw const ImapSecurityException('The server refused STARTTLS', startTlsUnavailable: true);
      await _conn.startTls(host: endpoint.host, context: config.securityContext, timeout: config.connectTimeout);
      // Capabilities learned before TLS must be discarded (RFC 3501 6.2.1).
      _caps = {};
      await refreshCapabilities();
    }
  }

  // State ------------------------------------------------------------------

  /// Upper-cased capabilities, e.g. `IMAP4REV1`, `AUTH=PLAIN`, `X-GM-EXT-1`.
  Set<String> get capabilities => Set.unmodifiable(_caps);

  bool supports(String capability) => _caps.contains(capability.toUpperCase());

  /// The server speaks Gmail's extensions.
  bool get isGmail => supports('X-GM-EXT-1');
  bool get isAuthenticated => _authenticated;
  bool get isClosed => _conn.isClosed;
  Future<void> get done => _conn.done;
  String get greetingText => _greetingText;

  bool get utf8Enabled => _enabled.contains('UTF8=ACCEPT');
  bool get condstoreEnabled => _enabled.contains('CONDSTORE') || _enabled.contains('QRESYNC');
  bool get qresyncEnabled => _enabled.contains('QRESYNC');

  /// The selected mailbox, if any.
  ImapSelected? get selected => _selected;

  /// Mailbox change notifications.
  Stream<ImapEvent> get events => _events.stream;

  void _applyCapabilityCode(ResponseCode? code) {
    if (code?.name == 'CAPABILITY') _setCapabilities(code!.words);
  }

  void _setCapabilities(Iterable<String> words) {
    _caps = {for (final w in words) w.toUpperCase()};
    _conn.nonSyncLiteralLimit = _caps.contains('LITERAL+') ? 1 << 30 : (_caps.contains('LITERAL-') ? 4096 : 0);
  }

  void _onUntagged(ImapResponse r) {
    switch (r.type) {
      case 'CAPABILITY':
        _setCapabilities([for (final v in r.data) ?v.text]);
      case 'ENABLED':
        _enabled.addAll([for (final v in r.data) ?v.text?.toUpperCase()]);
      case 'EXISTS':
        final s = _selected;
        if (s != null && r.number != null) {
          s.exists = r.number!;
          _events.add(ImapExistsEvent(r.number!));
        }
      case 'EXPUNGE':
        final s = _selected;
        if (s != null && r.number != null) {
          if (s.exists > 0) s.exists--;
          _events.add(ImapExpungeEvent(r.number!));
        }
      case 'VANISHED':
        final earlier = r.data.isNotEmpty && r.data.first is ImapList;
        final set = UidSet.parse(r.data.isEmpty ? '' : (r.data.last.text ?? ''));
        final s = _selected;
        if (s != null) {
          if (earlier) {
            s.vanished = s.vanished.union(set);
          } else {
            s.exists = (s.exists - set.length).clamp(0, 1 << 31);
          }
        }
        _events.add(ImapVanishedEvent(set));
      case 'FETCH':
        if (_selected != null && r.number != null) {
          _events.add(ImapFlagsEvent(ImapFetch.parse(r.number!, r.data, utf8Names: utf8Enabled)));
        }
      case 'FLAGS':
        _selected?.flags = {for (final v in r.data.isEmpty ? const <ImapValue>[] : r.data.first.items) ?v.text};
      case 'OK':
        final code = r.code;
        final s = _selected;
        if (code != null && s != null) {
          switch (code.name) {
            case 'UIDVALIDITY':
              s.uidValidity = code.number;
            case 'UIDNEXT':
              s.uidNext = code.number;
            case 'HIGHESTMODSEQ':
              s.highestModSeq = code.number;
            case 'NOMODSEQ':
              s.noModSeq = true;
            case 'PERMANENTFLAGS':
              s.permanentFlags = RegExp(r'\\?[^\s()]+').allMatches(code.args).map((m) => m.group(0)!).toSet();
          }
        }
        _applyCapabilityCode(code);
    }
  }

  // Commands ---------------------------------------------------------------

  Future<ImapResult> _run(String name, List<Object> parts, {bool check = true}) async {
    final r = await _conn.send(ImapCommand(name, parts));
    return check ? r.check() : r;
  }

  Future<void> refreshCapabilities() async {
    final r = await _run('CAPABILITY', ['CAPABILITY']);
    if (r.ofType('CAPABILITY').isEmpty) _applyCapabilityCode(r.tagged.code);
  }

  /// Logs in with a password: AUTHENTICATE PLAIN (with SASL-IR when
  /// available), else LOGIN. Respects LOGINDISABLED. Throws
  /// [ImapAuthException] when the server refuses.
  Future<void> login(String username, String password) async {
    if (_authenticated) return;
    final loginDisabled = supports('LOGINDISABLED');
    if (supports('AUTH=PLAIN')) {
      final r = await _authenticate(PlainSasl(username, password));
      if (r.isOk) return _afterLogin(r);
      if (r.tagged.status == 'NO' || loginDisabled) throw _authError(r);
      _log.fine('AUTHENTICATE PLAIN rejected as ${r.tagged.status}; trying LOGIN');
    } else if (loginDisabled) {
      throw const ImapAuthException('The server does not allow password login on this connection (LOGINDISABLED)');
    }
    final r = await _run('LOGIN', ['LOGIN ', ..._quotedOrLiteral(username), ' ', ..._quotedOrLiteral(password)], check: false);
    if (!r.isOk) throw _authError(r);
    await _afterLogin(r);
  }

  /// Authenticates with [mechanism] (e.g. [XOAuth2Sasl]).
  Future<void> authenticate(ImapSaslMechanism mechanism) async {
    if (_authenticated) return;
    final r = await _authenticate(mechanism);
    if (!r.isOk) throw _authError(r);
    await _afterLogin(r);
  }

  Future<ImapResult> _authenticate(ImapSaslMechanism mechanism) {
    final initial = base64.encode(mechanism.initialResponse);
    final saslIr = supports('SASL-IR');
    var sentInitial = saslIr;
    return _conn.send(ImapCommand(
      'AUTHENTICATE',
      ['AUTHENTICATE ${mechanism.name}${saslIr ? ' ${initial.isEmpty ? '=' : initial}' : ''}'],
      onContinuation: (c) {
        if (!sentInitial) {
          sentInitial = true;
          return ascii.encode(initial);
        }
        return ascii.encode(base64.encode(mechanism.respond(_decodeChallenge(c.text))));
      },
    ));
  }

  static Uint8List _decodeChallenge(String text) {
    try {
      return base64.decode(base64.normalize(text.trim()));
    } on FormatException {
      return Uint8List(0);
    }
  }

  ImapAuthException _authError(ImapResult r) {
    final alert = r.untagged.where((u) => u.code?.name == 'ALERT').map((u) => u.text).firstOrNull;
    var text = r.tagged.text.trim();
    if (text.isEmpty && alert != null) text = alert;
    return ImapAuthException(text.isEmpty ? 'Authentication failed' : text, code: r.tagged.code?.name);
  }

  Future<void> _afterLogin(ImapResult r) async {
    _authenticated = true;
    final code = r.tagged.code;
    if (code?.name == 'CAPABILITY') {
      _applyCapabilityCode(code);
    } else if (r.ofType('CAPABILITY').isEmpty) {
      await refreshCapabilities();
    }
    if (supports('ID') && config.clientId.isNotEmpty) {
      try {
        await id(config.clientId);
      } on ImapException catch (e) {
        _log.fine('ID failed: $e');
      }
    }
  }

  /// Sends client identification and returns the server's.
  Future<Map<String, String>> id(Map<String, String> client) async {
    final parts = <Object>['ID ('];
    var first = true;
    for (final e in client.entries) {
      if (!first) parts.add(' ');
      first = false;
      parts
        ..addAll(_quotedOrLiteral(e.key))
        ..add(' ')
        ..addAll(_quotedOrLiteral(e.value));
    }
    parts.add(')');
    final r = await _run('ID', client.isEmpty ? ['ID NIL'] : parts);
    final out = <String, String>{};
    for (final u in r.ofType('ID')) {
      final items = u.data.isEmpty ? const <ImapValue>[] : u.data.first.items;
      for (var i = 0; i + 1 < items.length; i += 2) {
        final k = items[i].text;
        final v = items[i + 1].text;
        if (k != null && v != null) out[k.toLowerCase()] = v;
      }
    }
    return out;
  }

  /// Enables the given extensions among those advertised. Returns the set
  /// the server confirmed.
  Future<Set<String>> enable(Iterable<String> extensions) async {
    final wanted = [for (final e in extensions) if (supports(e)) e.toUpperCase()];
    if (wanted.isEmpty || !supports('ENABLE')) return const {};
    await _run('ENABLE', ['ENABLE ${wanted.join(' ')}']);
    return {for (final e in wanted) if (_enabled.contains(e)) e};
  }

  /// The personal namespace prefix and delimiter (e.g. `INBOX.` and `.`
  /// on Courier-style servers), or null without NAMESPACE support.
  Future<({String prefix, String? delimiter})?> personalNamespace() async {
    if (!supports('NAMESPACE')) return null;
    final r = await _run('NAMESPACE', ['NAMESPACE']);
    final ns = r.ofType('NAMESPACE').firstOrNull;
    if (ns == null || ns.data.isEmpty) return null;
    final personal = ns.data.first.items;
    if (personal.isEmpty) return null;
    final first = personal.first.items;
    if (first.isEmpty) return null;
    final prefix = _decodeName(first[0].text ?? '');
    final delimiter = first.length > 1 && !first[1].isNil ? first[1].text : null;
    return (prefix: prefix, delimiter: delimiter);
  }

  /// LIST, with SPECIAL-USE attributes and LIST-STATUS when supported.
  /// [statusItems] (e.g. `MESSAGES UIDNEXT`) are only requested if the
  /// server has LIST-STATUS; check [ImapMailboxInfo.status].
  Future<List<ImapMailboxInfo>> list({String pattern = '*', List<String> statusItems = const []}) async {
    final returns = <String>[];
    final extended = supports('LIST-EXTENDED');
    if (supports('SPECIAL-USE') && extended) returns.add('SPECIAL-USE');
    final listStatus = statusItems.isNotEmpty && supports('LIST-STATUS');
    if (listStatus) returns.add('STATUS (${statusItems.join(' ')})');
    final r = await _run('LIST', [
      'LIST "" ',
      ..._quotedOrLiteral(pattern),
      if (returns.isNotEmpty) ' RETURN (${returns.join(' ')})',
    ]);
    final statuses = <String, ImapMailboxStatus>{};
    for (final s in r.ofType('STATUS')) {
      if (s.data.length < 2) continue;
      statuses[s.data.first.text ?? ''] = ImapMailboxStatus.parse(s.data[1].items);
    }
    final out = <ImapMailboxInfo>[];
    for (final l in r.ofType('LIST')) {
      if (l.data.length < 3) continue;
      final encoded = l.data[2].text ?? '';
      final isInbox = encoded.toUpperCase() == 'INBOX';
      out.add(ImapMailboxInfo(
        name: isInbox ? 'INBOX' : _decodeName(encoded),
        encodedName: encoded,
        delimiter: l.data[1].isNil ? null : l.data[1].text,
        attributes: {for (final a in l.data[0].items) ?a.text?.toLowerCase()},
        status: statuses[encoded],
      ));
    }
    return out;
  }

  /// STATUS of a mailbox not currently selected.
  Future<ImapMailboxStatus> status(String mailbox, List<String> items) async {
    final r = await _run('STATUS', ['STATUS ', ..._mailbox(mailbox), ' (${items.join(' ')})']);
    final s = r.ofType('STATUS').firstOrNull;
    return s == null || s.data.length < 2 ? const ImapMailboxStatus() : ImapMailboxStatus.parse(s.data[1].items);
  }

  /// SELECT (or EXAMINE when [readOnly]). With [qresync] = (uidValidity,
  /// modseq, knownUids) and QRESYNC enabled, the result carries vanished
  /// UIDs and changed flags.
  Future<ImapSelected> select(
    String mailbox, {
    bool readOnly = false,
    ({int uidValidity, int modseq, UidSet? knownUids})? qresync,
  }) async {
    final selected = ImapSelected(mailbox, readOnly: readOnly);
    _selected = selected;
    String params = '';
    if (qresync != null && qresyncEnabled && qresync.modseq > 0) {
      final known = qresync.knownUids;
      params = ' (QRESYNC (${qresync.uidValidity} ${qresync.modseq}'
          '${known == null || known.isEmpty || known.toString().length > 2000 ? '' : ' $known'}))';
    } else if (supports('CONDSTORE') && !condstoreEnabled) {
      params = ' (CONDSTORE)';
    }
    final name = readOnly ? 'EXAMINE' : 'SELECT';
    try {
      final r = await _run(name, ['$name ', ..._mailbox(mailbox), params]);
      final code = r.tagged.code?.name;
      if (code == 'READ-ONLY') selected.readOnly = true;
      for (final f in r.ofType('FETCH')) {
        if (f.number != null) selected.changed.add(ImapFetch.parse(f.number!, f.data, utf8Names: utf8Enabled));
      }
      return selected;
    } catch (_) {
      if (identical(_selected, selected)) _selected = null;
      rethrow;
    }
  }

  /// UID FETCH (or FETCH by sequence numbers when [byUid] is false).
  /// [items] are raw fetch attributes (`FLAGS`, `BODY.PEEK[1]<0.2048>`...).
  /// Returns only responses that carry a UID when [byUid].
  Future<({List<ImapFetch> messages, UidSet vanished})> fetch(
    String set,
    List<String> items, {
    bool byUid = true,
    int? changedSince,
    bool vanished = false,
  }) async {
    final modifiers = <String>[
      if (changedSince != null) 'CHANGEDSINCE $changedSince',
      if (vanished && changedSince != null && qresyncEnabled) 'VANISHED',
    ];
    final cmd = byUid ? 'UID FETCH' : 'FETCH';
    final r = await _run(cmd, [
      '$cmd $set (${items.join(' ')})',
      if (modifiers.isNotEmpty) ' (${modifiers.join(' ')})',
    ]);
    final out = <ImapFetch>[];
    var gone = UidSet.empty;
    for (final u in r.untagged) {
      if (u.type == 'FETCH' && u.number != null) {
        final f = ImapFetch.parse(u.number!, u.data, utf8Names: utf8Enabled);
        if (!byUid || f.uid != null) out.add(f);
      } else if (u.type == 'VANISHED' && u.data.isNotEmpty && u.data.first is ImapList) {
        gone = gone.union(UidSet.parse(u.data.last.text ?? ''));
      }
    }
    return (messages: out, vanished: gone);
  }

  /// UID SEARCH with raw [criteria] parts (use [searchString] for user
  /// text). Uses ESEARCH when available so large results stay compact.
  Future<ImapSearchResult> search(List<Object> criteria, {bool needsCharset = false}) async {
    final esearch = supports('ESEARCH');
    final charset = needsCharset && !utf8Enabled ? 'CHARSET UTF-8 ' : '';
    final r = await _run('UID SEARCH', [
      'UID SEARCH ${esearch ? 'RETURN (ALL) ' : ''}$charset',
      ...criteria,
    ]);
    var ids = UidSet.empty;
    int? modseq;
    for (final u in r.untagged) {
      if (u.type == 'SEARCH') {
        final numbers = <int>[];
        for (final v in u.data) {
          if (v is ImapList) {
            final items = v.items;
            if (items.length >= 2 && items[0].text?.toUpperCase() == 'MODSEQ') modseq = items[1].asInt;
          } else if (v.asInt case final n?) {
            numbers.add(n);
          }
        }
        ids = ids.union(UidSet.of(numbers));
      } else if (u.type == 'ESEARCH') {
        final d = u.data;
        for (var i = 0; i < d.length; i++) {
          final key = d[i].text?.toUpperCase();
          if (key == 'ALL' && i + 1 < d.length) ids = ids.union(UidSet.parse(d[i + 1].text ?? ''));
          if (key == 'MODSEQ' && i + 1 < d.length) modseq = d[i + 1].asInt;
        }
      }
    }
    return ImapSearchResult(ids, highestModSeq: modseq);
  }

  /// A search key's string argument (quoted, or a literal for 8-bit text).
  List<Object> searchString(String text) => _quotedOrLiteral(text);

  /// Whether [text] needs `CHARSET UTF-8` in a SEARCH.
  static bool isNonAscii(String text) => text.codeUnits.any((c) => c > 0x7E);

  /// UID STORE, e.g. `store(set, '+FLAGS.SILENT', [r'\Seen'])` or
  /// `store(set, '-X-GM-LABELS', [r'\Inbox'])`.
  Future<void> store(UidSet uids, String action, List<String> values) async {
    final labels = action.toUpperCase().contains('X-GM-LABELS');
    for (final chunk in uids.chunks()) {
      final parts = <Object>['UID STORE $chunk $action ('];
      for (var i = 0; i < values.length; i++) {
        if (i > 0) parts.add(' ');
        final v = values[i];
        // Flags and system labels are atoms; user labels are strings.
        if (v.startsWith(r'\') || !labels) {
          parts.add(v);
        } else {
          parts.addAll(_quotedOrLiteral(utf8Enabled ? v : ModifiedUtf7.encode(v)));
        }
      }
      parts.add(')');
      await _run('UID STORE', parts);
    }
  }

  /// UID MOVE, falling back to COPY + \Deleted + (UID) EXPUNGE when the
  /// server lacks MOVE. Returns COPYUID data when the server reports it.
  Future<ImapCopyUid?> move(UidSet uids, String destination) async {
    if (uids.isEmpty) return null;
    final mapping = <int, int>{};
    int? uidValidity;
    for (final chunk in uids.chunks()) {
      ImapCopyUid? copy;
      if (supports('MOVE')) {
        final r = await _run('UID MOVE', ['UID MOVE $chunk ', ..._mailbox(destination)]);
        copy = ImapCopyUid.parse(r.tagged.code) ??
            r.untagged.map((u) => ImapCopyUid.parse(u.code)).nonNulls.firstOrNull;
      } else {
        copy = await _copy(chunk, destination);
        await store(chunk, '+FLAGS.SILENT', const [r'\Deleted']);
        await expunge(chunk);
      }
      if (copy != null) {
        uidValidity = copy.uidValidity;
        mapping.addAll(copy.mapping);
      }
    }
    return uidValidity == null ? null : ImapCopyUid(uidValidity, mapping);
  }

  Future<ImapCopyUid?> copy(UidSet uids, String destination) async {
    final mapping = <int, int>{};
    int? uidValidity;
    for (final chunk in uids.chunks()) {
      final c = await _copy(chunk, destination);
      if (c != null) {
        uidValidity = c.uidValidity;
        mapping.addAll(c.mapping);
      }
    }
    return uidValidity == null ? null : ImapCopyUid(uidValidity, mapping);
  }

  Future<ImapCopyUid?> _copy(UidSet chunk, String destination) async {
    final r = await _run('UID COPY', ['UID COPY $chunk ', ..._mailbox(destination)]);
    return ImapCopyUid.parse(r.tagged.code);
  }

  /// Permanently removes [uids] (which must already be `\Deleted`). Uses
  /// UID EXPUNGE (UIDPLUS); without it, plain EXPUNGE also removes other
  /// `\Deleted` messages in the mailbox, which is what other clients
  /// expect to happen eventually anyway.
  Future<void> expunge([UidSet? uids]) async {
    if (uids != null && supports('UIDPLUS')) {
      for (final chunk in uids.chunks()) {
        await _run('UID EXPUNGE', ['UID EXPUNGE $chunk']);
      }
      return;
    }
    await _run('EXPUNGE', ['EXPUNGE']);
  }

  /// APPEND. Returns APPENDUID data when the server reports it.
  Future<ImapAppendUid?> append(
    String mailbox,
    Uint8List message, {
    Iterable<String> flags = const [],
    DateTime? date,
  }) async {
    final r = await _run('APPEND', [
      'APPEND ',
      ..._mailbox(mailbox),
      if (flags.isNotEmpty) ' (${flags.join(' ')})',
      if (date != null) ' "${formatInternalDate(date)}"',
      ' ',
      ImapLiteral(message),
    ]);
    return ImapAppendUid.parse(r.tagged.code);
  }

  /// CREATE. An `ALREADYEXISTS` refusal counts as success.
  Future<void> create(String mailbox) async {
    final r = await _run('CREATE', ['CREATE ', ..._mailbox(mailbox)], check: false);
    if (r.isOk || r.tagged.code?.name == 'ALREADYEXISTS') return;
    r.check();
  }

  Future<void> subscribe(String mailbox) => _run('SUBSCRIBE', ['SUBSCRIBE ', ..._mailbox(mailbox)]);

  Future<void> noop() => _run('NOOP', ['NOOP']);

  /// Leaves the selected mailbox without expunging.
  Future<void> unselect() async {
    if (_selected == null) return;
    if (supports('UNSELECT')) {
      await _run('UNSELECT', ['UNSELECT']);
    }
    _selected = null;
  }

  /// One IDLE cycle: idles until [stop] completes, [maxDuration] passes
  /// (default [ImapClientConfig.idleRestart]) or the server ends it, then
  /// sends DONE. Events arrive on [events] meanwhile.
  Future<void> idle({Future<void>? stop, Duration? maxDuration}) async {
    if (!supports('IDLE')) throw const ImapProtocolException('The server does not support IDLE');
    final started = Completer<void>();
    late final ImapCommand command;
    command = ImapCommand('IDLE', ['IDLE'], onContinuation: (_) {
      if (!started.isCompleted) {
        // The server may now stay silent until something changes.
        command.timeoutExempt = true;
        _conn.refreshTimeout();
        started.complete();
      }
      return null;
    });
    var finished = false;
    final result = _conn.send(command);
    final settled = result.then<void>((_) => finished = true, onError: (Object _) => finished = true);
    await Future.any([started.future, settled]);
    if (started.isCompleted && !finished) {
      final timeUp = Completer<void>();
      final ticker = Timer(maxDuration ?? config.idleRestart, timeUp.complete);
      try {
        await Future.any([settled, timeUp.future, ?stop]);
      } finally {
        ticker.cancel();
      }
      if (!finished && !_conn.isClosed) {
        command.timeoutExempt = false;
        _conn
          ..writeLine('DONE')
          ..refreshTimeout();
      }
    }
    (await result).check();
  }

  /// LOGOUT and close. Never throws.
  Future<void> logout() async {
    if (_conn.isClosed) return;
    try {
      await _conn.send(ImapCommand('LOGOUT', ['LOGOUT'])).timeout(const Duration(seconds: 5));
    } on Object {
      // Best effort: the server may close first.
    }
    await _conn.close();
    await _events.close();
  }

  /// Closes the connection immediately.
  void destroy() {
    _conn.destroy();
    unawaited(_events.close());
  }

  // Encoding helpers -------------------------------------------------------

  /// Encodes a decoded mailbox name for a command.
  List<Object> _mailbox(String name) {
    if (name.toUpperCase() == 'INBOX') return const ['INBOX'];
    return _quotedOrLiteral(encodeMailboxName(name));
  }

  /// The wire form of a decoded mailbox name: UTF-8 with UTF8=ACCEPT,
  /// modified UTF-7 otherwise.
  String encodeMailboxName(String name) => utf8Enabled ? name : ModifiedUtf7.encode(name);

  String _decodeName(String wire) => utf8Enabled ? wire : ModifiedUtf7.decode(wire);

  /// A string argument: quoted when possible, else a literal.
  List<Object> _quotedOrLiteral(String s) {
    var quotable = true;
    for (final c in s.codeUnits) {
      if (c == 0 || c == 0x0D || c == 0x0A || (c > 0x7E && !utf8Enabled)) {
        quotable = false;
        break;
      }
    }
    if (quotable) return ['"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"'];
    return [ImapLiteral(Uint8List.fromList(utf8.encode(s)))];
  }
}
