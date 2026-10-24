import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/provider/ids.dart';
import 'package:test/test.dart';

import '../support/fake_imap_server.dart';
import '../support/provider_harness.dart';

void seedConversation(FakeImapServer s) {
  s
    ..addMailbox('Projects')
    ..addMailbox('Projects/2026')
    ..addMailbox('Archives') // name-based archive role (no SPECIAL-USE)
    ..deliver('INBOX', rawMessage(id: 'root@example.com', subject: 'Lunch?', body: 'Shall we have lunch on Friday?'))
    ..deliver('Sent',
        rawMessage(
          id: 'reply@example.org',
          from: 'Ana <ana@example.org>',
          to: 'Ben Okafor <ben@example.com>',
          subject: 'Re: Lunch?',
          body: 'Yes!\r\n\r\n> Shall we have lunch on Friday?',
          inReplyTo: 'root@example.com',
          references: ['root@example.com'],
          date: 'Mon, 02 Mar 2026 11:00:00 +0000',
        ),
        flags: {r'\Seen'})
    ..deliver('INBOX', rawMessage(
      id: 'follow@example.com',
      subject: 'Re: Lunch?',
      body: 'Great, 12:30 then.',
      inReplyTo: 'reply@example.org',
      references: ['root@example.com', 'reply@example.org'],
      date: 'Mon, 02 Mar 2026 12:00:00 +0000',
    ))
    ..deliver('INBOX', richMessage(id: 'rich@example.net'), flags: {r'\Seen', r'\Flagged'})
    ..deliver('Projects/2026', rawMessage(id: 'p1@example.com', subject: 'Kickoff'));
}

void main() {
  late Harness h;

  tearDown(() async => h.dispose());

  test('initial sync: mailboxes, roles, ids, threads, previews, attachments', () async {
    h = await Harness.start(seed: seedConversation);
    final result = await h.sync();
    expect(result.fullResync, isTrue);
    expect(result.newMessages, isEmpty, reason: 'no notifications for the first sync');

    final boxes = {for (final m in await h.store.mailboxes(h.accountId)) m.id: m};
    expect(boxes['INBOX']!.role, MailboxRole.inbox);
    expect(boxes['Sent']!.role, MailboxRole.sent);
    expect(boxes['Drafts']!.role, MailboxRole.drafts);
    expect(boxes['Trash']!.role, MailboxRole.trash);
    expect(boxes['Junk']!.role, MailboxRole.junk);
    expect(boxes['Archives']!.role, MailboxRole.archive, reason: 'found by name');
    expect(boxes['Archives']!.kind, MailboxKind.system);
    expect(boxes['Projects/2026']!.parentId, 'Projects');
    expect(boxes['Projects/2026']!.name, '2026');
    expect(boxes['Projects']!.kind, MailboxKind.user);
    expect(boxes['INBOX']!.totalThreads, 3, reason: 'message counts from LIST-STATUS');
    expect(boxes['INBOX']!.unreadThreads, 2);

    final all = await h.messages();
    expect(all, hasLength(5));
    final lunch = all.values.where((m) => m.subject.contains('Lunch')).toList();
    expect(lunch.map((m) => m.threadId).toSet(), hasLength(1), reason: 'the Sent reply joins the inbox thread');
    final reply = lunch.singleWhere((m) => m.mailboxIds.contains('Sent'));
    expect(ImapIds.parse(reply.id)!.path, 'Sent');
    expect(reply.isRead, isTrue);
    final root = all.values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
    expect(root.id, matches(RegExp(r'^\d+\.1@INBOX$')));
    expect(root.snippet, 'Shall we have lunch on Friday?');
    expect(root.from, const Address('ben@example.com', 'Ben Okafor'));
    expect(root.isRead, isFalse);
    expect(reply.snippet, 'Yes!', reason: 'quoted lines are not part of the preview');

    final rich = all.values.singleWhere((m) => m.subject == 'Report');
    expect(rich.isFlagged, isTrue);
    expect(rich.snippet, 'Quarterly numbers — see attached.');
    expect(rich.attachments.map((a) => (a.partId, a.filename, a.isInline)), [('1.2', 'logo.png', true), ('2', 'q3.pdf', false)]);
    expect(rich.hasAttachments, isTrue);
    expect(rich.attachments[1].size, closeTo(3000, 120));

    final kickoff = all.values.singleWhere((m) => m.subject == 'Kickoff');
    expect(kickoff.mailboxIds, {'Projects/2026'});
  });

  test('incremental sync: new mail is reported, unchanged folders are skipped', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    h.server.clearLog();
    expect((await h.sync()).newMessages, isEmpty);
    // Without changes only INBOX is selected (its flags are compared each
    // pass when the server lacks QRESYNC; CONDSTORE makes that cheap).
    expect(h.server.commands('SELECT').map((c) => c.split(' ')[1]), everyElement('INBOX'));

    h.server.deliver('INBOX', rawMessage(id: 'new@example.com', subject: 'Invoice', body: 'Attached.'));
    h.server.deliver('INBOX', rawMessage(id: 'mine@example.org', from: 'ana@example.org', subject: 'Note to self'));
    h.server.deliver('Projects', rawMessage(id: 'p2@example.com', subject: 'Budget'));
    h.server.clearLog();
    final result = await h.sync();
    expect(result.fullResync, isFalse);
    expect(result.newMessages.map((m) => m.subject), ['Invoice'], reason: 'own mail and other folders do not notify');
    expect((await h.bySubject('Budget')).mailboxIds, {'Projects'});
    expect(h.server.commands('SELECT').map((c) => c.split(' ')[1]).toSet(), {'INBOX', '"Projects"'});
  });

  test('flag changes and deletions made elsewhere (CONDSTORE)', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final inbox = h.server.mailboxes['INBOX']!;
    final root = inbox.entries.first.$2;
    h.server.setFlags(root, {r'\Seen', r'\Flagged'});
    h.server.remove(inbox, [inbox.entries[1].$2]);
    await h.sync();
    final m = await h.store.messagesInThreads(h.accountId, [(await h.bySubject('Lunch?')).threadId]);
    final stored = m.singleWhere((x) => x.messageIdHeader == '<root@example.com>');
    expect(stored.isRead, isTrue);
    expect(stored.isFlagged, isTrue);
    expect(m.where((x) => x.messageIdHeader == '<follow@example.com>'), isEmpty, reason: 'deleted on the server');
    expect(h.server.commands('UID FETCH').any((c) => c.contains('CHANGEDSINCE')), isTrue);
  });

  test('flags and deletions without CONDSTORE are found by comparing', () async {
    h = await Harness.start(
      seed: seedConversation,
      capabilities: {...FakeImapServer.genericCapabilities}..remove('CONDSTORE'),
    );
    await h.sync();
    final inbox = h.server.mailboxes['INBOX']!;
    h.server.setFlags(inbox.entries.first.$2, {r'\Seen'});
    h.server.remove(inbox, [inbox.entries.last.$2]);
    await h.sync();
    final all = await h.messages();
    expect(all.values.singleWhere((m) => m.messageIdHeader == '<root@example.com>').isRead, isTrue);
    expect(all.values.where((m) => m.subject == 'Report'), isEmpty);
  });

  test('QRESYNC: deletions and flag changes come with SELECT', () async {
    h = await Harness.start(seed: seedConversation, capabilities: {...FakeImapServer.genericCapabilities, 'QRESYNC'});
    await h.sync();
    final inbox = h.server.mailboxes['INBOX']!;
    h.server.setFlags(inbox.entries.first.$2, {r'\Seen'});
    h.server.remove(inbox, [inbox.entries.last.$2]);
    h.server.clearLog();
    await h.sync();
    expect(h.server.commands('SELECT').first, contains('QRESYNC'));
    expect(h.server.commands('UID SEARCH'), isEmpty, reason: 'no UID comparison needed');
    final all = await h.messages();
    expect(all.values.singleWhere((m) => m.messageIdHeader == '<root@example.com>').isRead, isTrue);
    expect(all.values.where((m) => m.subject == 'Report'), isEmpty);
  });

  test('a UIDVALIDITY change replaces the folder\'s messages', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final before = (await h.inMailbox('INBOX')).map((m) => m.id).toSet();
    await h.provider.fetchBodies(h.store, before.toList());
    h.server.resetUidValidity('INBOX');
    await h.sync();
    final after = (await h.inMailbox('INBOX')).map((m) => m.id).toSet();
    expect(after, hasLength(before.length));
    expect(after.intersection(before), isEmpty, reason: 'new ids include the new UIDVALIDITY');
    expect(await h.store.messagesWithoutBody(h.accountId, after), hasLength(after.length));
  });

  test('folders deleted on the server take their messages along', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    expect(await h.inMailbox('Projects/2026'), hasLength(1));
    h.server.mailboxes.remove('Projects/2026');
    await h.sync();
    expect(await h.inMailbox('Projects/2026'), isEmpty);
    expect((await h.store.mailboxes(h.accountId)).map((m) => m.id), isNot(contains('Projects/2026')));
  });

  test('loadMore pages older messages below the window', () async {
    h = await Harness.start(
      config: const ImapSyncConfig(primaryWindow: 4, fetchBatch: 3),
      seed: (s) {
        for (var i = 1; i <= 10; i++) {
          s.deliver('INBOX', rawMessage(id: 'm$i@x', subject: 'Message $i', date: 'Mon, 02 Mar 2026 10:${i.toString().padLeft(2, '0')}:00 +0000'));
        }
      },
    );
    await h.sync();
    expect((await h.inMailbox('INBOX')).map((m) => m.subject).toSet(), {for (var i = 7; i <= 10; i++) 'Message $i'});
    var r = await h.provider.loadMore(h.store, pageSize: 4);
    expect((r.loaded, r.hasMore), (4, true));
    r = await h.provider.loadMore(h.store, mailboxId: 'INBOX', pageSize: 4);
    expect((r.loaded, r.hasMore), (2, false));
    expect(await h.inMailbox('INBOX'), hasLength(10));
    // Paged-in messages are tracked like synced ones.
    final inbox = h.server.mailboxes['INBOX']!;
    h.server.remove(inbox, [inbox.entries.first.$2]);
    await h.sync();
    expect((await h.inMailbox('INBOX')).map((m) => m.subject), isNot(contains('Message 1')));
  });

  test('errors: wrong password, invalid settings, unreachable server', () async {
    h = await Harness.start(seed: seedConversation);
    h.tokens.password = 'wrong';
    await expectLater(h.sync(), throwsA(isA<AuthException>()));

    final broken = ImapProvider(
      account: h.account.copyWith(providerConfig: {'imap': 'nope'}),
      tokens: h.tokens,
      sender: h.sender,
    );
    await expectLater(broken.sync(h.store), throwsA(isA<PermanentException>()));
    expect(broken.capabilities.push, isFalse);
    expect(broken.localEffect(h.action(MailAction.archive, ['t']), const []).isNoop, isTrue);

    await h.server.close();
    h.tokens.password = 'secret';
    await expectLater(h.sync(), throwsA(isA<TransientException>()));
  });

  test('a hung server makes sync fail with a transient error', () async {
    h = await Harness.start(
      seed: seedConversation,
      config: const ImapSyncConfig(client: ImapClientConfig(responseTimeout: Duration(milliseconds: 300))),
    );
    h.server.hang.add('LIST');
    final watch = Stopwatch()..start();
    await expectLater(h.sync(), throwsA(isA<TransientException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    h.server.hang.clear();
    await h.sync();
    expect(await h.messages(), hasLength(5), reason: 'recovers on a fresh connection');
  });

  test('servers without SPECIAL-USE: roles from localized names', () async {
    h = await Harness.start(
      capabilities: {...FakeImapServer.genericCapabilities}..removeAll(['SPECIAL-USE', 'LIST-STATUS']),
      seed: (s) {
        s.mailboxes
          ..remove('Sent')
          ..remove('Trash');
        s
          ..addMailbox('Gesendete Objekte')
          ..addMailbox('Papierkorb')
          ..addMailbox('Archiv');
      },
    );
    await h.sync();
    final roles = {for (final m in await h.store.mailboxes(h.accountId)) m.id: m.role};
    expect(roles['Gesendete Objekte'], MailboxRole.sent);
    expect(roles['Papierkorb'], MailboxRole.trash);
    expect(roles['Archiv'], MailboxRole.archive);
    // Attributes a server sends anyway are still used.
    expect(roles['Drafts'], MailboxRole.drafts);
    expect(h.server.commands('STATUS'), isNotEmpty, reason: 'STATUS per folder without LIST-STATUS');
  });

  test('the folder left selected by an operation is not judged by its stale STATUS', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    // Search leaves INBOX selected on the sync connection.
    await h.provider.search(h.store, 'lunch');
    h.server.deliver('INBOX', rawMessage(id: 'late@x', subject: 'Late arrival'));
    final result = await h.sync();
    expect(result.newMessages.map((m) => m.subject), ['Late arrival']);
    expect(h.server.commands('UNSELECT'), isNotEmpty);
  });

  test('unsolicited FETCH responses during a fetch are not stored as messages', () async {
    h = await Harness.start(seed: seedConversation);
    h.server.intercept = (cmd, conn) {
      // Another client's flag change, announced in the middle of our fetch.
      if (cmd.name == 'FETCH' || cmd.name == 'UID FETCH') conn.send(r'* 2 FETCH (UID 999 FLAGS (\Seen))');
      return false;
    };
    await h.sync();
    final all = await h.messages();
    expect(all, hasLength(5));
    expect(all.values.where((m) => m.subject.isEmpty), isEmpty);
    await h.provider.fetchBodies(h.store, all.keys.toList());
    expect(await h.store.messagesWithoutBody(h.accountId, all.keys), isEmpty);
  });
}
