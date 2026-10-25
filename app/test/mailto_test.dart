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
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/desktop_bridge.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

/// A desktop that delivers links: [launchUris] at startup, then [send].
class _LinkDesktop implements DesktopIntegration {
  _LinkDesktop(this.launchUris);

  final List<String> launchUris;
  final _events = StreamController<DesktopEvent>.broadcast();

  void send(String uri) => _events.add(OpenUriEvent(uri));

  @override
  Stream<DesktopEvent> get events => _events.stream;
  @override
  Future<List<String>> takeOpenUris() async => launchUris;
  @override
  bool get hasTray => false;
  @override
  Future<bool> isWindowVisible() async => true;
  @override
  Future<void> setUnreadCount(int count) async {}
  @override
  Future<void> setPreventClose(bool prevent) async {}
  @override
  Future<void> dispose() => _events.close();

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
  Future<ProviderContainer> pumpBridge(WidgetTester tester, _LinkDesktop desktop, Stream<List<Account>> accounts) async {
    // The engine is never started and the store never queried: the bridge
    // only needs their event streams here.
    final store = DriftMailStore.inMemory();
    final service = AccountsService(store: store, connectors: const []);
    final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        servicesProvider.overrideWithValue(Services(
          store: store,
          engine: engine,
          desktop: desktop,
          secrets: _NoSecrets(),
          accounts: service,
          initialSettings: const AppSettings(),
        )),
        accountsProvider.overrideWith((ref) => accounts),
        hasCategoriesProvider.overrideWithValue(false),
        unreadCountProvider.overrideWith((ref, filter) => const Stream.empty()),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const DesktopBridge(child: Scaffold()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(DesktopBridge)));
  }

  testWidgets('the launch link and later links open prefilled compose windows', (tester) async {
    final desktop = _LinkDesktop(['mailto:jane@example.org?subject=Hello%20there&body=Hi+Jane']);
    final container = await pumpBridge(tester, desktop, Stream.value(const [_account]));

    var compose = container.read(composeProvider);
    expect(compose, hasLength(1));
    expect(compose.single.to.single.email, 'jane@example.org');
    expect(compose.single.subject, 'Hello there');
    expect(compose.single.body, 'Hi+Jane');
    expect(compose.single.accountId, 'a1');

    desktop.send('mailto:?to=bob@example.org&cc=amy@example.org');
    desktop.send('https://example.org');
    await tester.pump();
    compose = container.read(composeProvider);
    expect(compose, hasLength(2));
    expect(compose.last.to.single.email, 'bob@example.org');
    expect(compose.last.cc.single.email, 'amy@example.org');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('links wait for the first account', (tester) async {
    final accounts = StreamController<List<Account>>();
    addTearDown(accounts.close);
    final desktop = _LinkDesktop(['mailto:jane@example.org']);
    final container = await pumpBridge(tester, desktop, accounts.stream);

    accounts.add(const []);
    await tester.pump();
    expect(container.read(composeProvider), isEmpty);
    expect(find.text('Add an account to write this message'), findsNothing,
        reason: 'the launch link arrived while accounts were loading');

    desktop.send('mailto:bob@example.org');
    await tester.pump();
    expect(find.text('Add an account to write this message'), findsOneWidget);

    accounts.add(const [_account]);
    await tester.pump();
    expect([for (final r in container.read(composeProvider)) r.to.single.email], ['jane@example.org', 'bob@example.org']);
    await tester.pumpWidget(const SizedBox());
    // Let the snack bar's timers finish.
    await tester.pump(const Duration(seconds: 10));
  });
}
