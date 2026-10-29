import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/navigation.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/desktop_bridge.dart';
import 'package:plume/src/ui/shell/account_switcher.dart';
import 'package:plume/src/ui/shell/home_shell.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_store/plume_store.dart';

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

const _accounts = [
  Account(id: 'a1', provider: 'fake', email: 'me@example.org', displayName: 'Me', color: 0xFF6750A4),
  Account(id: 'a2', provider: 'fake', email: 'new@example.org', displayName: 'New', color: 0xFF006A6A),
];

const _receipts = Mailbox(accountId: 'a1', id: 'Label_1', name: 'Receipts');

void main() {
  group('MailView.forAccount', () {
    const label = MailView(ViewKind.label, accountId: 'a1', mailboxId: 'Label_1');

    test('leaving a label for all accounts opens the unified inbox', () {
      final view = label.forAccount(null, inboxCategory: MailCategory.primary);
      expect(view, const MailView(ViewKind.inbox, category: MailCategory.primary));
      expect(view.toFilter(), const RoleFilter(MailboxRole.inbox, category: MailCategory.primary));
    });

    test('leaving a label for another account opens that account’s inbox', () {
      expect(label.forAccount('a2'), const MailView(ViewKind.inbox, accountId: 'a2'));
    });

    test('picking the label’s own account stays on the label', () {
      expect(label.forAccount('a1', inboxCategory: MailCategory.primary), label);
    });

    test('other lists keep their kind and category', () {
      const inbox = MailView(ViewKind.inbox, accountId: 'a1', category: MailCategory.social);
      expect(inbox.forAccount(null), const MailView(ViewKind.inbox, category: MailCategory.social));
      expect(const MailView(ViewKind.starred).forAccount('a2'), const MailView(ViewKind.starred, accountId: 'a2'));
    });
  });

  testWidgets('switching to all inboxes from a label keeps the shell working', (tester) async {
    final store = DriftMailStore.inMemory();
    addTearDown(() => tester.runAsync(store.close));
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);

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
        accountsProvider.overrideWith((ref) => Stream.value(_accounts)),
        syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
        hasCategoriesProvider.overrideWithValue(false),
        unreadCountProvider.overrideWith((ref, filter) => Stream.value(0)),
        mailboxesProvider.overrideWith((ref, id) => Stream.value([if (id == null || id == 'a1') _receipts])),
        usesFoldersProvider.overrideWith((ref, id) => false),
        threadsProvider.overrideWith((ref, filter) => Stream.value(const <ThreadSummary>[])),
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

    // A label opened from the unified rail scopes the view to its account.
    await tester.tap(find.textContaining('Receipts'));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), const MailView(ViewKind.label, accountId: 'a1', mailboxId: 'Label_1'));

    await tester.tap(find.byType(AccountSwitcher));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All inboxes').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(viewProvider).kind, ViewKind.inbox);
    expect(container.read(viewProvider).accountId, isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
