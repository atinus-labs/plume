import 'dart:typed_data';

import 'settings.dart';

/// Delivers an already encoded RFC 5322 message. Implemented over SMTP by
/// `SmtpMailSender`; the IMAP provider takes it as a constructor argument so
/// tests can substitute a fake.
abstract interface class MailSender {
  /// Sends [data] to [recipients] (bare addresses) with [from] as the
  /// envelope sender, logging in as [username].
  ///
  /// Throws `AuthException` when the login is rejected,
  /// `TransientException` for network failures and 4xx replies, and
  /// `PermanentException` for 5xx replies. If the server refuses any
  /// recipient, nothing is sent and the exception names that address.
  Future<void> send({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String from,
    required List<String> recipients,
    required Uint8List data,
  });
}
