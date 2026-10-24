import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late DriftMailStore store;

  setUp(() async => store = await newStore());
  tearDown(() => store.close());

  group('MailboxFilter', () {
    setUp(() async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, boxes: {'INBOX'}),
        msg('m2', thread: 't2', minute: 2, boxes: {'INBOX', 'Label_work'}, read: false),
        msg('m3', thread: 't3', minute: 3, boxes: {'Label_work'}),
        // Thread t4: one message in the inbox, another (newer) labelled Work.
        msg('m4', thread: 't4', minute: 4, boxes: {'INBOX'}, read: false),
        msg('m5', thread: 't4', minute: 5, boxes: {'Label_work'}),
      ]);
    });

    test('lists threads in the mailbox, newest first', () async {
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX')), ['t4', 't2', 't1']);
      expect(await threadIds(store, const MailboxFilter('a1', 'Label_work')), ['t4', 't3', 't2']);
      expect(await threadIds(store, const MailboxFilter('a2', 'INBOX')), isEmpty);
    });

    test('alsoIn intersects', () async {
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX', alsoIn: 'Label_work')), ['t4', 't2']);
    });

    test('unread counts', () async {
      expect(await store.watchUnreadCount(const MailboxFilter('a1', 'INBOX')).first, 2);
      expect(await store.watchUnreadCount(const MailboxFilter('a1', 'Label_work')).first, 2);
      expect(await store.watchUnreadCount(const MailboxFilter('a1', 'INBOX', alsoIn: 'Label_work')).first, 2);
      expect(await store.watchUnreadCount(const MailboxFilter('a1', 'SENT')).first, 0);
    });

    test('limit and tie-breaking by id', () async {
      await store.upsertMessages('a1', [
        for (final id in ['tc', 'ta', 'tb']) msg('x$id', thread: id, minute: 10),
      ]);
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX'), limit: 4), ['ta', 'tb', 'tc', 't4']);
      expect(await threadIds(store, const MailboxFilter('a1', 'INBOX'), limit: 0), isEmpty);
    });
  });

  group('RoleFilter', () {
    test('inbox of one account and the unified inbox across accounts', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, read: false),
        msg('m3', thread: 't3', minute: 3),
        msg('m5', thread: 't5', minute: 5, boxes: {'SENT'}),
      ]);
      await store.upsertMessages('a2', [
        msg('n2', account: 'a2', thread: 'u2', minute: 2, read: false),
        msg('n4', account: 'a2', thread: 'u4', minute: 4, read: false),
      ]);
      expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, accountIds: {'a1'})), ['t3', 't1']);
      final unified = await threads(store, const RoleFilter(MailboxRole.inbox));
      expect([for (final t in unified) t.key], ['a2/u4', 'a1/t3', 'a2/u2', 'a1/t1']);
      expect(await threadIds(store, const RoleFilter(MailboxRole.inbox), limit: 2), ['u4', 't3']);
      expect(await threadIds(store, const RoleFilter(MailboxRole.sent)), ['t5']);

      expect(await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox)).first, 3);
      expect(await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, accountIds: {'a2'})).first, 2);
      expect(await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, accountIds: {'zz'})).first, 0);
    });

    test('an account without a mailbox of that role contributes nothing', () async {
      await store.saveAccount(account('a3', sortOrder: 2));
      await store.replaceMailboxes('a3', [
        const Mailbox(accountId: 'a3', id: 'Archive', name: 'Archive', role: MailboxRole.archive),
        const Mailbox(accountId: 'a3', id: 'INBOX', name: 'Not really the inbox'),
      ]);
      await store.upsertMessages('a3', [
        msg('k1', account: 'a3', thread: 'k1', boxes: {'INBOX'}),
      ]);
      await store.upsertMessages('a1', [msg('m1', thread: 't1')]);
      expect(await threadIds(store, const RoleFilter(MailboxRole.inbox)), ['t1']);
      expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, accountIds: {'a3'})), isEmpty);
      expect(await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, accountIds: {'a3'})).first, 0);
    });

    group('categories', () {
      setUp(() async {
        await store.upsertMessages('a1', [
          msg('p1', thread: 'personal', minute: 1, boxes: {'INBOX', 'CATEGORY_PERSONAL'}, read: false),
          msg('p2', thread: 'unlabelled', minute: 2, boxes: {'INBOX'}, read: false),
          msg('s1', thread: 'social', minute: 3, boxes: {'INBOX', 'CATEGORY_SOCIAL'}, read: false),
          msg('o1', thread: 'promo', minute: 4, boxes: {'INBOX', 'CATEGORY_PROMOTIONS'}),
          msg('o2', thread: 'promo-archived', minute: 5, boxes: {'CATEGORY_PROMOTIONS'}),
          msg('u1', thread: 'updates', minute: 6, boxes: {'INBOX', 'CATEGORY_UPDATES'}),
          msg('f1', thread: 'forums', minute: 7, boxes: {'INBOX', 'CATEGORY_FORUMS'}),
          // A conversation where one message was categorised as social.
          msg('x1', thread: 'mixed', minute: 8, boxes: {'INBOX', 'CATEGORY_PERSONAL'}),
          msg('x2', thread: 'mixed', minute: 9, boxes: {'INBOX', 'CATEGORY_SOCIAL'}),
        ]);
      });

      test('primary excludes the other categories, with or without CATEGORY_PERSONAL', () async {
        expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.primary)), [
          'unlabelled',
          'personal',
        ]);
        expect(
          await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, category: MailCategory.primary)).first,
          2,
        );
      });

      test('other categories intersect the inbox', () async {
        expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.social)), [
          'mixed',
          'social',
        ]);
        expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.promotions)), [
          'promo',
        ]);
        expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.updates)), [
          'updates',
        ]);
        expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.forums)), ['forums']);
        expect(
          await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, category: MailCategory.social)).first,
          1,
        );
      });

      test('the category role selects the category mailbox itself', () async {
        expect(await threadIds(store, const RoleFilter(MailboxRole.category, category: MailCategory.promotions)), [
          'promo-archived',
          'promo',
        ]);
      });

      test('unified primary inbox across accounts', () async {
        await store.upsertMessages('a2', [
          msg('q1', account: 'a2', thread: 'b-primary', minute: 3, boxes: {'INBOX'}, read: false),
          msg('q2', account: 'a2', thread: 'b-promo', minute: 10, boxes: {'INBOX', 'CATEGORY_PROMOTIONS'}),
        ]);
        final list = await threads(store, const RoleFilter(MailboxRole.inbox, category: MailCategory.primary));
        expect([for (final t in list) t.key], ['a2/b-primary', 'a1/unlabelled', 'a1/personal']);
        expect(
          await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox, category: MailCategory.primary)).first,
          3,
        );
      });

      test('accounts without categories: primary is the whole inbox, others empty', () async {
        await store.saveAccount(account('imap', sortOrder: 5));
        await store.replaceMailboxes('imap', [
          const Mailbox(accountId: 'imap', id: 'INBOX', name: 'Inbox', role: MailboxRole.inbox),
        ]);
        await store.upsertMessages('imap', [msg('i1', account: 'imap', thread: 'i1', minute: 0)]);
        expect(
          await threadIds(
            store,
            const RoleFilter(MailboxRole.inbox, category: MailCategory.primary, accountIds: {'imap'}),
          ),
          ['i1'],
        );
        expect(
          await threadIds(
            store,
            const RoleFilter(MailboxRole.inbox, category: MailCategory.social, accountIds: {'imap'}),
          ),
          isEmpty,
        );
      });
    });
  });

  group('FlaggedFilter and AllMailFilter', () {
    setUp(() async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 'inbox', minute: 1, flagged: true, read: false),
        msg('m2', thread: 'archived', minute: 2, boxes: {}, flagged: true),
        msg('m3', thread: 'trashed', minute: 3, boxes: {'TRASH'}, flagged: true, read: false),
        msg('m4', thread: 'spam', minute: 4, boxes: {'SPAM'}, read: false),
        // One message trashed, one still in the inbox.
        msg('m5', thread: 'partly-trashed', minute: 5, boxes: {'TRASH'}, flagged: true),
        msg('m6', thread: 'partly-trashed', minute: 6, boxes: {'INBOX'}, read: false),
        msg('m7', thread: 'sent', minute: 7, boxes: {'SENT'}),
      ]);
      await store.upsertMessages('a2', [
        msg('n1', account: 'a2', thread: 'other', minute: 8, flagged: true, read: false),
      ]);
    });

    test('flagged excludes threads entirely in trash or junk', () async {
      expect(await threadIds(store, const FlaggedFilter(accountIds: {'a1'})), ['partly-trashed', 'archived', 'inbox']);
      expect(await threadIds(store, const FlaggedFilter()), ['other', 'partly-trashed', 'archived', 'inbox']);
      expect(await store.watchUnreadCount(const FlaggedFilter()).first, 3);
      expect(await store.watchUnreadCount(const FlaggedFilter(accountIds: {'a2'})).first, 1);
    });

    test('all mail has threads with a message outside trash and junk', () async {
      expect(await threadIds(store, const AllMailFilter(accountIds: {'a1'})), [
        'sent',
        'partly-trashed',
        'archived',
        'inbox',
      ]);
      expect(await threadIds(store, const AllMailFilter()), ['other', 'sent', 'partly-trashed', 'archived', 'inbox']);
      expect(await store.watchUnreadCount(const AllMailFilter()).first, 3);
    });

    test('restoring from trash brings the thread back', () async {
      await store.applyDeltas('a1', [
        const MessageDelta('m3', removeMailboxes: {'TRASH'}, addMailboxes: {'INBOX'}),
      ]);
      expect(await threadIds(store, const FlaggedFilter(accountIds: {'a1'})), [
        'partly-trashed',
        'trashed',
        'archived',
        'inbox',
      ]);
    });

    test('a change of trash/junk mailboxes recomputes every thread', () async {
      // The provider renames its trash: the old TRASH loses its role.
      final boxes = [
        for (final m in gmailMailboxes('a1'))
          if (m.id != 'TRASH') m,
        const Mailbox(accountId: 'a1', id: 'TRASH', name: 'Old trash'),
        const Mailbox(accountId: 'a1', id: 'BIN', name: 'Bin', role: MailboxRole.trash),
      ];
      await store.replaceMailboxes('a1', boxes);
      expect(await threadIds(store, const AllMailFilter(accountIds: {'a1'})), [
        'sent',
        'partly-trashed',
        'trashed',
        'archived',
        'inbox',
      ]);
    });
  });

  group('ThreadSetFilter', () {
    test('returns the exact keys in order, skipping unknown ones, with limit', () async {
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', minute: 1, read: false),
        msg('m2', thread: 't2', minute: 2),
      ]);
      await store.upsertMessages('a2', [msg('n1', account: 'a2', thread: 'u1', minute: 3, read: false)]);
      const filter = ThreadSetFilter(['a1/t1', 'a2/u1', 'a1/missing', 'a1/t2', 'a1/t1', 'garbage']);
      expect([for (final t in await threads(store, filter)) t.key], ['a1/t1', 'a2/u1', 'a1/t2']);
      expect(await threadIds(store, filter, limit: 2), ['t1', 'u1']);
      expect(await store.watchUnreadCount(filter).first, 2);
      expect(await threadIds(store, const ThreadSetFilter([])), isEmpty);
    });
  });

  group('reactivity', () {
    test('emits on relevant changes only', () async {
      await store.upsertMessages('a1', [msg('m1', thread: 't1', minute: 1)]);
      final list = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox)));
      final count = Recorder(store.watchUnreadCount(const RoleFilter(MailboxRole.inbox)));
      await list.waitFor(1);
      await count.waitFor(1);
      expect(list.last.map((t) => t.id), ['t1']);
      expect(count.last, 0);

      // Unrelated writes.
      await store.writeSetting('theme', 'dark');
      await store.saveBody('a1', 'm1', const MessageBody(text: 'body'));
      await store.writeState('a1', 'historyId', '42');
      await store.updateMailboxCounts('a1', {'INBOX': (unread: 5, total: 9)});
      await store.upsertMessages('a1', [
        msg('m9', thread: 't9', minute: 9, boxes: {'SENT'}),
      ]);
      await store.upsertMessages('a1', [msg('m1', thread: 't1', minute: 1)]);
      await Recorder.settle();
      expect(list.events, hasLength(1));
      expect(count.events, hasLength(1));

      await store.upsertMessages('a1', [msg('m2', thread: 't2', minute: 2, read: false)]);
      await list.waitFor(2);
      await count.waitFor(2);
      expect(list.last.map((t) => t.id), ['t2', 't1']);
      expect(count.last, 1);

      await store.applyLocalMutation('a1', OperationScope.thread, ['t2'], const LocalMutation(setRead: true));
      await count.waitFor(3);
      expect(count.last, 0);
      await list.waitFor(3);
      expect(list.last.first.unreadCount, 0);

      await list.cancel();
      await count.cancel();
    });

    test('role filters follow account and mailbox changes', () async {
      final list = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox)));
      await list.waitFor(1);
      expect(list.last, isEmpty);

      await store.saveAccount(account('a3', sortOrder: 3));
      await store.upsertMessages('a3', [
        msg('k1', account: 'a3', thread: 'k1', boxes: {'IN'}),
      ]);
      await Recorder.settle();
      expect(list.last, isEmpty);

      await store.replaceMailboxes('a3', [
        const Mailbox(accountId: 'a3', id: 'IN', name: 'Inbox', role: MailboxRole.inbox),
      ]);
      await list.waitFor(2);
      expect(list.last.map((t) => t.key), ['a3/k1']);

      await store.deleteAccount('a3');
      await list.waitFor(3);
      expect(list.last, isEmpty);
      await list.cancel();
    });

    test('several listeners and re-listening work', () async {
      await store.upsertMessages('a1', [msg('m1', thread: 't1')]);
      final stream = store.watchThreads(const RoleFilter(MailboxRole.inbox));
      expect((await stream.first).single.id, 't1');
      final a = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox)));
      final b = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox)));
      await a.waitFor(1);
      await b.waitFor(1);
      await store.upsertMessages('a1', [msg('m2', thread: 't2', minute: 5)]);
      await a.waitFor(2);
      await b.waitFor(2);
      await a.cancel();
      await b.cancel();
    });
  });
}
