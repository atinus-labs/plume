import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

const ana = Address('ana@example.org', 'Ana Alvarez');
const ben = Address('ben@example.org', 'Ben Brown');
const cy = Address('cy@example.org', 'Cy');
const me = Address('a1@example.com', 'Me');

void main() {
  late DriftMailStore store;

  setUp(() async => store = await newStore());
  tearDown(() => store.close());

  group('thread recomputation on upsert', () {
    test('aggregates counts, flags, dates and mailboxes', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', subject: 'Plans', from: ana, minute: 1, snippet: 'first', read: true),
        msg(
          'm2',
          thread: 't1',
          subject: 'Re: Plans',
          from: ben,
          minute: 5,
          snippet: 'second',
          read: false,
          flagged: true,
          attachments: [pdf],
          boxes: {'INBOX', 'IMPORTANT'},
        ),
        msg('m3', thread: 't1', subject: 'Re: Plans', from: me, minute: 3, snippet: 'reply', boxes: {'SENT'}),
      ]);
      final t = (await summary(store, 'a1', 't1'))!;
      expect(t.subject, 'Plans');
      expect(t.snippet, 'second');
      expect(t.lastDate.millisecondsSinceEpoch, at(5).millisecondsSinceEpoch);
      expect(t.messageCount, 3);
      expect(t.unreadCount, 1);
      expect(t.isFlagged, isTrue);
      expect(t.hasAttachments, isTrue);
      expect(t.draftCount, 0);
      expect(t.mailboxIds, {'INBOX', 'IMPORTANT', 'SENT'});
      expect(t.participants.map((a) => a.email), ['ana@example.org', 'a1@example.com', 'ben@example.org']);
    });

    test('subject comes from the oldest message with a non-empty subject', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', subject: '', minute: 1),
        msg('m2', thread: 't1', subject: 'Second', minute: 2),
        msg('m3', thread: 't1', subject: 'Third', minute: 3),
      ]);
      expect((await summary(store, 'a1', 't1'))!.subject, 'Second');
      await store.upsertMessages('a1', [msg('m0', thread: 't1', subject: 'Zeroth', minute: 0)]);
      expect((await summary(store, 'a1', 't1'))!.subject, 'Zeroth');
    });

    test('snippet comes from the newest non-draft message, else the newest', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, snippet: 'sent mail'),
        msg('d1', thread: 't1', minute: 9, snippet: 'my draft', draft: true, boxes: {'DRAFT'}),
      ]);
      var t = (await summary(store, 'a1', 't1'))!;
      expect(t.snippet, 'sent mail');
      expect(t.draftCount, 1);
      expect(t.lastDate.millisecondsSinceEpoch, at(9).millisecondsSinceEpoch);

      await store.deleteMessages('a1', ['m1']);
      t = (await summary(store, 'a1', 't1'))!;
      expect(t.snippet, 'my draft');
      expect(t.messageCount, 1);
    });

    test('unread count ignores drafts', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', read: false),
        msg('d1', thread: 't1', read: false, draft: true, boxes: {'DRAFT'}),
      ]);
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 1);
    });

    test('inline images do not count as attachments', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', attachments: [inlineImage]),
      ]);
      expect((await summary(store, 'a1', 't1'))!.hasAttachments, isFalse);
    });

    test('participants: distinct, first appearance order, latest kept last when trimmed', () async {
      final senders = [for (var i = 0; i < 8; i++) Address('p$i@x.org', 'P$i')];
      await store.upsertMessages('a1', [
        for (var i = 0; i < 8; i++) msg('m$i', thread: 't1', from: senders[i], minute: i),
        // p1 writes again, then p7 again: p7 is the latest sender.
        msg('m8', thread: 't1', from: const Address('P1@X.org', 'Pat One'), minute: 8),
        msg('m9', thread: 't1', from: senders[7], minute: 9),
      ]);
      final t = (await summary(store, 'a1', 't1'))!;
      expect(t.participants.map((a) => a.email.toLowerCase()), [
        'p0@x.org',
        'p1@x.org',
        'p2@x.org',
        'p3@x.org',
        'p4@x.org',
        'p7@x.org',
      ]);
      // The most recent display name is used.
      expect(t.participants[1].name, 'Pat One');
    });

    test('participants up to six are all kept in order', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', from: ana, minute: 1),
        msg('m2', thread: 't1', from: ben, minute: 2),
        msg('m3', thread: 't1', from: ana, minute: 3),
        msg('m4', thread: 't1', from: cy, minute: 4),
      ]);
      expect((await summary(store, 'a1', 't1'))!.participants, [ana, ben, cy]);
    });

    test('re-upsert replaces metadata and mailboxes', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', read: false, boxes: {'INBOX', 'Label_work'}),
      ]);
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', read: true, boxes: {'Label_work'}),
      ]);
      final t = (await summary(store, 'a1', 't1'))!;
      expect(t.unreadCount, 0);
      expect(t.mailboxIds, {'Label_work'});
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), isEmpty);
      expect(await threadIds(store, const MailboxFilter('a1', 'Label_work')), ['t1']);
    });

    test('a message moving to another thread recomputes both', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1),
        msg('m2', thread: 't1', minute: 2, read: false),
      ]);
      await store.upsertMessages('a1', [msg('m2', thread: 't2', minute: 2, read: false)]);
      expect((await summary(store, 'a1', 't1'))!.messageCount, 1);
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 0);
      expect((await summary(store, 'a1', 't2'))!.unreadCount, 1);

      await store.upsertMessages('a1', [msg('m1', thread: 't2', minute: 1)]);
      expect(await summary(store, 'a1', 't1'), isNull);
      expect((await summary(store, 'a1', 't2'))!.messageCount, 2);
    });

    test('duplicate ids in one call: the last one wins', () async {
      await store.upsertMessages('a1', [msg('m1', thread: 't1', read: false), msg('m1', thread: 't1', read: true)]);
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 0);
    });

    test('accounts are isolated', () async {
      await store.upsertMessages('a1', [msg('m1', thread: 't1', read: false)]);
      await store.upsertMessages('a2', [msg('m1', account: 'a2', thread: 't1', read: true)]);
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 1);
      expect((await summary(store, 'a2', 't1'))!.unreadCount, 0);
      await store.deleteMessages('a2', ['m1']);
      expect(await summary(store, 'a1', 't1'), isNotNull);
      expect(await summary(store, 'a2', 't1'), isNull);
    });

    test('round-trips every message field', () async {
      final m = Message(
        accountId: 'a1',
        id: 'm1',
        threadId: 't1',
        subject: 'Hello',
        from: ana,
        to: const [ben, cy],
        cc: const [me],
        bcc: const [Address('hidden@x.org')],
        replyTo: const [Address('reply@x.org', 'Reply')],
        // The store returns local times; DateTime == also compares the zone.
        date: at(7).toLocal(),
        snippet: 'snip',
        isRead: false,
        isFlagged: true,
        isDraft: false,
        mailboxIds: const {'INBOX', 'Label_work'},
        attachments: const [pdf, inlineImage],
        messageIdHeader: '<abc@x.org>',
        inReplyTo: '<prev@x.org>',
        references: const ['<a@x>', '<prev@x.org>'],
        listUnsubscribe: '<mailto:unsub@x.org>',
        size: 4321,
      );
      await store.upsertMessages('a1', [m]);
      final [back] = await store.messagesInThreads('a1', ['t1']);
      expect(back, m);
      expect(back.to, m.to);
      expect(back.cc, m.cc);
      expect(back.bcc, m.bcc);
      expect(back.replyTo, m.replyTo);
      expect(back.from, ana);
      expect(back.attachments, m.attachments);
      expect(back.attachments[1].isInline, isTrue);
      expect(back.attachments[1].contentId, 'logo');
      expect(back.messageIdHeader, m.messageIdHeader);
      expect(back.inReplyTo, m.inReplyTo);
      expect(back.references, m.references);
      expect(back.listUnsubscribe, m.listUnsubscribe);
      expect(back.size, 4321);
      expect(back.isDraft, isFalse);
      expect(back.date.isAtSameMomentAs(m.date), isTrue);
    });
  });

  group('deltas', () {
    setUp(() async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, read: false),
        msg('m2', thread: 't1', minute: 2, read: false),
        msg('m3', thread: 't2', minute: 3, read: true),
      ]);
    });

    test('flags and mailboxes are applied and threads recomputed', () async {
      await store.applyDeltas('a1', [
        const MessageDelta('m1', isRead: true),
        const MessageDelta('m2', isFlagged: true, addMailboxes: {'Label_work'}, removeMailboxes: {'INBOX'}),
      ]);
      final t1 = (await summary(store, 'a1', 't1'))!;
      expect(t1.unreadCount, 1);
      expect(t1.isFlagged, isTrue);
      expect(t1.mailboxIds, {'INBOX', 'Label_work'});
      final [m1, m2] = await store.messagesInThreads('a1', ['t1']);
      expect(m1.isRead, isTrue);
      expect(m1.isFlagged, isFalse);
      expect(m2.isRead, isFalse);
      expect(m2.mailboxIds, {'Label_work'});
    });

    test('several deltas for one message apply in order', () async {
      await store.applyDeltas('a1', [
        const MessageDelta('m3', addMailboxes: {'Label_work'}),
        const MessageDelta('m3', removeMailboxes: {'Label_work', 'INBOX'}, isRead: false),
        const MessageDelta('m3', addMailboxes: {'INBOX'}),
        const MessageDelta('m3', isRead: true),
      ]);
      final [m3] = await store.messagesInThreads('a1', ['t2']);
      expect(m3.mailboxIds, {'INBOX'});
      expect(m3.isRead, isTrue);
    });

    test('unknown messages are ignored', () async {
      await store.applyDeltas('a1', [
        const MessageDelta('nope', isRead: true, addMailboxes: {'INBOX'}),
      ]);
      expect(await store.knownMessageIds('a1', ['nope', 'm1']), {'m1'});
    });

    test('archiving every message removes the thread from the inbox', () async {
      await store.applyDeltas('a1', [
        const MessageDelta('m1', removeMailboxes: {'INBOX'}),
        const MessageDelta('m2', removeMailboxes: {'INBOX'}),
      ]);
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), ['t2']);
      expect(await threadIds(store, const AllMailFilter()), ['t2', 't1']);
    });
  });

  group('deletes', () {
    setUp(() async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, read: false),
        msg('m2', thread: 't1', minute: 2),
        msg('m3', thread: 't2', minute: 3),
      ]);
      await store.saveBody('a1', 'm1', const MessageBody(text: 'hello'));
    });

    test('deleteMessages removes messages, bodies and empty threads', () async {
      await store.deleteMessages('a1', ['m1']);
      expect(await store.body('a1', 'm1'), isNull);
      final t1 = (await summary(store, 'a1', 't1'))!;
      expect(t1.messageCount, 1);
      expect(t1.unreadCount, 0);
      await store.deleteMessages('a1', ['m2', 'unknown']);
      expect(await summary(store, 'a1', 't1'), isNull);
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), ['t2']);
    });

    test('deleteThreads removes every message of the threads', () async {
      await store.deleteThreads('a1', ['t1']);
      expect(await store.knownMessageIds('a1', ['m1', 'm2', 'm3']), {'m3'});
      expect(await summary(store, 'a1', 't1'), isNull);
      expect(await store.body('a1', 'm1'), isNull);
    });
  });

  group('applyLocalMutation', () {
    setUp(() async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, read: false),
        msg('m2', thread: 't1', minute: 2, read: false),
        msg('m3', thread: 't2', minute: 3, read: false),
      ]);
    });

    test('thread scope affects every message of the threads', () async {
      await store.applyLocalMutation('a1', OperationScope.thread, [
        't1',
      ], const LocalMutation(setRead: true, removeMailboxes: {'INBOX'}));
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 0);
      expect((await summary(store, 'a1', 't2'))!.unreadCount, 1);
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), ['t2']);
      expect((await store.messagesInThreads('a1', ['t1'])).every((m) => m.mailboxIds.isEmpty), isTrue);
    });

    test('message scope affects only those messages', () async {
      await store.applyLocalMutation('a1', OperationScope.message, [
        'm2',
      ], const LocalMutation(setFlagged: true, addMailboxes: {'Label_work'}));
      final t1 = (await summary(store, 'a1', 't1'))!;
      expect(t1.isFlagged, isTrue);
      expect(t1.mailboxIds, {'INBOX', 'Label_work'});
      final [m1, m2] = await store.messagesInThreads('a1', ['t1']);
      expect(m1.isFlagged, isFalse);
      expect(m2.isFlagged, isTrue);
      expect(m2.mailboxIds, {'INBOX', 'Label_work'});
    });

    test('trash moves the thread out of the inbox and all mail', () async {
      await store.applyLocalMutation('a1', OperationScope.thread, [
        't1',
      ], const LocalMutation(addMailboxes: {'TRASH'}, removeMailboxes: {'INBOX'}));
      expect(await threadIds(store, const MailboxFilter('a1', 'TRASH')), ['t1']);
      expect(await threadIds(store, const AllMailFilter()), ['t2']);
    });

    test('delete removes messages and threads', () async {
      await store.applyLocalMutation('a1', OperationScope.thread, ['t1'], const LocalMutation(delete: true));
      expect(await summary(store, 'a1', 't1'), isNull);
      expect(await store.knownMessageIds('a1', ['m1', 'm2', 'm3']), {'m3'});
      await store.applyLocalMutation('a1', OperationScope.message, ['m3'], const LocalMutation(delete: true));
      expect(await summary(store, 'a1', 't2'), isNull);
    });

    test('onlyIn moves just the messages in those mailboxes', () async {
      await store.upsertMessages('a1', [msg('m4', thread: 't1', minute: 4, boxes: {'SENT'})]);
      await store.applyLocalMutation('a1', OperationScope.thread, [
        't1',
      ], const LocalMutation(addMailboxes: {'Archive'}, removeMailboxes: {'INBOX'}, onlyIn: {'INBOX'}));
      final byId = {for (final m in await store.messagesInThreads('a1', ['t1'])) m.id: m.mailboxIds};
      expect(byId, {'m1': {'Archive'}, 'm2': {'Archive'}, 'm4': {'SENT'}});
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), ['t2']);
    });

    test('onlyIn also limits deletes', () async {
      await store.upsertMessages('a1', [msg('m4', thread: 't1', minute: 4, boxes: {'TRASH'})]);
      await store.applyLocalMutation('a1', OperationScope.thread, [
        't1',
      ], const LocalMutation(delete: true, onlyIn: {'TRASH'}));
      expect(await store.knownMessageIds('a1', ['m1', 'm2', 'm4']), {'m1', 'm2'});
      expect((await summary(store, 'a1', 't1'))!.messageCount, 2);
    });

    test('no-op mutations and unknown ids are harmless', () async {
      await store.applyLocalMutation('a1', OperationScope.thread, ['t1'], const LocalMutation());
      await store.applyLocalMutation('a1', OperationScope.thread, ['zzz'], const LocalMutation(setRead: true));
      expect((await summary(store, 'a1', 't1'))!.unreadCount, 2);
    });
  });

  group('reads', () {
    test('watchThread emits messages oldest first and null once gone', () async {
      await store.upsertMessages('a1', [
        msg('m2', thread: 't1', minute: 2, read: false),
        msg('m1', thread: 't1', minute: 1),
      ]);
      final rec = Recorder(store.watchThread('a1', 't1'));
      await rec.waitFor(1);
      expect(rec.last!.messages.map((m) => m.id), ['m1', 'm2']);
      expect(rec.last!.summary.unreadCount, 1);

      await store.applyDeltas('a1', [const MessageDelta('m2', isRead: true)]);
      await rec.waitFor(2);
      expect(rec.last!.summary.unreadCount, 0);
      expect(rec.last!.messages.last.isRead, isTrue);

      await store.deleteThreads('a1', ['t1']);
      await rec.waitFor(3);
      expect(rec.last, isNull);
      await rec.cancel();
    });

    test('messageIdsOfThreads, knownMessageIds', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1),
        msg('m2', thread: 't1', minute: 2),
        msg('m3', thread: 't2', minute: 3),
      ]);
      expect(await store.messageIdsOfThreads('a1', ['t1', 't2']), ['m1', 'm2', 'm3']);
      expect(await store.messageIdsOfThreads('a2', ['t1']), isEmpty);
      expect(await store.knownMessageIds('a1', ['m1', 'm3', 'x']), {'m1', 'm3'});
      expect(await store.knownMessageIds('a1', []), isEmpty);
    });

    test('bodies: save, read, replace, missing', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, boxes: {'INBOX'}),
        msg('m2', thread: 't1', minute: 2, boxes: {'INBOX'}),
        msg('m3', thread: 't2', minute: 3, boxes: {'INBOX'}),
        msg('m4', thread: 't2', minute: 4, boxes: {'SENT'}),
      ]);
      final png = MessageBody(
        html: '<p>Hi</p>',
        text: 'Hi',
        inlineParts: {
          'logo': Uint8List.fromList([1, 2, 3]),
        },
      );
      await store.saveBody('a1', 'm1', png);
      final b = (await store.body('a1', 'm1'))!;
      expect(b.html, '<p>Hi</p>');
      expect(b.text, 'Hi');
      expect(b.inlineParts['logo'], [1, 2, 3]);

      await store.saveBody('a1', 'm1', const MessageBody(text: 'Replaced'));
      final b2 = (await store.body('a1', 'm1'))!;
      expect(b2.html, isNull);
      expect(b2.text, 'Replaced');
      expect(b2.inlineParts, isEmpty);

      // Unknown messages are ignored.
      await store.saveBody('a1', 'nope', const MessageBody(text: 'x'));
      expect(await store.body('a1', 'nope'), isNull);

      expect(await store.messagesWithoutBody('a1', ['m3', 'm1', 'm2', 'zz']), ['m3', 'm2', 'zz']);
      // Newest threads first, newest message first, only messages in INBOX.
      expect(await store.recentMessagesWithoutBody('a1', 'INBOX'), ['m3', 'm2']);
      expect(await store.recentMessagesWithoutBody('a1', 'INBOX', limit: 1), ['m3']);
    });
  });
}
