import 'package:plume_imap/plume_imap.dart';

/// Logs in to both servers of a mail server account. Returns [settings]
/// adjusted to what the server turned out to be: Gmail files sent mail by
/// itself, so Plume must not add a second copy.
///
/// Throws [ConnectionCheckException] for the first problem found.
Future<MailServerSettings> verifyServerAccount(MailServerSettings settings, String password) async {
  final results = await Future.wait<Object?>([
    checkImapLogin(settings.imap, settings.username, password),
    checkSmtpLogin(settings.smtp, settings.smtpUsername, password),
  ]);
  final imap = results.first! as ImapLoginInfo;
  return imap.isGmail ? settings.copyWith(saveSentCopy: false) : settings;
}

/// App passwords are shown in groups ("abcd efgh ijkl mnop") and often
/// pasted that way; the spaces are not part of the password.
String cleanPassword(String password, ProviderInfo? provider) =>
    provider?.needsAppPassword == true ? password.replaceAll(RegExp(r'\s'), '') : password;

/// A sentence telling the user what went wrong and what to change.
String describeServerProblem(ConnectionCheckException e, {ProviderInfo? provider}) {
  final host = e.host;
  final which = e.protocol == MailProtocol.imap ? 'incoming' : 'outgoing';
  return switch (e.failure) {
    ConnectionFailure.authFailed when provider?.needsAppPassword == true =>
      '${provider!.name} didn’t accept that password. It needs an app password, not your normal one.',
    ConnectionFailure.authFailed when e.protocol == MailProtocol.smtp =>
      'The outgoing mail server ($host) didn’t accept the password, although the incoming one did.',
    ConnectionFailure.authFailed => 'The server didn’t accept that email and password.',
    ConnectionFailure.serverBusy => '$host is busy and turned Plume away for now. Try again in a few minutes.',
    ConnectionFailure.hostNotFound => 'There’s no server called $host. Check the $which server name.',
    ConnectionFailure.unreachable => 'Couldn’t connect to $host. Check the $which port and your internet connection.',
    ConnectionFailure.timeout => '$host didn’t answer in time. Check the $which server name and port.',
    ConnectionFailure.certificate =>
      '$host’s security certificate isn’t valid for that name, so Plume didn’t connect. '
          'Check the $which server name.',
    ConnectionFailure.tls =>
      'Couldn’t open a secure connection to $host. Check that security matches the port '
          '(SSL/TLS uses 993 and 465, STARTTLS uses 143 and 587).',
    ConnectionFailure.startTlsUnavailable => '$host doesn’t offer STARTTLS. Choose SSL/TLS instead.',
    ConnectionFailure.protocol =>
      '$host didn’t answer like an ${e.protocol == MailProtocol.imap ? 'IMAP' : 'SMTP'} server. '
          'Check the $which port.',
  };
}
