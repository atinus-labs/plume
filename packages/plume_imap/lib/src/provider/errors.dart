import 'dart:async';
import 'dart:io';

import 'package:plume_core/plume_core.dart';

import '../imap/imap_exception.dart';

/// Runs async actions one at a time, in call order.
final class Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }
}

/// Maps IMAP, socket and TLS failures onto the engine's [MailException]s:
/// connection trouble is transient, refused logins are auth errors, and
/// refused commands are permanent unless their response code says
/// otherwise.
MailException toMailException(Object error) {
  switch (error) {
    case MailException():
      return error;
    case ImapAuthException(isTemporary: true):
      // "Too many simultaneous connections", "[UNAVAILABLE] Try again
      // later": not a reason to ask the user for the password again.
      return TransientException(error.serverText, error);
    case ImapAuthException():
      return AuthException(error.serverText, error);
    case ImapCommandException(:final code):
      return switch (code) {
        'AUTHENTICATIONFAILED' || 'AUTHORIZATIONFAILED' || 'EXPIRED' => AuthException(error.serverText, error),
        'NONEXISTENT' => NotFoundException(error.serverText, error),
        'UNAVAILABLE' || 'INUSE' || 'LIMIT' || 'SERVERBUG' => TransientException(error.serverText, error),
        _ => PermanentException('${error.command} failed: ${error.serverText}', error),
      };
    case ImapSecurityException():
      // Possibly a downgrade attack or a server misconfiguration; never
      // fall back, but keep retrying in case it is temporary.
      return TransientException(error.message, error);
    case ImapException():
      return TransientException(error.message, error);
    case SocketException():
      return TransientException('Network error: ${error.message}', error);
    case TlsException():
      return TransientException('Secure connection failed: ${error.message}', error);
    case TimeoutException():
      return TransientException('The mail server did not respond in time', error);
  }
  return TransientException('Unexpected error: $error', error);
}

/// Runs [action], converting failures with [toMailException]. Programming
/// errors (`Error`s) propagate unchanged.
Future<T> guarded<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on Error {
    rethrow;
  } on Object catch (e) {
    throw toMailException(e);
  }
}
