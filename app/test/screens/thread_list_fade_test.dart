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
import 'package:plume/src/ui/threads/thread_list_pane.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
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

List<ThreadSummary> _generateThreads(int count) {
  final now = DateTime.now();
  return List.generate(count, (i) => ThreadSummary(
    accountId: 'a1',
    id: 'thread_$i',
    subject: 'Subject $i',
    snippet: 'This is the snippet for email number $i',
    lastDate: now.subtract(Duration(hours: i * 4)),
    messageCount: 1,
    unreadCount: i % 2 == 0 ? 1 : 0,
    draftCount: 0,
    hasAttachments: false,
    isFlagged: false,
    participants: const [Address('sender@example.com', 'Sender')],
    mailboxIds: const {'INBOX'},
  ));
}

void main() {
  testWidgets('thread list applies fade and rounded corner clipping on scroll', (tester) async {
    final store = DriftMailStore.inMemory();
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
    addTearDown(() => tester.runAsync(store.close));

    final threads = _generateThreads(20);

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
        syncStatusProvider.overrideWith((ref) => const Stream.empty()),
        hasCategoriesProvider.overrideWithValue(false),
        unreadCountProvider.overrideWith((ref, filter) => const Stream.empty()),
        visibleThreadsProvider.overrideWith((ref) => AsyncValue.data(threads)),
      ],
      child: MaterialApp(
        theme: PlumeTheme.build(brightness: Brightness.dark),
        home: const Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ThreadListPane(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final shaderMaskFinder = find.byType(ShaderMask);
    expect(shaderMaskFinder, findsOneWidget);

    final clipPathFinder = find.byType(ClipPath);
    expect(clipPathFinder, findsOneWidget);

    final scrollable = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    expect(scrollable, findsOneWidget);

    // Scroll down by 150px
    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pumpAndSettle();

    // Verify ClipPath and ShaderMask remain rendered and updated
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.byType(ClipPath), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('category tabs apply horizontal fade and rounded corner clipping on scroll', (tester) async {
    final store = DriftMailStore.inMemory();
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
    addTearDown(() => tester.runAsync(store.close));

    final threads = _generateThreads(20);

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
        syncStatusProvider.overrideWith((ref) => const Stream.empty()),
        hasCategoriesProvider.overrideWithValue(true),
        unreadCountProvider.overrideWith((ref, filter) => const Stream.empty()),
        visibleThreadsProvider.overrideWith((ref) => AsyncValue.data(threads)),
      ],
      child: MaterialApp(
        theme: PlumeTheme.build(brightness: Brightness.dark),
        home: const Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: ThreadListPane(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Two ShaderMasks now: one for category tabs, one for thread list
    expect(find.byType(ShaderMask), findsNWidgets(2));
    expect(find.byType(ClipPath), findsNWidgets(2));

    final horizontalScrollable = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right && w.restorationId == null);
    expect(horizontalScrollable, findsOneWidget);

    // Scroll category tabs to the right
    await tester.drag(horizontalScrollable, const Offset(-100, 0));
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNWidgets(2));
    expect(find.byType(ClipPath), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
