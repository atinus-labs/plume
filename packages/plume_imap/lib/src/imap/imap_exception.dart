/// Failures of the IMAP client. The provider maps these onto `MailException`
/// subtypes; [checkImapLogin] maps them onto `ConnectionFailure`s.
sealed class ImapException implements Exception {
  const ImapException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server answered a command with `NO` or `BAD`.
final class ImapCommandException extends ImapException {
  const ImapCommandException({
    required this.command,
    required this.status,
    this.code,
    required String text,
  }) : super(text);

  /// The command name (e.g. `UID MOVE`), never its arguments.
  final String command;

  /// `NO` or `BAD`.
  final String status;

  /// The response code without brackets, upper-cased (`TRYCREATE`,
  /// `AUTHENTICATIONFAILED`, `NONEXISTENT`...), if any.
  final String? code;

  /// The server's text, with the response code, e.g.
  /// `[ALERT] Application-specific password required`.
  String get serverText => code == null ? message : '[$code] $message';

  bool get isNo => status == 'NO';

  @override
  String toString() => 'ImapCommandException($command: $status ${code == null ? '' : '[$code] '}$message)';
}

/// Login was refused (credentials, or no permitted mechanism).
final class ImapAuthException extends ImapException {
  const ImapAuthException(super.message, {this.code});

  /// Response code of the refusal, if any (`AUTHENTICATIONFAILED`,
  /// `ALERT`, `UNAVAILABLE`...).
  final String? code;

  /// The text including its response code, as the server wrote it.
  String get serverText => code == null ? message : '[$code] $message';

  static const _temporaryCodes = {'UNAVAILABLE', 'LIMIT', 'INUSE', 'SERVERBUG', 'OVERQUOTA'};
  static final _temporaryText = RegExp(
    r'too many (simultaneous )?(connections|logins|login attempts)|temporar|try again|later|unavailable|'
    r'overloaded|rate.?limit|throttl|maintenance|system problem|lookup failed',
    caseSensitive: false,
  );

  /// The refusal is not about the credentials (server busy, too many
  /// connections, temporary failure), so the login should be retried
  /// later rather than the password questioned. RFC 5530 codes
  /// `AUTHENTICATIONFAILED`, `AUTHORIZATIONFAILED` and `EXPIRED` are
  /// always about the credentials.
  bool get isTemporary {
    final c = code;
    if (c == 'AUTHENTICATIONFAILED' || c == 'AUTHORIZATIONFAILED' || c == 'EXPIRED') return false;
    if (c != null && _temporaryCodes.contains(c)) return true;
    return _temporaryText.hasMatch(message);
  }
}

/// The connection failed, was closed by the server (`BYE`) or by us.
final class ImapConnectionException extends ImapException {
  const ImapConnectionException(super.message, [this.cause]);

  final Object? cause;

  @override
  String toString() => 'ImapConnectionException: $message${cause == null ? '' : ' ($cause)'}';
}

/// The server did not answer within the configured time. The connection
/// has been closed.
final class ImapTimeoutException extends ImapException {
  const ImapTimeoutException(super.message);
}

/// The server sent something that is not IMAP, or broke a limit.
final class ImapProtocolException extends ImapException {
  const ImapProtocolException(super.message);
}

/// The requested connection security cannot be established: STARTTLS was
/// required but not offered, or plaintext was requested for a remote host.
final class ImapSecurityException extends ImapException {
  const ImapSecurityException(super.message, {this.startTlsUnavailable = false});

  final bool startTlsUnavailable;
}
