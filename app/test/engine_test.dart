// Integration tests for the sync engine over the real SQLite store.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

const _account = Account(id: 'a1', provider: 'fake', email: 'me@example.com', displayName: 'Me', color: 0);

Message _msg(String id, String thread, {Set<String> boxes = const {'INBOX'}, bool read = false}) => Message(
      accountId: 'a1',
      id: id,
      threadId: thread,
      subject: 'Subject $thread',
      from: const Address('sender@example.com', 'Sender'),
      date: DateTime.utc(2026, 10, 20, 9).add(Duration(minutes: id.hashCode % 100)),
      isRead: read,
      mailboxIds: boxes,
    );

/// A scriptable provider with Gmail-like label semantics.
final class FakeProvider implements MailProvider {
  FakeProvider(this.account);

  @override
  final Account account;
  final server = <String, Message>{};
  final executed = <MailOperation>[];
  final sent = <OutgoingMessage>[];
  final push = StreamController<void>.broadcast();
  Object? failExecuteWith;
  Object? failSyncWith;
  Completer<void>? holdExecute;

  /// Server drafts by id.
  final drafts = <String, OutgoingMessage>{};
  final _deleted = <String>{};
  Object? failDraftsWith;
  Completer<void>? holdDrafts;
  int draftSaves = 0;
  int syncs = 0;
  int disposals = 0;

  /// IMAP-like folder semantics: archive moves only the inbox messages.
  bool folders = false;

  @override
  ProviderCapabilities get capabilities =>
      const ProviderCapabilities(labels: true, categories: false, serverSearch: false, serverDrafts: false, push: true);

  @override
  Future<SyncResult> sync(SyncStore store) async {
    syncs++;
    if (failSyncWith != null) throw failSyncWith!;
    final known = await store.knownMessageIds(account.id, server.keys);
    await store.transaction(() async {
      await store.replaceMailboxes(account.id, [
        Mailbox(accountId: account.id, id: 'INBOX', name: 'Inbox', role: MailboxRole.inbox, kind: MailboxKind.system),
        Mailbox(accountId: account.id, id: 'TRASH', name: 'Trash', role: MailboxRole.trash, kind: MailboxKind.system),
        Mailbox(accountId: account.id, id: 'DRAFTS', name: 'Drafts', role: MailboxRole.drafts, kind: MailboxKind.system),
      ]);
      await store.deleteMessages(account.id, _deleted.toList());
      await store.upsertMessages(account.id, server.values.toList());
    });
    return SyncResult(newMessages: [for (final m in server.values) if (!known.contains(m.id)) m]);
  }

  @override
  LocalMutation localEffect(MailOperation op, List<Mailbox> mailboxes) => switch (op) {
        ActionOperation(action: MailAction.archive) when folders =>
          const LocalMutation(addMailboxes: {'TRASH'}, removeMailboxes: {'INBOX'}, onlyIn: {'INBOX'}),
        ActionOperation(action: MailAction.archive) => const LocalMutation(removeMailboxes: {'INBOX'}),
        ActionOperation(action: MailAction.moveToInbox) => const LocalMutation(addMailboxes: {'INBOX'}),
        ActionOperation(action: MailAction.markRead) => const LocalMutation(setRead: true),
        ActionOperation(action: MailAction.markUnread) => const LocalMutation(setRead: false),
        _ => const LocalMutation(),
      };

  @override
  List<String> currentMessageIds(List<String> messageIds) => messageIds;

  @override
  Future<void> execute(SyncStore store, MailOperation op) async {
    if (holdExecute != null) await holdExecute!.future;
    if (failExecuteWith != null) throw failExecuteWith!;
    executed.add(op);
    if (op is ActionOperation && op.action == MailAction.archive) {
      for (final m in server.values.where((m) => op.ids.contains(m.threadId)).toList()) {
        server[m.id] = m.copyWith(mailboxIds: {...m.mailboxIds}..remove('INBOX'));
      }
    }
  }

  @override
  Future<String> send(OutgoingMessage message) async {
    sent.add(message);
    return 'sent${sent.length}';
  }

  @override
  Stream<void> watchChanges() => push.stream;
  @override
  Future<void> fetchBodies(SyncStore store, List<String> messageIds) async {}
  @override
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment) async => Uint8List(0);
  @override
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, int pageSize = 50}) async =>
      const LoadMoreResult(loaded: 0, hasMore: false);
  @override
  Future<SearchPage> search(SyncStore store, String query, {String? pageToken}) async =>
      const SearchPage(threadIds: []);
  @override
  Future<String> saveDraft(OutgoingMessage message) async {
    if (holdDrafts != null) await holdDrafts!.future;
    if (failDraftsWith != null) throw failDraftsWith!;
    draftSaves++;
    final id = message.draftId ?? 'd$draftSaves';
    drafts[id] = message;
    server[id] = Message(
      accountId: account.id,
      id: id,
      threadId: message.threadId ?? 'thread-$id',
      subject: message.subject,
      date: DateTime.now(),
      isDraft: true,
      mailboxIds: const {'DRAFTS'},
    );
    return id;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    if (failDraftsWith != null) throw failDraftsWith!;
    drafts.remove(draftId);
    server.remove(draftId);
    _deleted.add(draftId);
  }
  @override
  Future<String?> draftIdOf(String messageId) async => messageId;
  @override
  Future<void> dispose() async => disposals++;
}

final class _Factory implements MailProviderFactory {
  _Factory(this.provider);
  final FakeProvider provider;
  int creates = 0;
  @override
  String get kind => 'fake';
  @override
  MailProvider create(Account account, TokenSource tokens) {
    creates++;
    return provider;
  }
}

final class _Tokens implements TokenSource {
  @override
  Future<String> accessToken() async => 't';
  @override
  void invalidate() {}
}

Future<void> _until(FutureOr<bool> Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late DriftMailStore store;
  late FakeProvider provider;
  late _Factory factory;
  late MailEngine engine;

  Future<List<ThreadSummary>> inbox() => store.watchThreads(const RoleFilter(MailboxRole.inbox)).first;

  /// Ids of the messages in Drafts.
  Future<List<String>> inDrafts() async => [
        for (final t in await store.watchThreads(const RoleFilter(MailboxRole.drafts)).first)
          for (final m in await store.messagesInThreads('a1', [t.id])) m.id,
      ];

  OutgoingMessage draft(String subject) => OutgoingMessage(
      accountId: 'a1',
      from: const Address('me@example.com'),
      to: const [Address('you@example.com')],
      subject: subject,
      textBody: 'Written on a train.');

  setUp(() async {
    store = DriftMailStore.inMemory();
    provider = FakeProvider(_account)
      ..server['m1'] = _msg('m1', 't1')
      ..server['m2'] = _msg('m2', 't2');
    factory = _Factory(provider);
    engine = MailEngine(store: store, factories: [factory], tokenSourceFor: (_) => _Tokens());
    await store.saveAccount(_account);
    await engine.start();
    await _until(() => engine.currentStatuses['a1']?.initialSyncDone ?? false);
  });

  tearDown(() async {
    await engine.dispose();
    await store.close();
  });

  test('restarting an account that was just saved leaves exactly one runtime', () async {
    // Saving emits an account list update while the restart is in flight.
    await store.saveAccount(_account.copyWith(providerConfig: {'server': 'new'}));
    await engine.restartAccount('a1');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(factory.creates - provider.disposals, 1);
  });

  test('undo of a partial folder move names exactly the messages that moved', () async {
    provider
      ..folders = true
      ..server['m1old'] = _msg('m1old', 't1', boxes: {'TRASH'}, read: true);
    provider.push.add(null);
    await _until(() async => (await store.messagesInThreads('a1', ['t1'])).length == 2);
    final undo = await engine.perform(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.archive));
    expect(
      undo,
      isA<ActionOperation>()
          .having((o) => o.action, 'action', MailAction.moveToInbox)
          .having((o) => o.scope, 'scope', OperationScope.message)
          .having((o) => o.ids, 'ids', ['m1']),
    );
  });

  test('undo of a label change keeps the whole conversation', () async {
    final undo = await engine.perform(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.archive));
    expect(
      undo,
      isA<ActionOperation>()
          .having((o) => o.action, 'action', MailAction.moveToInbox)
          .having((o) => o.scope, 'scope', OperationScope.thread)
          .having((o) => o.ids, 'ids', ['t1']),
    );
  });

  test('initial sync fills the inbox without notifying', () async {
    final events = <NewMailEvent>[];
    final sub = engine.newMail.listen(events.add);
    expect((await inbox()).map((t) => t.id), unorderedEquals(['t1', 't2']));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, isEmpty, reason: 'only incremental arrivals notify');
    await sub.cancel();
  });

  test('push signal syncs and reports new mail', () async {
    final events = <NewMailEvent>[];
    final sub = engine.newMail.listen(events.add);
    provider.server['m3'] = _msg('m3', 't3');
    provider.push.add(null);
    await _until(() => events.isNotEmpty);
    expect(events.single.messages.single.id, 'm3');
    expect((await inbox()).length, 3);
    await sub.cancel();
  });

  test('actions apply locally at once and reach the server', () async {
    provider.holdExecute = Completer();
    await engine.perform(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.archive));
    expect((await inbox()).map((t) => t.id), ['t2'], reason: 'optimistic');
    expect(provider.executed, isEmpty);
    provider.holdExecute!.complete();
    await _until(() => provider.executed.length == 1);
    await _until(() async => (await store.pendingOperations()).isEmpty);
  });

  test('a sync landing before the queue drains does not undo the action', () async {
    provider.holdExecute = Completer();
    await engine.perform(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.archive));
    // The server still has t1 in the inbox; a sync writes that state.
    await engine.syncAccount('a1');
    expect((await inbox()).map((t) => t.id), ['t2']);
    provider.holdExecute!.complete();
  });

  test('transient failures keep the operation queued', () async {
    provider.failExecuteWith = const TransientException('offline', null, Duration(milliseconds: 50));
    await engine.perform(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t2'], action: MailAction.markRead));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await store.pendingOperations(), hasLength(1));
    provider.failExecuteWith = null;
    await _until(() => provider.executed.isNotEmpty);
  });

  test('undo inverts actions', () {
    const op = ActionOperation(accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.archive);
    final inverse = MailEngine.inverseOf(op)! as ActionOperation;
    expect(inverse.action, MailAction.moveToInbox);
    expect(MailEngine.inverseOf(const ActionOperation(
        accountId: 'a1', scope: OperationScope.thread, ids: ['t1'], action: MailAction.deleteForever)), isNull);
  });

  test('undo send takes the message back before it leaves', () async {
    const message = OutgoingMessage(
        accountId: 'a1', from: Address('me@example.com'), to: [Address('you@example.com')], subject: 'Hi');
    final id = await engine.send(message, delay: const Duration(milliseconds: 300));
    final taken = await engine.cancelSend(id);
    expect(taken?.subject, 'Hi');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(provider.sent, isEmpty);
  });

  test('sending happens after the undo window', () async {
    final sent = <OutboxEvent>[];
    final sub = engine.outboxEvents.listen(sent.add);
    const message = OutgoingMessage(
        accountId: 'a1', from: Address('me@example.com'), to: [Address('you@example.com')], subject: 'Hello');
    await engine.send(message, delay: const Duration(milliseconds: 100));
    await _until(() => sent.isNotEmpty);
    expect(sent.single, isA<OutboxSent>());
    expect(provider.sent.single.subject, 'Hello');
    expect(await store.outbox(), isEmpty);
    await sub.cancel();
  });

  test('revoked credentials pause the account and mark it', () async {
    provider.failSyncWith = const AuthException('revoked');
    await engine.syncAccount('a1');
    await _until(() => engine.currentStatuses['a1']?.phase == SyncPhase.needsReauth);
    await _until(() async => (await store.accounts()).single.status == AccountStatus.needsReauth);
  });

  group('drafts', () {
    test('one written offline waits in Drafts and reaches the server once back online', () async {
      provider.failDraftsWith = const TransientException('offline');
      final saved = await engine.saveDraft(draft('Plans'));
      expect(await engine.uploadDraft(saved), isFalse);
      expect(provider.drafts, isEmpty);
      expect(await inDrafts(), [LocalDraft.messageIdOf(saved.id)]);

      provider.failDraftsWith = null;
      engine.wake();
      await _until(() => provider.drafts.isNotEmpty);
      expect(provider.drafts.values.single.subject, 'Plans');
      await engine.syncAccount('a1');
      expect(await inDrafts(), ['d1'], reason: 'the server copy takes the place of the one kept here');
    });

    test('one written offline is still there after a restart', () async {
      provider.failDraftsWith = const TransientException('offline');
      final saved = await engine.saveDraft(draft('Plans'));
      expect(await engine.uploadDraft(saved), isFalse);
      await engine.dispose();

      provider.failDraftsWith = null;
      engine = MailEngine(store: store, factories: [factory], tokenSourceFor: (_) => _Tokens());
      await engine.start();
      await _until(() => provider.drafts.isNotEmpty);
      expect(provider.drafts.values.single.subject, 'Plans');
    });

    test('saving again updates the server draft instead of making another', () async {
      final first = await engine.saveDraft(draft('Plans'));
      expect(await engine.uploadDraft(first), isTrue);
      final second = await engine.saveDraft(draft('Plans for Friday'), localId: first.id);
      expect(await engine.uploadDraft(second), isTrue);
      expect(provider.drafts.keys, ['d1']);
      expect(provider.drafts['d1']!.subject, 'Plans for Friday');
    });

    test('sending takes the draft along, uploaded or not', () async {
      final uploaded = await engine.saveDraft(draft('Uploaded'));
      expect(await engine.uploadDraft(uploaded), isTrue);
      await engine.send(draft('Uploaded'), delay: Duration.zero, localDraftId: uploaded.id);
      await _until(() => provider.sent.isNotEmpty);
      expect(provider.sent.single.draftId, 'd1');

      provider.failDraftsWith = const TransientException('offline');
      final local = await engine.saveDraft(draft('Local'));
      await engine.send(draft('Local'), delay: Duration.zero, localDraftId: local.id);
      await _until(() => provider.sent.length == 2);
      expect(provider.sent.last.draftId, isNull);
      expect(await store.localDrafts('a1'), isEmpty);
      expect(await inDrafts(), isNot(contains(LocalDraft.messageIdOf(local.id))));
    });

    test('one sent while its upload is on its way leaves no draft behind', () async {
      provider.holdDrafts = Completer();
      final saved = await engine.saveDraft(draft('Plans'));
      await engine.send(draft('Plans'), delay: const Duration(milliseconds: 200), localDraftId: saved.id);
      provider.holdDrafts!.complete();
      await _until(() => provider.sent.isNotEmpty);
      // The upload made one, which went once it found the draft sent.
      await _until(() => provider.draftSaves == 1 && provider.drafts.isEmpty);
      expect(provider.sent.single.draftId, isNull);
    });

    test('one discarded offline is deleted on the server once back online', () async {
      final saved = await engine.saveDraft(draft('Plans'));
      expect(await engine.uploadDraft(saved), isTrue);
      provider.failDraftsWith = const TransientException('offline');
      await engine.discardDraft('a1', localId: saved.id);
      expect(provider.drafts, isNotEmpty);

      provider.failDraftsWith = null;
      engine.wake();
      await _until(() => provider.drafts.isEmpty);
      await _until(() async => (await store.localDrafts('a1')).isEmpty);
      await _until(() async => (await inDrafts()).isEmpty);
    });

    test('deleting one only on this device from a list discards it', () async {
      provider.failDraftsWith = const TransientException('offline');
      final saved = await engine.saveDraft(draft('Plans'));
      final undo = await engine.perform(ActionOperation(
          accountId: 'a1', scope: OperationScope.thread, ids: [LocalDraft.messageIdOf(saved.id)], action: MailAction.trash));
      expect(undo, isNull);
      expect(await store.pendingOperations(), isEmpty);
      expect(await store.localDrafts('a1'), isEmpty);
      expect(await inDrafts(), isEmpty);
    });
  });
}
