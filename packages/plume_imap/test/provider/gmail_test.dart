import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:test/test.dart';

import '../support/fake_imap_server.dart';
import '../support/provider_harness.dart';

const allMail = '[Gmail]/All Mail';
const trash = '[Gmail]/Trash';
const spam = '[Gmail]/Spam';

late FakeMessage lunch;
late FakeMessage reply;
late FakeMessage social;
late FakeMessage work;
late FakeMessage draft;
late FakeMessage oldInbox;
late FakeMessage trashed;
late FakeMessage junk;

String hex(BigInt? id) => id!.toRadixString(16);

void seedGmail(FakeImapServer s) {
  s
    ..addMailbox('Work')
    ..addMailbox('Work/Q3')
    ..addMailbox('Reçus');
  oldInbox = s.deliver(allMail, rawMessage(id: 'old@x', subject: 'Old but in inbox', date: 'Mon, 05 Jan 2026 10:00:00 +0000'),
      labels: {r'\Inbox'});
  for (var i = 0; i < 4; i++) {
    s.deliver(allMail, rawMessage(id: 'arch$i@x', subject: 'Archived $i', date: 'Mon, 0${i + 1} Feb 2026 10:00:00 +0000'),
        flags: {r'\Seen'});
  }
  lunch = s.deliver(allMail, rawMessage(id: 'root@example.com', subject: 'Lunch?'), labels: {r'\Inbox', r'\Important'});
  reply = s.deliver(
    allMail,
    rawMessage(
      id: 'reply@example.org',
      from: 'Ana <ana@example.org>',
      subject: 'Re: Lunch?',
      inReplyTo: 'root@example.com',
      references: ['root@example.com'],
      date: 'Mon, 02 Mar 2026 11:00:00 +0000',
    ),
    labels: {r'\Sent'},
    flags: {r'\Seen'},
    threadId: lunch.gmailThreadId,
  );
  social = s.deliver(allMail, rawMessage(id: 'social@x', subject: 'You have a new follower', date: 'Mon, 02 Mar 2026 12:00:00 +0000'),
      labels: {r'\Inbox'}, categories: {'social'});
  work = s.deliver(allMail, rawMessage(id: 'work@x', subject: 'Q3 plan', date: 'Mon, 02 Mar 2026 13:00:00 +0000'),
      labels: {'Work/Q3', 'Reçus', r'\Starred'}, flags: {r'\Seen'});
  draft = s.deliver(allMail, rawMessage(id: 'draft@x', from: 'ana@example.org', subject: 'Unfinished', date: 'Mon, 02 Mar 2026 14:00:00 +0000'),
      labels: {r'\Draft'}, flags: {r'\Seen', r'\Draft'});
  trashed = s.deliver(trash, rawMessage(id: 'trash@x', subject: 'Old newsletter'), flags: {r'\Seen'});
  junk = s.deliver(spam, rawMessage(id: 'spam@x', subject: 'You won!'));
}

void main() {
  late Harness h;

  Future<Harness> start({ImapSyncConfig config = const ImapSyncConfig(gmailAllMailWindow: 7)}) =>
      Harness.start(gmail: true, seed: seedGmail, config: config);

  tearDown(() async => h.dispose());

  test('initial sync maps All Mail, Trash and Spam with Gmail ids and labels', () async {
    h = await start();
    expect(h.provider.capabilities.labels, isFalse, reason: 'unknown until connected');
    await h.sync();
    expect(h.provider.capabilities.labels, isTrue);
    expect(h.provider.capabilities.categories, isTrue);

    final boxes = {for (final m in await h.store.mailboxes(h.accountId)) m.id: m};
    expect(boxes['INBOX']!.role, MailboxRole.inbox);
    expect(boxes[r'\Sent']!.role, MailboxRole.sent);
    expect(boxes[r'\Drafts']!.role, MailboxRole.drafts);
    expect(boxes[r'\Trash']!.role, MailboxRole.trash);
    expect(boxes[r'\Junk']!.role, MailboxRole.junk);
    expect(boxes[r'\Important']!.role, MailboxRole.important);
    expect(boxes[r'\All']!.hidden, isTrue);
    expect(boxes['CATEGORY_SOCIAL']!.category, MailCategory.social);
    expect(boxes['CATEGORY_PERSONAL']!.role, MailboxRole.category);
    expect(boxes['Work/Q3']!.parentId, 'Work');
    expect(boxes['Work/Q3']!.name, 'Q3');
    expect(boxes['Reçus']!.kind, MailboxKind.user, reason: 'UTF8=ACCEPT names');
    expect(boxes.keys.where((k) => k.startsWith('[Gmail]')), isEmpty);
    // Only All Mail, Trash and Spam are selected.
    expect(h.server.commands('SELECT').map((c) => c.substring(7)).toSet(), {'"$allMail"', '"$trash"', '"$spam"'});

    final all = await h.messages();
    final m = all[hex(lunch.gmailId)]!;
    expect(m.threadId, hex(lunch.gmailThreadId));
    expect(m.mailboxIds, {'INBOX', r'\Important'});
    expect(all[hex(reply.gmailId)]!.threadId, m.threadId);
    expect(all[hex(reply.gmailId)]!.mailboxIds, {r'\Sent'});
    expect(all[hex(social.gmailId)]!.mailboxIds, {'INBOX', 'CATEGORY_SOCIAL'});
    final w = all[hex(work.gmailId)]!;
    expect(w.mailboxIds, {'Work/Q3', 'Reçus'});
    expect(w.isFlagged, isTrue, reason: r'\Starred');
    expect(all[hex(draft.gmailId)]!.isDraft, isTrue);
    expect(all[hex(draft.gmailId)]!.mailboxIds, {r'\Drafts'});
    expect(all[hex(trashed.gmailId)]!.mailboxIds, {r'\Trash'});
    expect(all[hex(junk.gmailId)]!.mailboxIds, {r'\Junk'});
    expect(all[hex(oldInbox.gmailId)], isNotNull, reason: 'inbox mail older than the All Mail window');
    expect(all.values.where((x) => x.subject.startsWith('Archived')).map((x) => x.subject),
        unorderedEquals(['Archived 2', 'Archived 3']),
        reason: 'the newest 7 of All Mail');

    // Inbox tabs: Primary excludes the social message.
    final primary = await h.store.watchThreads(RoleFilter(MailboxRole.inbox, accountIds: {h.accountId}, category: MailCategory.primary)).first;
    expect(primary.map((t) => t.subject), unorderedEquals(['Lunch?', 'Old but in inbox']));
    final socialTab = await h.store.watchThreads(RoleFilter(MailboxRole.inbox, accountIds: {h.accountId}, category: MailCategory.social)).first;
    expect(socialTab.single.subject, 'You have a new follower');
  });

  test('incremental: label and flag changes, new mail, moves to Trash elsewhere', () async {
    h = await start(config: const ImapSyncConfig(gmailAllMailWindow: 7, flagRefreshInterval: Duration.zero));
    await h.sync();
    await h.provider.fetchBodies(h.store, [hex(work.gmailId)]);
    h.server
      ..setLabels(lunch, {r'\Important'}) // archived on the web
      ..setFlags(social, {r'\Seen'});
    final fresh = h.server.deliver(allMail, rawMessage(id: 'new@x', subject: 'Invoice', date: 'Tue, 03 Mar 2026 09:00:00 +0000'),
        labels: {r'\Inbox'}, categories: {'updates'});
    h.server.gmailMove(work, allMail, trash);
    social.categories = {'promotions'};
    h.server.clearLog();
    final result = await h.sync();
    expect(result.newMessages.map((m) => m.subject), ['Invoice']);
    expect(h.server.commands('UID FETCH').any((c) => c.contains('CHANGEDSINCE')), isTrue);
    final all = await h.messages();
    expect(all[hex(lunch.gmailId)]!.mailboxIds, {r'\Important'});
    expect(all[hex(social.gmailId)]!.isRead, isTrue);
    expect(all[hex(social.gmailId)]!.mailboxIds, {'INBOX', 'CATEGORY_PROMOTIONS'}, reason: 're-categorized');
    expect(all[hex(fresh.gmailId)]!.mailboxIds, {'INBOX', 'CATEGORY_UPDATES'});
    final moved = all[hex(work.gmailId)]!;
    expect(moved.mailboxIds, {r'\Trash'});
    expect(await h.store.body(h.accountId, moved.id), isNotNull, reason: 'same id: a move is not a delete');

    // Deleted for good elsewhere.
    h.server.remove(h.server.mailboxes[trash]!, [work]);
    await h.sync();
    expect((await h.messages())[hex(work.gmailId)], isNull);
  });

  test('operations use labels, and folder moves only for Trash and Spam', () async {
    h = await start();
    await h.sync();
    final thread = hex(lunch.gmailThreadId);

    await h.perform(h.action(MailAction.archive, [thread]));
    expect(h.server.commands('UID STORE').single, contains(r'-X-GM-LABELS (\Inbox)'));
    expect(lunch.labels, isNot(contains(r'\Inbox')));
    expect((await h.messages())[hex(lunch.gmailId)]!.mailboxIds, {r'\Important'});

    await h.perform(h.action(MailAction.moveToInbox, [thread]));
    expect(lunch.labels, contains(r'\Inbox'));

    await h.perform(LabelOperation(accountId: h.accountId, scope: OperationScope.thread, ids: [thread], add: {'Work'}));
    expect(lunch.labels, contains('Work'));
    expect(reply.labels, contains('Work'), reason: 'thread scope: all its messages');
    await h.perform(LabelOperation(accountId: h.accountId, scope: OperationScope.thread, ids: [thread], remove: {'Work', r'\Important'}));
    expect(lunch.labels, {r'\Inbox'});

    await h.perform(h.action(MailAction.markRead, [hex(lunch.gmailId)], scope: OperationScope.message));
    expect(lunch.flags, contains(r'\Seen'));
    expect(reply.flags, contains(r'\Seen'));

    await h.perform(h.action(MailAction.trash, [thread]));
    expect(h.server.mailboxes[trash]!.entries.map((e) => e.$2), containsAll([lunch, reply]));
    expect(h.server.allMail.entries.map((e) => e.$2), isNot(contains(lunch)));
    final inTrash = await h.store.messagesInThreads(h.accountId, [thread]);
    expect(inTrash.every((m) => m.mailboxIds.contains(r'\Trash')), isTrue);
    await h.sync();
    expect((await h.store.messagesInThreads(h.accountId, [thread])).map((m) => m.mailboxIds), everyElement({r'\Trash'}));

    await h.perform(h.action(MailAction.restore, [thread]));
    expect(lunch.labels, contains(r'\Inbox'));
    expect(h.server.mailboxes[trash]!.entries, hasLength(1));
    await h.sync();
    expect((await h.messages())[hex(lunch.gmailId)]!.mailboxIds, contains('INBOX'));

    await h.perform(h.action(MailAction.markSpam, [hex(social.gmailThreadId)]));
    expect(h.server.mailboxes[spam]!.entries.map((e) => e.$2), contains(social));
    await h.perform(h.action(MailAction.markNotSpam, [hex(social.gmailThreadId)]));
    expect(social.labels, contains(r'\Inbox'));

    await h.perform(h.action(MailAction.deleteForever, [hex(trashed.gmailThreadId)]));
    expect(h.server.mailboxes[trash]!.entries, isEmpty);
    expect((await h.messages())[hex(trashed.gmailId)], isNull);

    await expectLater(h.provider.execute(h.store, h.action(MailAction.archive, ['ffff'])), throwsA(isA<NotFoundException>()));
  });

  test('local effects mirror Gmail labels', () async {
    h = await start();
    await h.sync();
    final boxes = await h.store.mailboxes(h.accountId);
    LocalMutation effect(MailAction a) => h.provider.localEffect(h.action(a, ['t']), boxes);
    expect(effect(MailAction.archive).removeMailboxes, {'INBOX'});
    expect(effect(MailAction.archive).onlyIn, isNull);
    expect(effect(MailAction.trash).addMailboxes, {r'\Trash'});
    expect(effect(MailAction.markSpam).addMailboxes, {r'\Junk'});
    expect(effect(MailAction.restore).removeMailboxes, {r'\Trash'});
    final star = h.provider.localEffect(
        LabelOperation(accountId: h.accountId, scope: OperationScope.thread, ids: ['t'], add: {r'\Starred', 'Work'}), boxes);
    expect(star.setFlagged, isTrue);
    expect(star.addMailboxes, {'Work'});
  });

  test('send never appends (Gmail files sent mail); drafts live in [Gmail]/Drafts', () async {
    h = await start();
    await h.sync();
    const message = OutgoingMessage(
      accountId: 'acc',
      from: Address('ana@example.org'),
      to: [Address('ben@example.com')],
      subject: 'Re: Lunch?',
      textBody: 'Sure',
      inReplyTo: '<root@example.com>',
      references: ['<root@example.com>'],
    );
    final draftId = await h.provider.saveDraft(message);
    expect(draftId, matches(RegExp(r'^[0-9a-f]+$')), reason: 'X-GM-MSGID of the draft');
    final stored = h.server.allMail.entries.map((e) => e.$2).singleWhere((m) => hex(m.gmailId) == draftId);
    expect(stored.labels, contains(r'\Draft'));

    h.server.clearLog();
    final sentId = await h.provider.send(const OutgoingMessage(
      accountId: 'acc',
      from: Address('ana@example.org'),
      to: [Address('ben@example.com')],
      textBody: 'Sure',
    ).copyWith(draftId: draftId));
    expect(h.sender.sent, hasLength(1));
    expect(h.server.commands('APPEND'), isEmpty);
    expect(sentId, startsWith('<'));
    expect(h.server.allMail.entries.map((e) => e.$2), isNot(contains(stored)), reason: 'draft deleted');
    expect(h.server.mailboxes[trash]!.entries.map((e) => e.$2), isNot(contains(stored)), reason: 'for good');
  });

  test('search uses Gmail syntax over All Mail; loadMore pages labels and All Mail', () async {
    h = await start(config: const ImapSyncConfig(gmailAllMailWindow: 3, gmailInboxWindow: 1, gmailDraftWindow: 0));
    await h.sync();
    final page = await h.provider.search(h.store, 'in:inbox follower');
    expect(h.server.commands('UID SEARCH').last, contains('X-GM-RAW "in:inbox follower"'));
    expect(page.threadIds, [hex(social.gmailThreadId)]);

    final before = (await h.messages()).length;
    final inbox = await h.provider.loadMore(h.store, mailboxId: 'INBOX', pageSize: 5);
    expect(inbox.loaded, greaterThan(0));
    expect(inbox.hasMore, isFalse);
    final all = await h.provider.loadMore(h.store, pageSize: 50);
    expect(all.hasMore, isFalse);
    expect((await h.messages()).length, greaterThan(before));
    final work = await h.provider.loadMore(h.store, mailboxId: 'Work/Q3');
    expect(work.hasMore, isFalse);
  });

  test("Gmail's refusal of a normal password surfaces as an auth error with its text", () async {
    h = await start();
    h.tokens.password = 'my-google-password';
    final error = await h.sync().then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<AuthException>());
    expect((error! as AuthException).message, contains('Application-specific password required'));
  });

  test('bodies of messages moved on the web are found where they are now', () async {
    h = await start();
    await h.sync();
    h.server.gmailMove(lunch, allMail, trash); // index still says All Mail
    await h.provider.fetchBodies(h.store, [hex(lunch.gmailId)]);
    expect((await h.store.body(h.accountId, hex(lunch.gmailId)))!.text, 'Hi there');
    await h.provider.fetchBodies(h.store, ['ffffffffffff']);
    expect((await h.messages())[hex(lunch.gmailId)], isNotNull);
  });

  test('All Mail hidden from IMAP: folders are synced like any server', () async {
    h = await Harness.start(gmail: true, seed: (s) {
      seedGmail(s);
      s.allMail.listed = false;
    });
    await h.sync();
    expect(h.provider.capabilities.labels, isFalse);
    final boxes = {for (final m in await h.store.mailboxes(h.accountId)) m.id: m};
    expect(boxes['[Gmail]/Sent Mail']!.role, MailboxRole.sent);
    final inbox = await h.inMailbox('INBOX');
    expect(inbox.map((m) => m.subject), containsAll(['Lunch?', 'You have a new follower']));
    expect(inbox.first.id, contains('@INBOX'), reason: 'folder-based ids');
    // Gmail files sent mail itself even so.
    await h.provider.send(const OutgoingMessage(accountId: 'acc', from: Address('ana@example.org'), to: [Address('b@x.org')]));
    expect(h.server.commands('APPEND'), isEmpty);
  });
}
