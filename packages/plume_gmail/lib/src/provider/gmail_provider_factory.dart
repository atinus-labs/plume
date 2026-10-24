import 'package:http/http.dart' as http;
import 'package:plume_core/plume_core.dart';

import '../api/gmail_client.dart';
import '../imap/imap_doorbell.dart';
import 'gmail_provider.dart';

/// Registers Gmail with the engine. Register one instance; it creates a
/// [GmailProvider] per account from that account's [TokenSource]
/// (normally a `GoogleTokenSource`).
final class GmailProviderFactory implements MailProviderFactory {
  const GmailProviderFactory({
    this.httpClient,
    this.clientConfig = const GmailClientConfig(),
    this.syncConfig = const GmailSyncConfig(),
    this.imapConfig = const ImapDoorbellConfig(),
    this.imapConnector,
  });

  /// Shared HTTP client; when null each provider owns its own.
  final http.Client? httpClient;
  final GmailClientConfig clientConfig;
  final GmailSyncConfig syncConfig;
  final ImapDoorbellConfig imapConfig;
  final ImapConnector? imapConnector;

  @override
  String get kind => GmailProvider.kind;

  @override
  MailProvider create(Account account, TokenSource tokens) => GmailProvider(
        account: account,
        tokens: tokens,
        httpClient: httpClient,
        clientConfig: clientConfig,
        syncConfig: syncConfig,
        imapConfig: imapConfig,
        imapConnector: imapConnector,
      );
}
