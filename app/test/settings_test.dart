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
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/compose/compose_panel.dart';
import 'package:plume/src/ui/desktop_bridge.dart';
import 'package:plume/src/ui/reader/reader_pane.dart';
import 'package:plume/src/ui/settings/settings_page.dart';
import 'package:plume/src/ui/shell/home_shell.dart';
import 'package:plume/src/ui/shell/title_bar.dart';
import 'package:plume/src/ui/threads/thread_list_pane.dart';
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

  group('AppSettings mailListPosition', () {
    test('defaults to left', () {
      const settings = AppSettings();
      expect(settings.mailListPosition, MailListPosition.left);
      expect(settings.mailListOnRight, isFalse);
    });

    test('serializes and deserializes correctly', () {
      const original = AppSettings(mailListPosition: MailListPosition.right);
      final json = original.toJson();
      expect(json['mailListPosition'], 'right');

      final loaded = AppSettings.fromJson(json);
      expect(loaded.mailListPosition, MailListPosition.right);
      expect(loaded.mailListOnRight, isTrue);
    });

    test('copyWith updates mailListPosition', () {
      const original = AppSettings();
      final updated1 = original.copyWith(mailListPosition: MailListPosition.right);
      expect(updated1.mailListPosition, MailListPosition.right);
      expect(updated1.mailListOnRight, isTrue);

      final updated2 = original.copyWith(mailListOnRight: true);
      expect(updated2.mailListPosition, MailListPosition.right);
      expect(updated2.mailListOnRight, isTrue);

      final updated3 = updated2.copyWith(mailListOnRight: false);
      expect(updated3.mailListPosition, MailListPosition.left);
      expect(updated3.mailListOnRight, isFalse);
    });
  });

  group('AppSettings avatar preferences', () {
    test('defaults to showSenderAvatars true, fetchDomainFavicons true, enableGravatar false', () {
      const settings = AppSettings();
      expect(settings.showSenderAvatars, isTrue);
      expect(settings.fetchDomainFavicons, isTrue);
      expect(settings.enableGravatar, isFalse);
    });

    test('serializes and deserializes correctly', () {
      const original = AppSettings(
        showSenderAvatars: false,
        fetchDomainFavicons: false,
        enableGravatar: true,
      );
      final json = original.toJson();
      expect(json['showSenderAvatars'], isFalse);
      expect(json['fetchDomainFavicons'], isFalse);
      expect(json['enableGravatar'], isTrue);

      final restored = AppSettings.fromJson(json);
      expect(restored.showSenderAvatars, isFalse);
      expect(restored.fetchDomainFavicons, isFalse);
      expect(restored.enableGravatar, isTrue);
    });

    test('copyWith updates avatar options', () {
      const original = AppSettings();
      final updated = original.copyWith(
        showSenderAvatars: false,
        fetchDomainFavicons: false,
        enableGravatar: true,
      );
      expect(updated.showSenderAvatars, isFalse);
      expect(updated.fetchDomainFavicons, isFalse);
      expect(updated.enableGravatar, isTrue);
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

    testWidgets('displays Mail list position option and toggles to right side', (tester) async {
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

      expect(find.text('Mail list position'), findsOneWidget);
      expect(find.text('Move the mail list to the right side'), findsOneWidget);

      // Initially Left is selected
      expect(container.read(settingsProvider).mailListPosition, MailListPosition.left);

      // Tap Right segment
      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).mailListPosition, MailListPosition.right);
      expect(container.read(settingsProvider).mailListOnRight, isTrue);

      // Tap Left segment
      await tester.tap(find.text('Left'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).mailListPosition, MailListPosition.left);
      expect(container.read(settingsProvider).mailListOnRight, isFalse);
    });
  });

  group('HomeShell layout', () {
    testWidgets('places mail list on right side when mailListPosition is right, keeping nav rail on left', (tester) async {
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
            initialSettings: const AppSettings(mailListPosition: MailListPosition.right),
          )),
          accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
          syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
          hasCategoriesProvider.overrideWithValue(false),
          unreadCountProvider.overrideWith((ref, filter) => Stream.value(0)),
          mailboxesProvider.overrideWith((ref, id) => Stream.value(const <Mailbox>[])),
          usesFoldersProvider.overrideWith((ref, id) => false),
          visibleThreadsProvider.overrideWithValue(const AsyncValue.data(<ThreadSummary>[])),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
          home: const DesktopBridge(child: HomeShell()),
        ),
      ));
      await tester.pumpAndSettle();

      final navRailHostRect = tester.getRect(find.byType(NavRailHost));
      final threadListRect = tester.getRect(find.byType(ThreadListPane));
      final readerPaneRect = tester.getRect(find.byType(ReaderPane));

      // Nav rail remains on the left
      expect(navRailHostRect.left, lessThan(readerPaneRect.left));
      expect(navRailHostRect.left, lessThan(threadListRect.left));

      // Reader pane is in the middle / left of the mail list
      expect(readerPaneRect.left, lessThan(threadListRect.left));
      // ThreadListPane is on the right side!
      expect(threadListRect.left, greaterThan(readerPaneRect.left));
    });

    testWidgets('places mail list on left side by default', (tester) async {
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
            initialSettings: const AppSettings(mailListPosition: MailListPosition.left),
          )),
          accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
          syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
          hasCategoriesProvider.overrideWithValue(false),
          unreadCountProvider.overrideWith((ref, filter) => Stream.value(0)),
          mailboxesProvider.overrideWith((ref, id) => Stream.value(const <Mailbox>[])),
          usesFoldersProvider.overrideWith((ref, id) => false),
          visibleThreadsProvider.overrideWithValue(const AsyncValue.data(<ThreadSummary>[])),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
          home: const DesktopBridge(child: HomeShell()),
        ),
      ));
      await tester.pumpAndSettle();

      final navRailHostRect = tester.getRect(find.byType(NavRailHost));
      final threadListRect = tester.getRect(find.byType(ThreadListPane));
      final readerPaneRect = tester.getRect(find.byType(ReaderPane));

      // Nav rail is on the left
      expect(navRailHostRect.left, lessThan(threadListRect.left));
      // Mail list is on the left (between nav rail and reader)
      expect(threadListRect.left, lessThan(readerPaneRect.left));
    });

    testWidgets('docks compose popup on left when mail list is on right', (tester) async {
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
            initialSettings: const AppSettings(mailListPosition: MailListPosition.right),
          )),
          accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
          syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
          hasCategoriesProvider.overrideWithValue(false),
          unreadCountProvider.overrideWith((ref, filter) => Stream.value(0)),
          mailboxesProvider.overrideWith((ref, id) => Stream.value(const <Mailbox>[])),
          usesFoldersProvider.overrideWith((ref, id) => false),
          visibleThreadsProvider.overrideWithValue(const AsyncValue.data(<ThreadSummary>[])),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
          home: const DesktopBridge(child: HomeShell()),
        ),
      ));
      await tester.pumpAndSettle();

      container.read(composeProvider.notifier).newMessage();
      await tester.pumpAndSettle();

      expect(find.byType(ComposePanel), findsOneWidget);
      final composeRect = tester.getRect(find.byType(ComposePanel));
      final navRailRect = tester.getRect(find.byType(NavRailHost));
      final threadListRect = tester.getRect(find.byType(ThreadListPane));

      // Compose popup starts from left (after nav rail) instead of right
      expect(composeRect.left, greaterThanOrEqualTo(navRailRect.right));
      expect(composeRect.left, closeTo(navRailRect.right + 16.0, 1.0));
      expect(composeRect.right, lessThan(threadListRect.left));
    });

    testWidgets('docks compose popup on right by default', (tester) async {
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
            initialSettings: const AppSettings(mailListPosition: MailListPosition.left),
          )),
          accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
          syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
          hasCategoriesProvider.overrideWithValue(false),
          unreadCountProvider.overrideWith((ref, filter) => Stream.value(0)),
          mailboxesProvider.overrideWith((ref, id) => Stream.value(const <Mailbox>[])),
          usesFoldersProvider.overrideWith((ref, id) => false),
          visibleThreadsProvider.overrideWithValue(const AsyncValue.data(<ThreadSummary>[])),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
          home: const DesktopBridge(child: HomeShell()),
        ),
      ));
      await tester.pumpAndSettle();

      container.read(composeProvider.notifier).newMessage();
      await tester.pumpAndSettle();

      expect(find.byType(ComposePanel), findsOneWidget);
      final composeRect = tester.getRect(find.byType(ComposePanel));

      // Compose popup is docked on the right side
      expect(composeRect.right, closeTo(1400.0 - 16.0, 1.0));
    });
  });
}
