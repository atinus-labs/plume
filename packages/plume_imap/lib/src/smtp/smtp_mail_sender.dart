import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';

import '../connection_check.dart';
import '../mail_sender.dart';
import '../settings.dart';
import 'smtp_client.dart';
import 'smtp_exception.dart';

/// [MailSender] over SMTP submission: one connection per message.
///
/// Errors map onto the provider contract: a rejected sign-in becomes
/// [AuthException] (keeping the server's explanation, such as Gmail's
/// "Application-specific password required"), network trouble, TLS
/// failures and 4xx replies become [TransientException], and 5xx replies
/// become [PermanentException]. All messages are written for the user.
///
/// A connection lost after the message was uploaded is reported as
/// transient although the server may have accepted it; a retry can then
/// deliver it twice, which is the lesser evil compared to losing it.
final class SmtpMailSender implements MailSender {
  const SmtpMailSender({this.config = const SmtpConfig()});

  final SmtpConfig config;

  @override
  Future<void> send({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String from,
    required List<String> recipients,
    required Uint8List data,
  }) async {
    final client = SmtpClient(endpoint, config: config);
    try {
      SmtpClient.checkEnvelope(from, recipients);
      await client.connect();
      await client.login(username, password);
      await client.send(from: from, recipients: recipients, data: data);
      await client.quit();
    } on SmtpException catch (e) {
      throw switch (e) {
        SmtpException(kind: SmtpErrorKind.authFailed) => AuthException(e.message, e),
        SmtpException(isTransient: true) => TransientException(e.message, e),
        _ => PermanentException(e.message, e),
      };
    } on IOException catch (e) {
      throw TransientException('The connection to the outgoing mail server ${endpoint.host} failed.', e);
    } finally {
      client.destroy();
    }
  }
}

/// Checks that [username] and [password] can sign in to the SMTP server at
/// [endpoint]: connect, STARTTLS when configured, EHLO, AUTH, QUIT. Used by
/// account setup before anything is saved.
///
/// Throws [ConnectionCheckException] naming the exact [ConnectionFailure],
/// with the server's own text in `serverMessage` when it gave one. The
/// whole check is bounded by [timeout].
///
/// [securityContext] replaces the system's trusted certificates; it exists
/// for tests.
Future<void> checkSmtpLogin(
  ServerEndpoint endpoint,
  String username,
  String password, {
  Duration timeout = const Duration(seconds: 20),
  SecurityContext? securityContext,
}) async {
  final client = SmtpClient(
    endpoint,
    config: SmtpConfig(connectTimeout: timeout, replyTimeout: timeout, securityContext: securityContext),
  );
  ConnectionCheckException fail(ConnectionFailure failure, [String? serverMessage]) =>
      ConnectionCheckException(failure, protocol: MailProtocol.smtp, host: endpoint.host, serverMessage: serverMessage);
  try {
    Future<void> check() async {
      await client.connect();
      await client.login(username, password);
    }

    await check().timeout(timeout);
    await client.quit();
  } on TimeoutException {
    throw fail(ConnectionFailure.timeout);
  } on SmtpException catch (e) {
    throw fail(connectionFailureFor(e), e.serverMessage);
  } on IOException {
    throw fail(ConnectionFailure.unreachable);
  } finally {
    client.destroy();
  }
}

/// The setup-screen classification of an SMTP failure.
ConnectionFailure connectionFailureFor(SmtpException e) => switch (e.kind) {
  // 421/454 and friends: the server is refusing for now.
  SmtpErrorKind.rejected when e.isTransient => ConnectionFailure.serverBusy,
  SmtpErrorKind.hostNotFound => ConnectionFailure.hostNotFound,
  SmtpErrorKind.unreachable || SmtpErrorKind.connectionLost => ConnectionFailure.unreachable,
  SmtpErrorKind.timeout => ConnectionFailure.timeout,
  SmtpErrorKind.certificate => ConnectionFailure.certificate,
  SmtpErrorKind.tls || SmtpErrorKind.insecure => ConnectionFailure.tls,
  SmtpErrorKind.startTlsUnavailable => ConnectionFailure.startTlsUnavailable,
  SmtpErrorKind.authFailed => ConnectionFailure.authFailed,
  SmtpErrorKind.protocol ||
  SmtpErrorKind.authUnavailable ||
  SmtpErrorKind.rejected ||
  SmtpErrorKind.recipientRejected ||
  SmtpErrorKind.messageTooLarge ||
  SmtpErrorKind.invalidAddress => ConnectionFailure.protocol,
};
