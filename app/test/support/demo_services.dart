import 'package:plume/src/demo/demo_provider.dart';
import 'package:plume/src/platform/linux/linux_desktop.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/imap_connector.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/services/window_frame.dart';
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

/// A window on a floating desktop, laid out as GTK's [layout] says. Its
/// buttons do nothing.
class DemoWindowFrame extends WindowFrame {
  DemoWindowFrame({String layout = ''}) : _buttons = parseDecorationLayout(layout);

  final (List<WindowButton>, List<WindowButton>) _buttons;

  @override
  TitleBar get defaultStyle => TitleBar.plume;
  @override
  bool get maximized => false;
  @override
  List<WindowButton> get leading => _buttons.$1;
  @override
  List<WindowButton> get trailing => _buttons.$2;
  @override
  Future<void> apply(TitleBar style) async {}
  @override
  Future<void> startMove() async {}
  @override
  Future<void> showMenu() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
}

/// An in-memory store holding only the demo account, already synced. Nothing
/// touches the user's real mail or settings. With a [frame], Plume draws its
/// title bar as on a floating desktop.
Future<Services> demoServices({WindowFrame? frame}) async {
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
    desktop: HeadlessDesktop(windowFrame: frame),
    secrets: NoSecrets(),
    accounts: accounts,
    initialSettings: const AppSettings(),
  );
}
