import 'dart:async';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:test/test.dart';

import '../support/fake_imap_server.dart';
import '../support/provider_harness.dart';
import 'generic_sync_test.dart' show seedConversation;

void main() {
  late Harness h;

  tearDown(() async => h.dispose());

  test('IDLE on INBOX signals new mail, debounced; cancelling logs out', () async {
    h = await Harness.start(
      seed: seedConversation,
      config: const ImapSyncConfig(pushDebounce: Duration(milliseconds: 50)),
    );
    var events = 0;
    final sub = h.provider.watchChanges().listen((_) => events++);
    await eventually(() => h.server.commands('IDLE').isNotEmpty);
    expect(h.server.commands('EXAMINE').single, 'EXAMINE INBOX');
    h.server
      ..deliver('INBOX', rawMessage(id: 'a@x', subject: 'One'))
      ..deliver('INBOX', rawMessage(id: 'b@x', subject: 'Two'));
    await eventually(() => events > 0);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(events, 1, reason: 'a burst rings once');
    await sub.cancel();
    await eventually(() => h.server.commands('LOGOUT').isNotEmpty);
    expect(h.server.log.where((l) => l == 'DONE' || l.startsWith('IDLE')), isNotEmpty);
  });

  test('without IDLE, NOOP polling', () async {
    h = await Harness.start(
      seed: seedConversation,
      capabilities: {...FakeImapServer.genericCapabilities}..remove('IDLE'),
      config: const ImapSyncConfig(pollInterval: Duration(milliseconds: 100), pushDebounce: Duration(milliseconds: 10)),
    );
    expect(h.provider.capabilities.push, isTrue);
    var events = 0;
    final sub = h.provider.watchChanges().listen((_) => events++);
    await eventually(() => h.server.commands('NOOP').isNotEmpty);
    // The fake only reports EXISTS to idling sessions, so polling sees no
    // change here; what matters is that it polls and can be cancelled.
    await sub.cancel();
    expect(events, 0);
  });

  test('a dropped connection ends the stream with a MailException', () async {
    h = await Harness.start(seed: seedConversation);
    final error = Completer<Object>();
    h.provider.watchChanges().listen((_) {}, onError: error.complete, cancelOnError: true);
    await eventually(() => h.server.commands('IDLE').isNotEmpty);
    await h.server.close();
    expect(await error.future.timeout(const Duration(seconds: 5)), isA<TransientException>());

    h.tokens.password = 'wrong';
    final denied = Completer<Object>();
    h.provider.watchChanges().listen((_) {}, onError: denied.complete, cancelOnError: true);
    expect(await denied.future.timeout(const Duration(seconds: 5)), isA<MailException>());
  });

  test('at most three connections; dispose closes them all', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final ids = (await h.messages()).keys.toList();
    final sub = h.provider.watchChanges().listen((_) {});
    await Future.wait([
      h.sync(),
      h.provider.fetchBodies(h.store, ids),
      h.provider.execute(h.store, h.action(MailAction.markRead, ids, scope: OperationScope.message)),
      h.provider.search(h.store, 'lunch'),
    ]);
    await eventually(() => h.server.commands('IDLE').isNotEmpty);
    expect(h.server.connectionsOpened, lessThanOrEqualTo(3));
    // dispose() also ends push connections still being listened to.
    await h.provider.dispose();
    await eventually(() => h.server.openConnections == 0);
    await sub.cancel();
  });

  test('end to end through the MailEngine: sync, prefetch, queued operation', () async {
    h = await Harness.start(seed: seedConversation);
    final engine = MailEngine(
      store: h.store,
      factories: [ImapProviderFactory(sender: h.sender)],
      tokenSourceFor: (_) => h.tokens,
    );
    await engine.start();
    await eventually(() => engine.currentStatuses[h.accountId]?.initialSyncDone ?? false);
    final lunch = await h.bySubject('Lunch?');
    // Prefetch of the newest inbox bodies.
    await eventually(() async => (await h.store.body(h.accountId, lunch.id)) != null);
    await engine.perform(ActionOperation(
      accountId: h.accountId,
      scope: OperationScope.thread,
      ids: [lunch.threadId],
      action: MailAction.archive,
    ));
    await eventually(() async => (await h.store.pendingOperations(accountId: h.accountId)).isEmpty);
    expect(h.server.mailboxes['Archives']!.entries, hasLength(2));
    expect(engine.capabilitiesOf(h.accountId)!.labels, isFalse);
    await engine.dispose();
  });
}
