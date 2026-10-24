import 'smtp_reply.dart';

/// What went wrong in an SMTP session.
enum SmtpErrorKind {
  /// The host name does not resolve.
  hostNotFound,

  /// The TCP connection could not be made.
  unreachable,

  /// The server did not answer in time.
  timeout,

  /// The connection broke after it was established.
  connectionLost,

  /// The server certificate is not trusted or not valid for the host.
  certificate,

  /// Another TLS failure, usually the wrong security mode for the port.
  tls,

  /// STARTTLS was required but the server does not offer it.
  startTlsUnavailable,

  /// An unencrypted connection to a remote host was requested.
  insecure,

  /// The peer is not an SMTP server or broke the protocol.
  protocol,

  /// The server rejected the credentials.
  authFailed,

  /// The server offers no sign-in method Plume supports.
  authUnavailable,

  /// The server refused a command; see [SmtpException.reply].
  rejected,

  /// One or more recipients were refused; nothing was sent.
  recipientRejected,

  /// The message exceeds the server's advertised SIZE limit.
  messageTooLarge,

  /// An address cannot be put into an SMTP command.
  invalidAddress,
}

/// A failed SMTP operation. [message] is written for the end user.
final class SmtpException implements Exception {
  const SmtpException(this.kind, this.message, {this.reply, this.recipients = const [], this.serverText, this.cause});

  final SmtpErrorKind kind;
  final String message;

  /// The server reply that caused the failure, if any.
  final SmtpReply? reply;

  /// For [SmtpErrorKind.recipientRejected]: the refused addresses.
  final List<String> recipients;

  /// What a peer that is not speaking SMTP said instead (truncated).
  final String? serverText;

  /// The server's own words, for showing next to [message].
  String? get serverMessage => reply?.message ?? serverText;

  /// The underlying I/O error, if any.
  final Object? cause;

  /// Whether trying again later could succeed: network trouble, timeouts
  /// and 4xx replies. A broken TLS handshake is included because hotel and
  /// airport networks intercept connections until the user signs in.
  bool get isTransient => switch (kind) {
    SmtpErrorKind.hostNotFound ||
    SmtpErrorKind.unreachable ||
    SmtpErrorKind.timeout ||
    SmtpErrorKind.connectionLost ||
    SmtpErrorKind.certificate ||
    SmtpErrorKind.tls ||
    SmtpErrorKind.startTlsUnavailable ||
    SmtpErrorKind.protocol => true,
    SmtpErrorKind.rejected || SmtpErrorKind.recipientRejected => reply?.isTransient ?? false,
    SmtpErrorKind.authFailed ||
    SmtpErrorKind.insecure ||
    SmtpErrorKind.authUnavailable ||
    SmtpErrorKind.messageTooLarge ||
    SmtpErrorKind.invalidAddress => false,
  };

  @override
  String toString() => 'SmtpException(${kind.name}: $message${reply == null ? '' : ' [$reply]'})';
}
