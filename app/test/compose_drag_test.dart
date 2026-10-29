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

const _account = Account(id: 'a1', provider: 'fake', email: 'me@example.org', displayName: 'Me', color: 0xFF6750A4);

void main() {
  Widget buildApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
        home: const DesktopBridge(child: HomeShell()),
      ),
    );
  }

  ProviderContainer createContainer({MailListPosition mailListPosition = MailListPosition.left}) {
    final store = DriftMailStore.inMemory();
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(
      store: store,
      factories: service.factories,
      tokenSourceFor: service.tokenSourceFor,
    );

    return ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(Services(
          store: store,
          engine: engine,
          desktop: HeadlessDesktop(),
          secrets: _NoSecrets(),
          accounts: service,
          initialSettings: AppSettings(mailListPosition: mailListPosition),
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
  }

  testWidgets('compose panel is draggable when docked (not in full window mode)', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(container));
    await tester.pumpAndSettle();

    container.read(composeProvider.notifier).newMessage();
    await tester.pumpAndSettle();

    expect(find.byType(ComposePanel), findsOneWidget);
    final initialRect = tester.getRect(find.byType(ComposePanel));

    // Drag by the title bar
    await tester.drag(find.text('New message'), const Offset(-100, -80));
    await tester.pumpAndSettle();

    final draggedRect = tester.getRect(find.byType(ComposePanel));
    expect(draggedRect.left, lessThan(initialRect.left));
    expect(draggedRect.top, lessThan(initialRect.top));
  });

  testWidgets('compose panel is draggable by its title bar when minimized', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(container));
    await tester.pumpAndSettle();

    container.read(composeProvider.notifier).newMessage();
    await tester.pumpAndSettle();

    // Minimize the panel
    await tester.tap(find.byTooltip('Minimise'));
    await tester.pumpAndSettle();

    final minimizedRectBefore = tester.getRect(find.byType(ComposePanel));
    expect(minimizedRectBefore.height, closeTo(72.0, 1.0));

    // Drag the minimized title bar
    await tester.drag(find.text('New message'), const Offset(-60, -100));
    await tester.pumpAndSettle();

    final minimizedRectAfter = tester.getRect(find.byType(ComposePanel));
    expect(minimizedRectAfter.left, lessThan(minimizedRectBefore.left));
    expect(minimizedRectAfter.top, lessThan(minimizedRectBefore.top));

    // Restore the panel
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    final restoredRect = tester.getRect(find.byType(ComposePanel));
    expect(restoredRect.height, greaterThan(200.0));
    expect(restoredRect.left, closeTo(minimizedRectAfter.left, 1.0));
  });

  testWidgets('compose panel cannot be dragged in full window mode (maximized)', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(container));
    await tester.pumpAndSettle();

    container.read(composeProvider.notifier).newMessage();
    await tester.pumpAndSettle();

    // Maximize the panel
    await tester.tap(find.byTooltip('Full size'));
    await tester.pumpAndSettle();

    final maximizedRectBefore = tester.getRect(find.byType(ComposePanel));

    // Attempt to drag in full window mode
    await tester.drag(find.text('New message'), const Offset(-100, -80));
    await tester.pumpAndSettle();

    final maximizedRectAfter = tester.getRect(find.byType(ComposePanel));
    expect(maximizedRectAfter.left, equals(maximizedRectBefore.left));
    expect(maximizedRectAfter.top, equals(maximizedRectBefore.top));

    // Exit full window mode
    await tester.tap(find.byTooltip('Exit full size'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposePanel), findsOneWidget);
  });

  testWidgets('multiple compose windows drag independently', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp(container));
    await tester.pumpAndSettle();

    // Open two compose windows
    container.read(composeProvider.notifier).newMessage(to: [const Address('bob@example.org', 'Bob')]);
    await tester.pumpAndSettle();
    container.read(composeProvider.notifier).newMessage(to: [const Address('alice@example.org', 'Alice')]);
    await tester.pumpAndSettle();

    expect(find.byType(ComposePanel), findsNWidgets(2));

    final firstPanelRectBefore = tester.getRect(find.byType(ComposePanel).first);
    final secondPanelRectBefore = tester.getRect(find.byType(ComposePanel).last);

    // Drag the second panel by its title bar text
    await tester.drag(find.text('New message').last, const Offset(-80, -60));
    await tester.pumpAndSettle();

    final firstPanelRectAfter = tester.getRect(find.byType(ComposePanel).first);
    final secondPanelRectAfter = tester.getRect(find.byType(ComposePanel).last);

    // First panel didn't move
    expect(firstPanelRectAfter.left, closeTo(firstPanelRectBefore.left, 1.0));
    expect(firstPanelRectAfter.top, closeTo(firstPanelRectBefore.top, 1.0));

    // Second panel moved
    expect(secondPanelRectAfter.left, lessThan(secondPanelRectBefore.left));
    expect(secondPanelRectAfter.top, lessThan(secondPanelRectBefore.top));
  });
}
