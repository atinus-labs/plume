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
import 'package:plume/src/ui/threads/thread_list_pane.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_store/plume_store.dart';

class _FakeDesktop implements DesktopIntegration {
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

final _now = DateTime.now();

ThreadSummary _thread(int i) => ThreadSummary(
      accountId: 'a1',
      id: 'thread_$i',
      subject: 'Subject $i',
      snippet: 'Snippet $i',
      lastDate: _now.subtract(Duration(minutes: i)),
      messageCount: 1,
      unreadCount: 0,
      draftCount: 0,
      hasAttachments: false,
      isFlagged: false,
      participants: const [Address('sender@example.com', 'Sender')],
      mailboxIds: const {'INBOX'},
    );

class _Threads extends Notifier<List<ThreadSummary>> {
  @override
  List<ThreadSummary> build() => [for (var i = 0; i < 5; i++) _thread(i)];

  void set(List<ThreadSummary> threads) => state = threads;
}

final _threads = NotifierProvider<_Threads, List<ThreadSummary>>(_Threads.new);

Future<ProviderContainer> _pumpList(WidgetTester tester) async {
  final store = DriftMailStore.inMemory();
  final service = AccountsService(store: store, connectors: const []);
  final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
  addTearDown(() => tester.runAsync(store.close));
  final container = ProviderContainer(overrides: [
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
    mailboxesProvider.overrideWith((ref, id) => const Stream.empty()),
    unreadCountProvider.overrideWith((ref, filter) => const Stream.empty()),
    visibleThreadsProvider.overrideWith((ref) => AsyncValue.data(ref.watch(_threads))),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: SizedBox(width: 420, height: 800, child: ThreadListPane())),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a row that leaves stays for its exit, then goes', (tester) async {
    final container = await _pumpList(tester);
    expect(find.text('Subject 2'), findsOneWidget);

    container.read(_threads.notifier).set([for (final i in [0, 1, 3, 4]) _thread(i)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Subject 2'), findsOneWidget, reason: 'still animating out');

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Subject 2'), findsNothing);
    expect(find.text('Subject 3'), findsOneWidget);
  });

  testWidgets('a row that comes back before it is gone stays', (tester) async {
    final container = await _pumpList(tester);
    container.read(_threads.notifier).set([for (final i in [0, 1, 3, 4]) _thread(i)]);
    await tester.pump(const Duration(milliseconds: 60));
    // Undo.
    container.read(_threads.notifier).set([for (var i = 0; i < 5; i++) _thread(i)]);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Subject 2'), findsOneWidget);
  });

  testWidgets('switching views replaces the list without row exits', (tester) async {
    final container = await _pumpList(tester);
    container.read(viewProvider.notifier).show(const MailView(ViewKind.starred));
    container.read(_threads.notifier).set([_thread(9)]);
    await tester.pump();
    expect(find.text('Subject 0'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Subject 9'), findsOneWidget);
  });

  test('view switches travel the way the views sit on screen', () {
    const inbox = MailView(ViewKind.inbox, category: MailCategory.primary);
    expect(viewTravel(inbox, const MailView(ViewKind.starred)), (Axis.vertical, 1));
    expect(viewTravel(const MailView(ViewKind.trash), inbox), (Axis.vertical, -1));
    expect(viewTravel(inbox, inbox.withCategory(MailCategory.social)), (Axis.horizontal, 1));
    expect(viewTravel(inbox.withCategory(MailCategory.social), inbox), (Axis.horizontal, -1));
    expect(viewTravel(inbox, inbox.forAccount('a1')), isNull);
  });
}
