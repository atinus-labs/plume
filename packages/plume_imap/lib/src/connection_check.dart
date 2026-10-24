/// Which server a connection check was talking to.
enum MailProtocol { imap, smtp }

/// Why a server could not be used. Precise enough for the account setup UI
/// to tell the user what to fix.
enum ConnectionFailure {
  /// The host name does not resolve.
  hostNotFound,

  /// Connection refused, no route, or the network is down.
  unreachable,

  /// No answer within the timeout.
  timeout,

  /// The server's TLS certificate is not trusted or does not match the
  /// host name.
  certificate,

  /// Another TLS handshake failure, typically the wrong security mode for
  /// the port (TLS on a STARTTLS port or vice versa).
  tls,

  /// [ConnectionSecurity.startTls] was requested but the server does not
  /// offer STARTTLS.
  startTlsUnavailable,

  /// The server rejected the username or password.
  authFailed,

  /// The server refused for now without judging the credentials: too many
  /// connections, temporarily unavailable, try again later.
  serverBusy,

  /// The server does not speak the expected protocol (wrong port?) or
  /// answered something unexpected.
  protocol,
}

/// Thrown by the connection checks used during account setup.
final class ConnectionCheckException implements Exception {
  const ConnectionCheckException(
    this.failure, {
    required this.protocol,
    required this.host,
    this.serverMessage,
  });

  final ConnectionFailure failure;
  final MailProtocol protocol;
  final String host;

  /// The server's own explanation, when it gave one (Gmail answers a normal
  /// password with "Application-specific password required").
  final String? serverMessage;

  @override
  String toString() =>
      'ConnectionCheckException(${protocol.name} $host: ${failure.name}'
      '${serverMessage == null ? '' : ' - $serverMessage'})';
}
