import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';

import '../platform/linux/graphics_engine.dart';
import '../services/accounts.dart';
import '../services/desktop.dart';
import '../services/secret_store.dart';
import 'settings.dart';

/// Long-lived services created at startup, before the widget tree.
final class Services {
  Services({
    required this.store,
    required this.engine,
    required this.desktop,
    required this.secrets,
    required this.accounts,
    required this.initialSettings,
    this.graphicsEngine,
  });

  final MailStore store;
  final MailEngine engine;
  final DesktopIntegration desktop;
  final SecretStore secrets;
  final AccountsService accounts;
  final AppSettings initialSettings;

  /// Linux only.
  final GraphicsEngineSetting? graphicsEngine;
}

/// Overridden in `main` with the bootstrapped instance.
final servicesProvider = Provider<Services>((ref) => throw UnimplementedError('servicesProvider not overridden'));

final storeProvider = Provider<MailStore>((ref) => ref.watch(servicesProvider).store);
final engineProvider = Provider<MailEngine>((ref) => ref.watch(servicesProvider).engine);
final desktopProvider = Provider<DesktopIntegration>((ref) => ref.watch(servicesProvider).desktop);
final accountsServiceProvider = Provider<AccountsService>((ref) => ref.watch(servicesProvider).accounts);
