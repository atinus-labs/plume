import 'dart:io';

import 'package:drift/drift.dart' show Uint8List, Variable;
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Row counts of every table for [accountId] (plus the account-less ones).
Future<Map<String, int>> counts(DriftMailStore store, String accountId) async {
  final db = store.db;
  Future<int> count(String sql) async =>
      (await db.customSelect(sql, variables: [Variable(accountId)]).getSingle()).read<int>('c');
  return {
    'accounts': await count('SELECT count(*) AS c FROM accounts WHERE id = ?'),
    for (final t in [
      'mailboxes',
      'messages',
      'message_mailboxes',
      'threads',
      'thread_mailboxes',
      'bodies',
      'body_parts',
      'sync_state',
      'pending_ops',
      'outbox',
    ])
      t: await count('SELECT count(*) AS c FROM $t WHERE account_id = ?'),
  };
}

Future<int> ftsRows(DriftMailStore store) async =>
    (await store.db.customSelect('SELECT count(*) AS c FROM message_fts_docsize').getSingle()).read<int>('c');

Future<void> populate(DriftMailStore store, String a) async {
  await store.upsertMessages(a, [
    msg('m1', account: a, thread: 't1', subject: 'Alpha $a', minute: 1, read: false),
    msg('m2', account: a, thread: 't1', subject: 'Re: Alpha', minute: 2, boxes: {'SENT'}),
    msg('m3', account: a, thread: 't2', subject: 'Beta', minute: 3),
  ]);
  await store.saveBody(a, 'm1', MessageBody(html: '<p>zebra</p>', inlineParts: {'c': Uint8List(3)}));
  await store.writeState(a, 'historyId', '7');
  await store.enqueueOperation(
    ActionOperation(accountId: a, scope: OperationScope.thread, ids: const ['t1'], action: MailAction.archive),
  );
  await store.enqueueOutgoing(OutgoingMessage(accountId: a, from: Address('$a@example.com')), DateTime.now());
}

void main() {
  group('clearMail and deleteAccount', () {
    late DriftMailStore store;

    setUp(() async {
      store = await newStore();
      await populate(store, 'a1');
      await populate(store, 'a2');
      await store.writeSetting('theme', 'dark');
    });
    tearDown(() => store.close());

    test('clearMail wipes mail and cursors, keeps the rest', () async {
      final before = await counts(store, 'a2');
      expect(await ftsRows(store), 6);
      await store.clearMail('a1');
      final after = await counts(store, 'a1');
      expect(after, {
        'accounts': 1,
        'mailboxes': gmailMailboxes('a1').length,
        'messages': 0,
        'message_mailboxes': 0,
        'threads': 0,
        'thread_mailboxes': 0,
        'bodies': 0,
        'body_parts': 0,
        'sync_state': 0,
        'pending_ops': 1,
        'outbox': 1,
      });
      expect(await counts(store, 'a2'), before);
      expect(await ftsRows(store), 3);
      expect(await threadIds(store, const RoleFilter(MailboxRole.inbox, accountIds: {'a1'})), isEmpty);
      expect((await store.searchLocal('zebra')).map((t) => t.key), ['a2/t1']);
      expect(await store.suggestAddresses('ana'), isNotEmpty);
      expect(await store.readSetting('theme'), 'dark');

      // A resync can store everything again.
      await populate(store, 'a1');
      expect((await store.searchLocal('zebra')).map((t) => t.key).toSet(), {'a1/t1', 'a2/t1'});
    });

    test('deleteAccount cascades to everything the account owns', () async {
      final before = await counts(store, 'a2');
      final rec = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox)));
      await rec.waitFor(1);
      expect(rec.last, hasLength(4));

      await store.deleteAccount('a1');
      expect((await counts(store, 'a1')).values.every((c) => c == 0), isTrue, reason: '${await counts(store, 'a1')}');
      expect(await counts(store, 'a2'), before);
      expect(await ftsRows(store), 3);
      expect((await store.accounts()).map((a) => a.id), ['a2']);
      expect(await store.pendingOperations(accountId: 'a1'), isEmpty);
      expect(await store.readSetting('theme'), 'dark');

      await rec.waitFor(2);
      expect(rec.last.map((t) => t.accountId).toSet(), {'a2'});
      await rec.cancel();
    });
  });

  group('transactions', () {
    late DriftMailStore store;

    setUp(() async => store = await newStore());
    tearDown(() => store.close());

    test('nested store calls commit together and notify once', () async {
      final rec = Recorder(store.watchThreads(const MailboxFilter('a1', 'INBOX')));
      await rec.waitFor(1);
      final result = await store.transaction(() async {
        await store.upsertMessages('a1', [msg('m1', thread: 't1', minute: 1, read: false)]);
        await Recorder.settle();
        expect(rec.events, hasLength(1), reason: 'no emission before the outer transaction commits');
        await store.transaction(() async {
          await store.upsertMessages('a1', [msg('m2', thread: 't2', minute: 2)]);
          await store.applyLocalMutation('a1', OperationScope.thread, ['t1'], const LocalMutation(setRead: true));
        });
        await store.writeState('a1', 'historyId', '9');
        return 42;
      });
      expect(result, 42);
      await rec.waitFor(2);
      await Recorder.settle();
      expect(rec.events, hasLength(2));
      expect(rec.last.map((t) => (t.id, t.unreadCount)), [('t2', 0), ('t1', 0)]);
      expect(await store.readState('a1', 'historyId'), '9');
      await rec.cancel();
    });

    test('a failing inner transaction rolls back only itself', () async {
      await store.transaction(() async {
        await store.upsertMessages('a1', [msg('m1', thread: 't1')]);
        await expectLater(
          store.transaction(() async {
            await store.upsertMessages('a1', [msg('m2', thread: 't2', subject: 'ghost')]);
            await store.saveBody('a1', 'm2', const MessageBody(text: 'ghost body'));
            throw StateError('boom');
          }),
          throwsStateError,
        );
        await store.writeSetting('after', 'yes');
      });
      expect(await store.knownMessageIds('a1', ['m1', 'm2']), {'m1'});
      expect(await summary(store, 'a1', 't2'), isNull);
      expect(await store.searchLocal('ghost'), isEmpty);
      expect(await store.readSetting('after'), 'yes');
    });

    test('a failing outer transaction rolls back everything', () async {
      await expectLater(
        store.transaction(() async {
          await store.upsertMessages('a1', [msg('m1', thread: 't1', subject: 'phantom')]);
          await store.transaction(() => store.writeState('a1', 'historyId', '1'));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await store.knownMessageIds('a1', ['m1']), isEmpty);
      expect(await summary(store, 'a1', 't1'), isNull);
      expect(await store.searchLocal('phantom'), isEmpty);
      expect(await store.readState('a1', 'historyId'), isNull);
    });

    test('concurrent writers are serialised', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) store.upsertMessages('a1', [msg('m$i', thread: 't${i % 3}', minute: i)]),
      ]);
      final list = await threads(store, const MailboxFilter('a1', 'INBOX'));
      expect(list.fold<int>(0, (n, t) => n + t.messageCount), 20);
    });
  });

  group('file database', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('plume_store_test'));
    tearDown(() => dir.delete(recursive: true));

    test('opens in a background isolate with WAL, foreign keys and SQL functions; persists', () async {
      final path = '${dir.path}/nested/mail.sqlite';
      var store = DriftMailStore.open(path);
      // Inside a transaction to run on the writer connection.
      final pragmas = await store.transaction(
        () => store.db.customSelect('SELECT * FROM pragma_journal_mode, pragma_foreign_keys').getSingle(),
      );
      expect(pragmas.data.values, ['wal', 1]);
      await store.saveAccount(account('a1'));
      await store.replaceMailboxes('a1', gmailMailboxes('a1'));
      await store.upsertMessages('a1', [
        msg('m1', thread: 't1', subject: 'Persisted', minute: 1, read: false, from: const Address('x@y.z', 'Xavier')),
      ]);
      await store.saveBody('a1', 'm1', const MessageBody(html: '<p>quokka</p>'));
      // Reads may run on a reader isolate: functions and data must be there.
      expect((await store.searchLocal('quokka')).single.id, 't1');
      expect((await threads(store, const RoleFilter(MailboxRole.inbox))).single.participants.single.name, 'Xavier');
      await store.close();
      expect(File(path).existsSync(), isTrue);

      store = DriftMailStore.open(path, readPool: 0);
      expect((await threads(store, const RoleFilter(MailboxRole.inbox))).single.subject, 'Persisted');
      expect(await store.watchUnreadCount(const RoleFilter(MailboxRole.inbox)).first, 1);
      // Foreign keys are enforced: data needs its account.
      await expectLater(store.upsertMessages('nobody', [msg('x', account: 'nobody')]), throwsA(anything));
      await store.close();
    });
  });
}
