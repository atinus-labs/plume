import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/threads/thread_list_pane.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

class _FakeDesktop implements DesktopIntegration {
  @override
  Stream<DesktopEvent> get events => const Stream.empty();
  @override
  bool get hasTray => false;
  @override
  Future<bool> isWindowVisible() async => true;
  @override
  Future<List<String>> takeOpenUris() async => const [];
  @override
  Future<void> setUnreadCount(int count) async {}
  @override
  Future<void> setPreventClose(bool prevent) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

const _account = Account(id: 'a1', provider: 'imap', email: 'me@example.org', displayName: 'Me', color: 0xFF6750A4);

void main() {
  testWidgets('refresh button is displayed and triggers sync', (tester) async {
    final store = DriftMailStore.inMemory();
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
    addTearDown(() => tester.runAsync(store.close));

    final syncStatusController = StreamController<Map<String, AccountSyncStatus>>.broadcast();
    addTearDown(syncStatusController.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        servicesProvider.overrideWithValue(Services(
          store: store,
          engine: engine,
          desktop: _FakeDesktop(),
          secrets: _NoSecrets(),
          accounts: service,
          initialSettings: const AppSettings(),
        )),
        accountsProvider.overrideWith((ref) => Stream.value(const [_account])),
        syncStatusProvider.overrideWith((ref) => syncStatusController.stream),
        hasCategoriesProvider.overrideWithValue(false),
        unreadCountProvider.overrideWith((ref, filter) => const Stream.empty()),
        visibleThreadsProvider.overrideWith((ref) => const AsyncValue.data([])),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ThreadListPane(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final buttonFinder = find.byTooltip('Check for mail (F5)');
    expect(buttonFinder, findsOneWidget);
    expect(find.byIcon(Symbols.sync_rounded), findsOneWidget);

    // Tapping button triggers sync
    await tester.tap(buttonFinder);
    await tester.pump();

    // When syncing is active, tooltip updates
    syncStatusController.add({
      'a1': const AccountSyncStatus(accountId: 'a1', phase: SyncPhase.syncing, initialSyncDone: true),
    });
    await tester.pump();

    expect(find.byTooltip('Checking for mail…'), findsOneWidget);

    // When syncing finishes, tooltip restores
    syncStatusController.add({
      'a1': const AccountSyncStatus(accountId: 'a1', phase: SyncPhase.idle, initialSyncDone: true),
    });
    await tester.pump();

    expect(find.byTooltip('Check for mail (F5)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
