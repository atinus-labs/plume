import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/desktop_bridge.dart';
import 'package:plume/src/ui/settings/settings_page.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_store/plume_store.dart';

// using HeadlessDesktop from services/desktop.dart

class _NoSecrets implements SecretStore {
  @override
  String get backend => 'test';
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

final class _Tokens implements TokenSource {
  @override
  Future<String> accessToken() async => 'token';
  @override
  void invalidate() {}
}

const _account = Account(id: 'a1', provider: 'fake', email: 'me@example.org', displayName: 'Me', color: 0xFF6750A4);

final class _FakeProvider implements MailProvider {
  _FakeProvider(this.account);
  @override
  final Account account;
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(labels: true, categories: false, serverSearch: false, serverDrafts: false, push: false);
  @override
  Future<SyncResult> sync(SyncStore store) async => const SyncResult(newMessages: []);
  @override
  Stream<void> watchChanges() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeFactory implements MailProviderFactory {
  @override
  String get kind => 'fake';
  @override
  MailProvider create(Account account, TokenSource tokenSource) => _FakeProvider(account);
}

void main() {
  group('AppSettings sync interval', () {
    test('defaults to 2 minutes foreground and 10 minutes background', () {
      const settings = AppSettings();
      expect(settings.foregroundSyncMinutes, 2);
      expect(settings.backgroundSyncMinutes, 10);
      expect(settings.foregroundSyncInterval, const Duration(minutes: 2));
      expect(settings.backgroundSyncInterval, const Duration(minutes: 10));
    });

    test('serializes and deserializes correctly', () {
      const original = AppSettings(
        foregroundSyncMinutes: 5,
        backgroundSyncMinutes: 30,
      );
      final json = original.toJson();
      expect(json['foregroundSyncMinutes'], 5);
      expect(json['backgroundSyncMinutes'], 30);

      final loaded = AppSettings.fromJson(json);
      expect(loaded.foregroundSyncMinutes, 5);
      expect(loaded.backgroundSyncMinutes, 30);
      expect(loaded.foregroundSyncInterval, const Duration(minutes: 5));
      expect(loaded.backgroundSyncInterval, const Duration(minutes: 30));
    });

    test('copyWith updates intervals', () {
      const original = AppSettings();
      final updated = original.copyWith(foregroundSyncMinutes: 15, backgroundSyncMinutes: 60);
      expect(updated.foregroundSyncMinutes, 15);
      expect(updated.backgroundSyncMinutes, 60);
    });
  });

  group('MailEngine sync intervals', () {
    test('dynamically updates active runtime intervals', () async {
      final store = DriftMailStore.inMemory();
      addTearDown(store.close);
      await store.saveAccount(_account);

      final engine = MailEngine(
        store: store,
        factories: [_FakeFactory()],
        tokenSourceFor: (_) => _Tokens(),
        foregroundInterval: const Duration(minutes: 2),
        backgroundInterval: const Duration(minutes: 10),
      );
      await engine.start();

      expect(engine.foregroundInterval, const Duration(minutes: 2));
      expect(engine.backgroundInterval, const Duration(minutes: 10));
      expect(engine.syncIntervalOf(_account.id), const Duration(minutes: 2));

      // Updating foreground interval propagates to active runtime while in foreground
      engine.foregroundInterval = const Duration(minutes: 5);
      expect(engine.foregroundInterval, const Duration(minutes: 5));
      expect(engine.syncIntervalOf(_account.id), const Duration(minutes: 5));

      // Switch to background mode
      engine.foreground = false;
      expect(engine.syncIntervalOf(_account.id), const Duration(minutes: 10));

      // Updating background interval propagates to active runtime while in background
      engine.backgroundInterval = const Duration(minutes: 30);
      expect(engine.backgroundInterval, const Duration(minutes: 30));
      expect(engine.syncIntervalOf(_account.id), const Duration(minutes: 30));

      // Switch back to foreground
      engine.foreground = true;
      expect(engine.syncIntervalOf(_account.id), const Duration(minutes: 5));
    });
  });

  group('SettingsPage UI', () {
    testWidgets('displays Sync section and updates foreground/background intervals', (tester) async {
      final store = DriftMailStore.inMemory();
      addTearDown(() => tester.runAsync(store.close));

      final service = AccountsService(store: store, connectors: const []);
      final engine = MailEngine(
        store: store,
        factories: service.factories,
        tokenSourceFor: service.tokenSourceFor,
      );

      final container = ProviderContainer(
        overrides: [
          servicesProvider.overrideWithValue(Services(
            store: store,
            engine: engine,
            desktop: HeadlessDesktop(),
            secrets: _NoSecrets(),
            accounts: service,
            initialSettings: const AppSettings(),
          )),
          accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
          syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
          home: const DesktopBridge(
            child: SettingsPage(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Check section and rows exist
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Foreground refresh interval'), findsOneWidget);
      expect(find.text('Background refresh interval'), findsOneWidget);

      // Verify dropdowns show default initial selections
      expect(find.text('Every 2 minutes'), findsWidgets);
      expect(find.text('Every 10 minutes'), findsWidgets);

      // Change foreground sync interval to 5 minutes
      await tester.tap(find.byKey(const ValueKey('settings_foreground_interval')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Every 5 minutes').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).foregroundSyncMinutes, 5);
      expect(engine.foregroundInterval, const Duration(minutes: 5));

      // Change background sync interval to 30 minutes
      await tester.tap(find.byKey(const ValueKey('settings_background_interval')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Every 30 minutes').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).backgroundSyncMinutes, 30);
      expect(engine.backgroundInterval, const Duration(minutes: 30));
    });
  });
}
