import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import '../connection_check.dart';
import '../settings.dart';
import 'imap_client.dart';
import 'imap_exception.dart';

final Logger _log = Logger('plume.imap');

/// What a successful IMAP login revealed about the server.
final class ImapLoginInfo {
  const ImapLoginInfo({required this.isGmail, required this.capabilities});

  /// The server speaks Gmail's IMAP extensions (X-GM-EXT-1).
  final bool isGmail;

  /// Upper-cased capabilities after login.
  final Set<String> capabilities;
}

/// Connects to [endpoint], logs in, and logs out, for the account setup
/// screen. Throws [ConnectionCheckException] describing precisely what
/// failed; the server's own text (e.g. Gmail's "[ALERT]
/// Application-specific password required") is kept in
/// [ConnectionCheckException.serverMessage].
Future<ImapLoginInfo> checkImapLogin(
  ServerEndpoint endpoint,
  String username,
  String password, {
  Duration timeout = const Duration(seconds: 20),
  SecurityContext? securityContext,
}) async {
  ConnectionCheckException fail(ConnectionFailure failure, [String? message]) =>
      ConnectionCheckException(failure, protocol: MailProtocol.imap, host: endpoint.host, serverMessage: message);

  ImapClient? client;
  try {
    final config = ImapClientConfig(connectTimeout: timeout, responseTimeout: timeout, securityContext: securityContext);
    // Every step (connect, TLS, greeting, each command) has its own
    // timeout inside the client, so nothing here can hang.
    client = await ImapClient.connect(endpoint, config: config);
    await client.login(username, password);
    final info = ImapLoginInfo(isGmail: client.isGmail, capabilities: client.capabilities);
    await client.logout();
    return info;
  } on Object catch (e) {
    client?.destroy();
    final failure = classifyImapFailure(e);
    if (failure == null) rethrow;
    _log.fine('IMAP check for ${endpoint.host} failed: ${failure.failure.name}');
    throw fail(failure.failure, failure.message);
  }
}

/// Maps a connection or login error onto a [ConnectionFailure] and the
/// server's explanation. Returns null for errors that are not about the
/// connection (programming errors).
({ConnectionFailure failure, String? message})? classifyImapFailure(Object e) {
  switch (e) {
    case ImapAuthException(isTemporary: true):
      // The server is busy or limiting connections; the credentials were
      // not judged.
      return (failure: ConnectionFailure.serverBusy, message: e.serverText);
    case ImapAuthException():
      return (failure: ConnectionFailure.authFailed, message: e.serverText);
    case ImapSecurityException(:final startTlsUnavailable):
      return (failure: startTlsUnavailable ? ConnectionFailure.startTlsUnavailable : ConnectionFailure.tls, message: e.message);
    case ImapTimeoutException():
      return (failure: ConnectionFailure.timeout, message: null);
    case ImapProtocolException():
      return (failure: ConnectionFailure.protocol, message: e.message);
    case ImapCommandException():
      return (failure: ConnectionFailure.protocol, message: e.serverText);
    case ImapConnectionException(:final cause):
      if (cause != null) {
        final inner = classifyImapFailure(cause);
        if (inner != null) return inner;
      }
      // Closed during the greeting or login: usually TLS expected on a
      // plaintext port, or the server rejected us outright.
      return (failure: ConnectionFailure.protocol, message: e.message);
    case TimeoutException():
      return (failure: ConnectionFailure.timeout, message: null);
    case HandshakeException():
      return (failure: _isCertificateError(e) ? ConnectionFailure.certificate : ConnectionFailure.tls, message: e.message);
    case TlsException():
      return (failure: ConnectionFailure.tls, message: e.message);
    case SocketException():
      return (failure: _socketFailure(e), message: null);
  }
  return null;
}

bool _isCertificateError(HandshakeException e) {
  final text = '${e.message} ${e.osError?.message ?? ''}'.toUpperCase();
  return text.contains('CERTIFICATE') || text.contains('HOSTNAME') || text.contains('HOST NAME');
}

ConnectionFailure _socketFailure(SocketException e) {
  final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
  final code = e.osError?.errorCode;
  // getaddrinfo failures: "Failed host lookup", EAI_NONAME (-2), EAI_AGAIN (-3).
  if (text.contains('host lookup') || text.contains('name or service not known') || text.contains('nodename nor servname')) {
    return ConnectionFailure.hostNotFound;
  }
  if (code == 110 || code == 60 || text.contains('timed out')) return ConnectionFailure.timeout;
  return ConnectionFailure.unreachable;
}
