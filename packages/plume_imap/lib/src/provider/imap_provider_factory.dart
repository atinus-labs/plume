import 'package:plume_core/plume_core.dart';

import '../mail_sender.dart';
import '../smtp/smtp_mail_sender.dart';
import 'context.dart';
import 'imap_provider.dart';
import 'session_pool.dart';

/// Registers IMAP/SMTP accounts (`Account.provider == 'imap'`) with the
/// engine. Server settings come from `Account.providerConfig`
/// (`MailServerSettings.toJson`); the account's [TokenSource] supplies the
/// password.
final class ImapProviderFactory implements MailProviderFactory {
  /// [sender] delivers outgoing mail; SMTP by default. [config] tunes sync
  /// windows and timeouts; [opener] replaces how connections are opened
  /// (tests).
  const ImapProviderFactory({this._sender, this.config = const ImapSyncConfig(), this.opener});

  final MailSender? _sender;
  final ImapSyncConfig config;
  final ImapOpener? opener;

  @override
  String get kind => ImapProvider.kind;

  @override
  MailProvider create(Account account, TokenSource tokens) => ImapProvider(
        account: account,
        tokens: tokens,
        sender: _sender ?? const SmtpMailSender(),
        config: config,
        opener: opener,
      );
}
