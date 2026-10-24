import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

OutgoingMessage outgoing({String account = 'a1', String subject = 'Hi'}) => OutgoingMessage(
  accountId: account,
  from: const Address('a1@example.com', 'Me'),
  to: const [Address('ana@example.org', 'Ana')],
  cc: const [Address('ben@example.org')],
  bcc: const [Address('hidden@example.org', 'H')],
  subject: subject,
  textBody: 'Hello',
  htmlBody: '<p>Hello</p>',
  attachments: [
    OutgoingAttachment(filename: 'a.bin', mimeType: 'application/octet-stream', bytes: Uint8List.fromList([0, 1, 255])),
    OutgoingAttachment(filename: 'i.png', mimeType: 'image/png', bytes: Uint8List(0), contentId: 'img1'),
  ],
  threadId: 't1',
  inReplyTo: '<x@y>',
  references: const ['<w@y>', '<x@y>'],
  draftId: 'r-1',
);

void main() {
  late DriftMailStore store;

  setUp(() async => store = await newStore());
  tearDown(() => store.close());

  group('contacts', () {
    test('counted once per new message, from/to/cc only, drafts ignored', () async {
      const ana = Address('Ana@Example.org', 'Ana Alvarez');
      const ben = Address('ben@example.org', 'Ben Brown');
      await store.upsertMessages('a1', [
        msg('m1', from: ana, to: const [ben], cc: const [Address('cy@example.org')], minute: 1),
        msg('m2', from: ben, to: const [ana], minute: 2),
        msg('m3', from: ana, to: const [Address('bcc-only@example.org')], minute: 3),
        msg('d1', from: ana, to: const [Address('drafty@example.org')], draft: true, minute: 4),
      ]);
      // Re-syncing the same messages must not inflate the counts.
      await store.upsertMessages('a1', [
        msg('m1', from: ana, to: const [ben], cc: const [Address('cy@example.org')], minute: 1, read: false),
        msg('m2', from: ben, to: const [ana], minute: 2),
      ]);
      expect(await store.suggestAddresses(''), [
        const Address('ana@example.org', 'Ana Alvarez'),
        const Address('ben@example.org', 'Ben Brown'),
        const Address('bcc-only@example.org'),
        const Address('cy@example.org'),
      ]);
      expect(await store.suggestAddresses('drafty'), isEmpty);
    });

    test('prefix on email or on any name word, most used first', () async {
      await store.upsertMessages('a1', [
        msg('m1', from: const Address('bob@x.org', 'Robert Smith'), minute: 1),
        msg('m2', from: const Address('rob@x.org', 'Rob Jones'), minute: 2),
        msg('m3', from: const Address('rob@x.org', 'Rob Jones'), minute: 3),
        msg('m4', from: const Address('jane@x.org', 'Jane Robinson'), minute: 4),
        msg('m5', from: const Address('100%_sure@x.org'), minute: 5),
      ]);
      expect([for (final a in await store.suggestAddresses('rob')) a.email], ['rob@x.org', 'jane@x.org', 'bob@x.org']);
      expect([for (final a in await store.suggestAddresses('SMI')) a.email], ['bob@x.org']);
      expect([for (final a in await store.suggestAddresses('rob', limit: 1)) a.email], ['rob@x.org']);
      expect([for (final a in await store.suggestAddresses('100%_')) a.email], ['100%_sure@x.org']);
      expect(await store.suggestAddresses('1000'), isEmpty);
      expect(await store.suggestAddresses('%'), isEmpty);
    });

    test('the most recent name wins', () async {
      await store.upsertMessages('a1', [
        msg('m1', from: const Address('x@x.org', 'Old Name'), minute: 1),
        msg('m2', from: const Address('x@x.org'), minute: 2),
      ]);
      expect((await store.suggestAddresses('x@')).single.name, 'Old Name');
      await store.upsertMessages('a1', [msg('m3', from: const Address('x@x.org', 'New Name'), minute: 3)]);
      expect((await store.suggestAddresses('x@')).single.name, 'New Name');
      await store.upsertMessages('a1', [msg('m0', from: const Address('x@x.org', 'Ancient'), minute: 0)]);
      expect((await store.suggestAddresses('x@')).single.name, 'New Name');
    });
  });

  group('operation queue', () {
    test('enqueue, list in order, defer, complete', () async {
      const op1 = ActionOperation(
        accountId: 'a1',
        scope: OperationScope.thread,
        ids: ['t1'],
        action: MailAction.archive,
      );
      const op2 = LabelOperation(
        accountId: 'a2',
        scope: OperationScope.message,
        ids: ['m1', 'm2'],
        add: {'L1'},
        remove: {'INBOX'},
      );
      const op3 = ActionOperation(accountId: 'a1', scope: OperationScope.message, ids: ['m9'], action: MailAction.flag);
      final id1 = await store.enqueueOperation(op1);
      final id2 = await store.enqueueOperation(op2);
      final id3 = await store.enqueueOperation(op3);
      expect(id1 < id2 && id2 < id3, isTrue);

      final all = await store.pendingOperations();
      expect([for (final p in all) p.id], [id1, id2, id3]);
      expect(all[1].operation, isA<LabelOperation>());
      final label = all[1].operation as LabelOperation;
      expect(label.add, {'L1'});
      expect(label.remove, {'INBOX'});
      expect(label.ids, ['m1', 'm2']);
      expect(all.first.attempts, 0);
      expect(all.first.notBefore, isNull);
      expect(all.first.lastError, isNull);

      expect([for (final p in await store.pendingOperations(accountId: 'a1')) p.id], [id1, id3]);

      final later = DateTime.now().add(const Duration(minutes: 5));
      await store.deferOperation(id1, error: 'offline', notBefore: later);
      await store.deferOperation(id1, error: 'still offline', notBefore: later);
      final deferred = (await store.pendingOperations(accountId: 'a1')).first;
      expect(deferred.id, id1);
      expect(deferred.attempts, 2);
      expect(deferred.lastError, 'still offline');
      expect(deferred.notBefore!.millisecondsSinceEpoch, later.millisecondsSinceEpoch);
      expect((deferred.operation as ActionOperation).action, MailAction.archive);

      await store.completeOperation(id1);
      expect([for (final p in await store.pendingOperations()) p.id], [id2, id3]);
    });

    test('unreadable entries are skipped, not fatal', () async {
      await store.db.customStatement(
        "INSERT INTO pending_ops (account_id, payload) VALUES ('a1', '{\"type\":\"future\"}')",
      );
      final id = await store.enqueueOperation(
        const ActionOperation(accountId: 'a1', scope: OperationScope.thread, ids: ['t'], action: MailAction.trash),
      );
      expect([for (final p in await store.pendingOperations()) p.id], [id]);
    });
  });

  group('outbox', () {
    test('codec round-trips every field', () {
      final m = outgoing();
      final back = OutgoingMessageCodec.decode(OutgoingMessageCodec.encode(m));
      expect(back.accountId, m.accountId);
      expect(back.from, m.from);
      expect(back.to, m.to);
      expect(back.cc, m.cc);
      expect(back.bcc, m.bcc);
      expect(back.subject, m.subject);
      expect(back.textBody, m.textBody);
      expect(back.htmlBody, m.htmlBody);
      expect(back.threadId, m.threadId);
      expect(back.inReplyTo, m.inReplyTo);
      expect(back.references, m.references);
      expect(back.draftId, m.draftId);
      expect(back.attachments, hasLength(2));
      expect(back.attachments[0].bytes, [0, 1, 255]);
      expect(back.attachments[0].filename, 'a.bin');
      expect(back.attachments[0].contentId, isNull);
      expect(back.attachments[1].contentId, 'img1');
      expect(back.attachments[1].bytes, isEmpty);

      const minimal = OutgoingMessage(accountId: 'a', from: Address('a@b.c'));
      final m2 = OutgoingMessageCodec.decode(OutgoingMessageCodec.encode(minimal));
      expect(m2.to, isEmpty);
      expect(m2.htmlBody, isNull);
      expect(m2.attachments, isEmpty);
    });

    test('state transitions and attempts', () async {
      final sendAt = DateTime.now().add(const Duration(seconds: 5));
      final rec = Recorder(store.watchOutbox());
      await rec.waitFor(1);
      expect(rec.last, isEmpty);

      final id = await store.enqueueOutgoing(outgoing(), sendAt);
      await rec.waitFor(2);
      var e = rec.last.single;
      expect(e.id, id);
      expect(e.state, OutboxState.scheduled);
      expect(e.attempts, 0);
      expect(e.sendAt.millisecondsSinceEpoch, sendAt.millisecondsSinceEpoch);
      expect(e.message.attachments.first.bytes, [0, 1, 255]);

      await store.updateOutbox(id, state: OutboxState.sending);
      e = (await store.outbox()).single;
      expect(e.state, OutboxState.sending);
      expect(e.attempts, 0);

      final retryAt = DateTime.now().add(const Duration(minutes: 1));
      await store.updateOutbox(id, state: OutboxState.retrying, error: 'timeout', sendAt: retryAt);
      e = (await store.outbox()).single;
      expect(e.state, OutboxState.retrying);
      expect(e.attempts, 1);
      expect(e.lastError, 'timeout');
      expect(e.sendAt.millisecondsSinceEpoch, retryAt.millisecondsSinceEpoch);

      await store.updateOutbox(id, state: OutboxState.sending);
      await store.updateOutbox(id, state: OutboxState.failed, error: 'rejected');
      e = (await store.outbox()).single;
      expect(e.state, OutboxState.failed);
      expect(e.attempts, 2);
      expect(e.lastError, 'rejected');
      expect(e.sendAt.millisecondsSinceEpoch, retryAt.millisecondsSinceEpoch);

      // A failed entry cannot be taken back; the user retries it instead.
      expect(await store.takeOutgoing(id), isNull);
      await store.updateOutbox(id, state: OutboxState.scheduled, sendAt: sendAt);
      expect((await store.outbox()).single.attempts, 2);

      await store.deleteOutgoing(id);
      expect(await store.outbox(), isEmpty);
      await Recorder.settle();
      expect(rec.last, isEmpty);
      await rec.cancel();
    });

    test('takeOutgoing only takes scheduled entries, atomically', () async {
      final now = DateTime.now();
      final a = await store.enqueueOutgoing(outgoing(subject: 'A'), now);
      final b = await store.enqueueOutgoing(outgoing(subject: 'B'), now);

      final taken = await store.takeOutgoing(a);
      expect(taken!.message.subject, 'A');
      expect(taken.state, OutboxState.scheduled);
      expect(await store.takeOutgoing(a), isNull);

      // Once the sender claimed it, undo is no longer possible.
      await store.updateOutbox(b, state: OutboxState.sending);
      expect(await store.takeOutgoing(b), isNull);
      expect((await store.outbox()).single.id, b);

      // Concurrent takes: exactly one wins.
      final c = await store.enqueueOutgoing(outgoing(subject: 'C'), now);
      final results = await Future.wait([for (var i = 0; i < 5; i++) store.takeOutgoing(c)]);
      expect(results.nonNulls, hasLength(1));
      expect(await store.takeOutgoing(999), isNull);
    });

    test('deleteOutgoing removes in any state', () async {
      final id = await store.enqueueOutgoing(outgoing(), DateTime.now());
      await store.updateOutbox(id, state: OutboxState.sending);
      await store.deleteOutgoing(id);
      expect(await store.outbox(), isEmpty);
    });
  });

  group('settings and sync state', () {
    test('settings read, write, delete and watch', () async {
      final rec = Recorder(store.watchSetting('theme'));
      await rec.waitFor(1);
      expect(rec.last, isNull);
      expect(await store.readSetting('theme'), isNull);

      await store.writeSetting('theme', 'dark');
      await rec.waitFor(2);
      expect(rec.last, 'dark');
      expect(await store.readSetting('theme'), 'dark');

      // Same value and other keys do not emit.
      await store.writeSetting('theme', 'dark');
      await store.writeSetting('density', 'compact');
      await Recorder.settle();
      expect(rec.events, hasLength(2));

      await store.writeSetting('theme', 'light');
      await rec.waitFor(3);
      expect(rec.last, 'light');

      await store.writeSetting('theme', null);
      await rec.waitFor(4);
      expect(rec.last, isNull);
      expect(await store.readSetting('density'), 'compact');
      await rec.cancel();
    });

    test('sync state is per account', () async {
      await store.writeState('a1', 'historyId', '1');
      await store.writeState('a2', 'historyId', '2');
      await store.writeState('a1', 'historyId', '3');
      expect(await store.readState('a1', 'historyId'), '3');
      expect(await store.readState('a2', 'historyId'), '2');
      await store.writeState('a1', 'historyId', null);
      expect(await store.readState('a1', 'historyId'), isNull);
      expect(await store.readState('a1', 'other'), isNull);
    });
  });

  group('accounts and mailboxes', () {
    test('accounts upsert in place without cascading', () async {
      await store.upsertMessages('a1', [msg('m1')]);
      final rec = Recorder(store.watchAccounts());
      await rec.waitFor(1);
      expect(rec.last.map((a) => a.id), ['a1', 'a2']);
      await store.saveAccount(account('a1', sortOrder: 9).copyWith(status: AccountStatus.needsReauth, signature: '--'));
      await rec.waitFor(2);
      expect(rec.last.map((a) => a.id), ['a2', 'a1']);
      expect(rec.last.last.status, AccountStatus.needsReauth);
      expect(rec.last.last.signature, '--');
      await store.saveAccount(rec.last.last.copyWith(providerConfig: {'imap': {'host': 'imap.example.com'}}));
      await rec.waitFor(3);
      expect(rec.last.last.providerConfig, {'imap': {'host': 'imap.example.com'}});
      expect(await store.knownMessageIds('a1', ['m1']), {'m1'});
      expect((await store.mailboxes('a1')), isNotEmpty);
      await rec.cancel();
    });

    test('replaceMailboxes and updateMailboxCounts', () async {
      final rec = Recorder(store.watchMailboxes(accountId: 'a1'));
      await rec.waitFor(1);
      expect(rec.last.map((m) => m.id), contains('INBOX'));
      final inbox = rec.last.firstWhere((m) => m.id == 'INBOX');
      expect(inbox.role, MailboxRole.inbox);
      expect(inbox.kind, MailboxKind.system);
      final social = rec.last.firstWhere((m) => m.id == 'CATEGORY_SOCIAL');
      expect(social.category, MailCategory.social);
      expect(social.hidden, isTrue);

      await store.updateMailboxCounts('a1', {'INBOX': (unread: 3, total: 10), 'UNKNOWN': (unread: 1, total: 1)});
      await rec.waitFor(2);
      expect(rec.last.firstWhere((m) => m.id == 'INBOX').unreadThreads, 3);
      expect(rec.last.firstWhere((m) => m.id == 'INBOX').totalThreads, 10);

      await store.replaceMailboxes('a1', [
        const Mailbox(accountId: 'a1', id: 'INBOX', name: 'Inbox', role: MailboxRole.inbox, sortOrder: 1),
        const Mailbox(accountId: 'a1', id: 'L2', name: 'beta', parentId: 'L1', color: 0xFF00FF00, sortOrder: 2),
        const Mailbox(accountId: 'a1', id: 'L1', name: 'Alpha', sortOrder: 2),
      ]);
      await rec.waitFor(3);
      expect(rec.last.map((m) => m.id), ['INBOX', 'L1', 'L2']);
      expect(rec.last[2].parentId, 'L1');
      expect(rec.last[2].color, 0xFF00FF00);
      expect((await store.mailboxes('a2')).length, gmailMailboxes('a2').length);

      final all = await store.watchMailboxes().first;
      expect(all.first.accountId, 'a1');
      expect(all.last.accountId, 'a2');
      await rec.cancel();
    });
  });
}
