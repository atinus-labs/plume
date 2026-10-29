import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

import 'config.dart';
import 'demo/demo_provider.dart';
import 'platform/linux/graphics_engine.dart';
import 'services/accounts.dart';
import 'services/desktop.dart';
import 'services/platform_desktop.dart';
import 'services/secret_store.dart';
import 'state/services.dart';
import 'state/settings.dart';

/// Creates every long-lived service before the first frame.
Future<Services> bootstrap(List<String> args) async {
  _configureLogging();
  final dataDir = await _dataDirectory();
  await dataDir.create(recursive: true);

  final store = DriftMailStore.open(p.join(dataDir.path, 'mail.sqlite'));
  final secrets = SystemSecretStore(fallbackDir: dataDir.path);
  final connectors = <AccountConnector>[
    ...platformConnectors(secrets),
    if (AppConfig.demo) DemoConnector(),
  ];
  final accounts = AccountsService(store: store, connectors: connectors);
  final settings = await SettingsNotifier.load(store.readSetting(SettingsNotifier.storageKey));
  final engine = MailEngine(
    store: store,
    factories: accounts.factories,
    tokenSourceFor: accounts.tokenSourceFor,
    foregroundInterval: settings.foregroundSyncInterval,
    backgroundInterval: settings.backgroundSyncInterval,
  );
  accounts.engine = engine;
  final DesktopIntegration desktop = createDesktopIntegration(startHidden: args.contains('--background'));
  await desktop.start();
  await desktop.setPreventClose(settings.runInBackground && desktop.hasTray);
  await engine.start();
  if (AppConfig.demo && (await store.accounts()).isEmpty && Platform.environment['PLUME_DEMO_AUTOADD'] == '1') {
    await accounts.add('demo');
  }

  return Services(
    store: store,
    engine: engine,
    desktop: desktop,
    secrets: secrets,
    accounts: accounts,
    initialSettings: settings,
    graphicsEngine: Platform.isLinux ? GraphicsEngineSetting.load(dataDir.path) : null,
  );
}

/// `$XDG_DATA_HOME/plume` on Linux (also correct inside Flatpak), the
/// platform support directory elsewhere.
Future<Directory> _dataDirectory() async {
  if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');
    return Directory(p.join(base, 'plume'));
  }
  return getApplicationSupportDirectory();
}

void _configureLogging() {
  Logger.root.level = kReleaseMode ? Level.INFO : Level.FINE;
  Logger.root.onRecord.listen((r) {
    final line = '${r.time.toIso8601String().substring(11, 23)} ${r.level.name.padRight(7)} ${r.loggerName}: ${r.message}'
        '${r.error == null ? '' : '  ${r.error}'}';
    stderr.writeln(line);
    if (r.stackTrace != null && r.level >= Level.SEVERE) stderr.writeln(r.stackTrace);
  });
}
