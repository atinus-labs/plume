import 'package:plume/src/demo/demo_provider.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/imap_connector.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

class NoSecrets implements SecretStore {
  @override
  String get backend => 'test';
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

/// An in-memory store holding only the demo account, already synced. Nothing
/// touches the user's real mail or settings.
Future<Services> demoServices() async {
  final store = DriftMailStore.inMemory();
  final accounts = AccountsService(store: store, connectors: [DemoConnector(), ImapConnector(NoSecrets())]);
  final engine = MailEngine(store: store, factories: accounts.factories, tokenSourceFor: accounts.tokenSourceFor);
  accounts.engine = engine;
  await engine.start();
  await accounts.add('demo');
  // Let the initial sync land.
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if ((engine.currentStatuses.values.firstOrNull?.initialSyncDone ?? false)) break;
  }
  return Services(
    store: store,
    engine: engine,
    desktop: HeadlessDesktop(),
    secrets: NoSecrets(),
    accounts: accounts,
    initialSettings: const AppSettings(),
  );
}
