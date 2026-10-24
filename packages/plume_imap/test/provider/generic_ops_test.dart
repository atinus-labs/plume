import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/provider/ids.dart';
import 'package:test/test.dart';

import '../support/fake_imap_server.dart';
import '../support/provider_harness.dart';
import 'generic_sync_test.dart' show seedConversation;

void main() {
  late Harness h;

  tearDown(() async => h.dispose());

  Future<String> lunchThread() async => (await h.bySubject('Lunch?')).threadId;

  group('archive', () {
    test('creates Archive on first use, moves only INBOX messages, re-keys with COPYUID', () async {
      h = await Harness.start(seed: (s) {
        seedConversation(s);
        s.mailboxes.remove('Archives');
      });
      await h.sync();
      final thread = await lunchThread();
      final before = await h.store.messagesInThreads(h.accountId, [thread]);
      final inboxIds = [for (final m in before) if (m.mailboxIds.contains('INBOX')) m.id];
      await h.provider.fetchBodies(h.store, inboxIds);

      await h.perform(h.action(MailAction.archive, [thread]));

      expect(h.server.commands('CREATE'), ['CREATE "Archive"']);
      expect(h.server.mailboxes['Archive']!.entries, hasLength(2));
      expect(h.server.mailboxes['Sent']!.entries, hasLength(1), reason: 'the reply in Sent stays');
      final after = await h.store.messagesInThreads(h.accountId, [thread]);
      expect(after, hasLength(3));
      final archived = [for (final m in after) if (m.mailboxIds.contains('Archive')) m];
      expect(archived, hasLength(2));
      for (final m in archived) {
        expect(ImapIds.parse(m.id)!.path, 'Archive', reason: 're-keyed to the new UID');
        expect(m.mailboxIds, {'Archive'});
      }
      expect(await h.store.messagesWithoutBody(h.accountId, [for (final m in archived) m.id]), isEmpty,
          reason: 'cached bodies survive the move');
      expect(after.where((m) => m.mailboxIds.contains('Sent')), hasLength(1));

      // The next sync neither duplicates nor drops anything.
      await h.sync();
      final synced = await h.store.messagesInThreads(h.accountId, [thread]);
      expect(synced.map((m) => m.id).toSet(), after.map((m) => m.id).toSet());
      expect((await h.store.mailboxes(h.accountId)).singleWhere((m) => m.id == 'Archive').role, MailboxRole.archive);

      // Undo (thread scope) brings them back.
      await h.perform(h.action(MailAction.moveToInbox, [thread]));
      final back = await h.store.messagesInThreads(h.accountId, [thread]);
      expect([for (final m in back) if (m.mailboxIds.contains('INBOX')) m], hasLength(2));
      expect(h.server.mailboxes['INBOX']!.entries.length, 3);
    });

    test('message-scoped undo with ids from before the move still works', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final root = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
      final archive = h.action(MailAction.archive, [root.id], scope: OperationScope.message);
      await h.perform(archive);
      expect(await h.store.knownMessageIds(h.accountId, [root.id]), isEmpty, reason: 'renamed');
      // The engine's inverse carries the original id. Its optimistic effect
      // already finds the renamed message, before any server round trip.
      final undo = MailEngine.inverseOf(archive)!;
      await h.optimistic(undo);
      final optimistic = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
      expect(optimistic.mailboxIds, {'INBOX'});
      await h.provider.execute(h.store, undo);
      final now = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
      expect(now.mailboxIds, {'INBOX'});
      expect(ImapIds.parse(now.id)!.path, 'INBOX');
      expect(h.server.mailboxes['Archives']!.entries, isEmpty);
      // Renames survive a restart (a provider created anew).
      final fresh = ImapProvider(account: h.account, tokens: h.tokens, sender: h.sender);
      await fresh.execute(h.store, h.action(MailAction.markRead, [root.id], scope: OperationScope.message));
      await fresh.dispose();
      expect(h.server.mailboxes['INBOX']!.entries.where((e) => e.$2.flags.contains(r'\Seen')), hasLength(2));
    });

    test('without MOVE: COPY, \\Deleted and UID EXPUNGE; without UIDPLUS: found by Message-ID', () async {
      h = await Harness.start(
        seed: seedConversation,
        capabilities: {...FakeImapServer.genericCapabilities}..removeAll(['MOVE', 'UIDPLUS']),
      );
      await h.sync();
      final thread = await lunchThread();
      await h.perform(h.action(MailAction.archive, [thread]));
      expect(h.server.commands('UID COPY'), hasLength(1));
      expect(h.server.commands('EXPUNGE'), hasLength(1), reason: 'plain EXPUNGE without UIDPLUS');
      expect(h.server.commands('UID SEARCH').where((c) => c.contains('HEADER Message-ID')), hasLength(2));
      final archived = await h.inMailbox('Archives');
      expect(archived, hasLength(2));
      expect(archived.every((m) => ImapIds.parse(m.id)!.path == 'Archives'), isTrue);
    });
  });

  test('trash, restore, spam, not spam, delete forever', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final thread = await lunchThread();

    await h.perform(h.action(MailAction.trash, [thread]));
    expect(h.server.mailboxes['Trash']!.entries, hasLength(3), reason: 'the whole conversation, Sent included');
    expect(await h.inMailbox('Trash'), hasLength(3));
    await h.sync();
    expect(await h.inMailbox('Trash'), hasLength(3));

    await h.perform(h.action(MailAction.restore, [thread]));
    expect(h.server.mailboxes['Trash']!.entries, isEmpty);
    expect(await h.inMailbox('INBOX'), hasLength(4));

    await h.perform(h.action(MailAction.markSpam, [thread]));
    expect(h.server.mailboxes['Junk']!.entries, hasLength(3));
    await h.perform(h.action(MailAction.markNotSpam, [thread]));
    expect(h.server.mailboxes['Junk']!.entries, isEmpty);

    await h.perform(h.action(MailAction.trash, [thread]));
    await h.perform(h.action(MailAction.deleteForever, [thread]));
    expect(h.server.mailboxes['Trash']!.entries, isEmpty);
    expect(h.server.commands('UID EXPUNGE'), hasLength(1));
    expect(await h.store.messagesInThreads(h.accountId, [thread]), isEmpty);
    await h.sync();
    expect(await h.store.messagesInThreads(h.accountId, [thread]), isEmpty);
  });

  test('read, unread, flag, unflag change flags in every folder of the thread', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final thread = await lunchThread();
    await h.perform(h.action(MailAction.markRead, [thread]));
    expect(h.server.mailboxes['INBOX']!.entries.take(2).every((e) => e.$2.flags.contains(r'\Seen')), isTrue);
    await h.perform(h.action(MailAction.flag, [thread]));
    expect(h.server.mailboxes['Sent']!.entries.single.$2.flags, contains(r'\Flagged'));
    await h.perform(h.action(MailAction.unflag, [thread]));
    await h.perform(h.action(MailAction.markUnread, [thread]));
    expect(h.server.mailboxes['INBOX']!.entries.first.$2.flags, isEmpty);
    expect((await h.store.messagesInThreads(h.accountId, [thread])).where((m) => !m.isRead), hasLength(3));
    h.server.clearLog();
    await h.sync();
    // The flag snapshot was updated with the change: no spurious deltas.
    expect((await h.store.messagesInThreads(h.accountId, [thread])).where((m) => !m.isRead), hasLength(3));
  });

  test('label operations move between folders; TRYCREATE is handled', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final kickoff = await h.bySubject('Kickoff');
    await h.perform(LabelOperation(
      accountId: h.accountId,
      scope: OperationScope.thread,
      ids: [kickoff.threadId],
      add: {'Projects'},
      remove: {'Projects/2026'},
    ));
    expect(h.server.mailboxes['Projects']!.entries, hasLength(1));
    expect((await h.bySubject('Kickoff')).mailboxIds, {'Projects'});

    // A folder deleted by another client: the move gets TRYCREATE.
    h.server.mailboxes.remove('Archives');
    h.server.intercept = null;
    final lunch = await lunchThread();
    await expectLater(h.perform(h.action(MailAction.archive, [lunch])), completes);
    expect(h.server.commands('CREATE'), ['CREATE "Archives"']);
    expect(h.server.mailboxes['Archives']!.entries, hasLength(2));
  });

  test('vanished targets: NotFoundException for message scope, no-op for nothing to do', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final root = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
    // Archiving a thread that only has Sent messages left does nothing.
    final sent = (await h.inMailbox('Sent')).single;
    await h.store.deleteMessages(h.accountId, [for (final m in await h.inMailbox('INBOX')) if (m.threadId == sent.threadId) m.id]);
    await h.provider.execute(h.store, h.action(MailAction.archive, [sent.threadId]));
    expect(h.server.commands('UID MOVE'), isEmpty);

    await expectLater(
      h.provider.execute(h.store, h.action(MailAction.archive, ['no-such-thread'])),
      throwsA(isA<NotFoundException>()),
    );
    await expectLater(
      h.provider.execute(h.store, h.action(MailAction.markRead, ['garbage'], scope: OperationScope.message)),
      throwsA(isA<NotFoundException>()),
    );
    // Old UIDVALIDITY: the message is gone; the command is skipped.
    h.server.resetUidValidity('INBOX');
    await h.provider.execute(h.store, h.action(MailAction.markRead, [root.id], scope: OperationScope.message));
    expect(h.server.commands('UID STORE'), isEmpty);
  });

  test('local effects use folder semantics', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final boxes = await h.store.mailboxes(h.accountId);
    LocalMutation effect(MailAction a) => h.provider.localEffect(h.action(a, ['t']), boxes);
    expect(effect(MailAction.archive).onlyIn, {'INBOX'});
    expect(effect(MailAction.archive).addMailboxes, {'Archives'});
    expect(effect(MailAction.moveToInbox).onlyIn, {'Archives', 'Projects', 'Projects/2026'});
    expect(effect(MailAction.trash).onlyIn, isNot(contains('Trash')));
    expect(effect(MailAction.trash).onlyIn, containsAll(['INBOX', 'Sent', 'Junk']));
    expect(effect(MailAction.deleteForever).delete, isTrue);
    expect(effect(MailAction.deleteForever).onlyIn, {'Trash', 'Junk'});
    expect(effect(MailAction.markSpam).addMailboxes, {'Junk'});
    expect(effect(MailAction.markNotSpam).onlyIn, {'Junk'});
    expect(effect(MailAction.restore).addMailboxes, {'INBOX'});
    expect(effect(MailAction.markRead).setRead, isTrue);
    expect(effect(MailAction.unflag).setFlagged, isFalse);
    final move = h.provider.localEffect(
        LabelOperation(accountId: h.accountId, scope: OperationScope.thread, ids: ['t'], add: {'Projects'}, remove: {'INBOX'}),
        boxes);
    expect(move.addMailboxes, {'Projects'});
    expect(move.removeMailboxes, {'INBOX'});
    expect(move.onlyIn, {'INBOX'});
    // No Archive folder yet: the optimistic move targets the one that will
    // be created.
    final withoutArchive = [for (final b in boxes) if (b.role != MailboxRole.archive) b];
    expect(h.provider.localEffect(h.action(MailAction.archive, ['t']), withoutArchive).addMailboxes, {'Archive'});
    expect(h.provider.capabilities.labels, isFalse);
    expect(h.provider.capabilities.serverSearch, isTrue);
  });
}
