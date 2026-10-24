/// Base class for failures surfaced by providers. The sync engine decides how
/// to react based on the subtype, so providers must map their native errors
/// onto these.
sealed class MailException implements Exception {
  const MailException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// Credentials are missing, expired beyond refresh, or revoked. The account
/// needs the user to sign in again; retrying will not help.
final class AuthException extends MailException {
  const AuthException(super.message, [super.cause]);
}

/// Network unreachable, timeouts, 5xx, rate limiting. Safe to retry later.
final class TransientException extends MailException {
  const TransientException(super.message, [super.cause, this.retryAfter]);

  /// Server-suggested delay before retrying, if any.
  final Duration? retryAfter;
}

/// The referenced object no longer exists on the server.
final class NotFoundException extends MailException {
  const NotFoundException(super.message, [super.cause]);
}

/// The incremental sync cursor is too old; a full resync is required.
final class SyncCursorExpiredException extends MailException {
  const SyncCursorExpiredException(super.message, [super.cause]);
}

/// The request was rejected and retrying will not change that (4xx other
/// than auth/not-found). The operation should be dropped.
final class PermanentException extends MailException {
  const PermanentException(super.message, [super.cause]);
}
