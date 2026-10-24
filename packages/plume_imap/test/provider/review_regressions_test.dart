// Regression tests for the issues found in review: local state that
// diverged from the server must be corrected, Gmail operations must find
// mail wherever it is, and nothing may be announced or deleted twice.
import 'dart:async';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/provider/ids.dart';
import 'package:test/test.dart';

import '../support/fake_imap_server.dart';
import '../support/provider_harness.dart';
import 'generic_sync_test.dart' show seedConversation;

const allMail = '[Gmail]/All Mail';
const trash = '[Gmail]/Trash';
const spam = '[Gmail]/Spam';

String hex(BigInt? id) => id!.toRadixString(16);

void main() {
  late Harness h;
  tearDown(() async => h.dispose());

  group('Gmail operations find mail wherever it is (1, 2)', () {
    test('trash of a thread in Spam moves it from Spam to Trash', () async {
      late FakeMessage junk;
      h = await Harness.start(gmail: true, seed: (s) {
        s.deliver(allMail, rawMessage(id: 'a@x', subject: 'In inbox'), labels: {r'\Inbox'});
        junk = s.deliver(spam, rawMessage(id: 'spam@x', subject: 'You won!'));
      });
      await h.sync();
      final m = await h.bySubject('You won!');
      await h.perform(h.action(MailAction.trash, [m.threadId]));
      expect(h.server.mailboxes[spam]!.entries, isEmpty);
      expect(h.server.mailboxes[trash]!.entries.single.$2, junk);
      await h.sync();
      expect((await h.bySubject('You won!')).mailboxIds, {r'\Trash'});
    });

    test('move to inbox from Spam or Trash moves it back out', () async {
      late FakeMessage junk;
      h = await Harness.start(gmail: true, seed: (s) {
        junk = s.deliver(spam, rawMessage(id: 'spam@x', subject: 'Actually fine'));
      });
      await h.sync();
      final m = await h.bySubject('Actually fine');
      await h.perform(h.action(MailAction.moveToInbox, [m.threadId]));
      expect(junk.labels, contains(r'\Inbox'));
      expect((await h.bySubject('Actually fine')).mailboxIds, {'INBOX'});
      await h.sync();
      expect((await h.bySubject('Actually fine')).mailboxIds, {'INBOX'});
    });

    test('Spam hidden from IMAP: flags and trash work, spam is refused clearly, sync copes', () async {
      h = await Harness.start(gmail: true, seed: (s) {
        s.deliver(allMail, rawMessage(id: 'n@x', subject: 'Hello'), labels: {r'\Inbox'});
        s.mailboxes[spam]!.listed = false;
      });
      await h.sync();
      final m = await h.bySubject('Hello');
      await h.perform(h.action(MailAction.markRead, [m.threadId]));
      expect(h.server.allMail.entries.single.$2.flags, contains(r'\Seen'));
      await expectLater(
        h.perform(h.action(MailAction.markSpam, [m.threadId])),
        throwsA(isA<PermanentException>().having((e) => e.message, 'message', contains('Show in IMAP'))),
      );
      // The refused optimistic change is undone by the next sync.
      await h.sync();
      expect((await h.bySubject('Hello')).mailboxIds, {'INBOX'});
      await h.perform(h.action(MailAction.trash, [m.threadId]));
      expect(h.server.mailboxes[trash]!.entries, hasLength(1));
    });

    test('Trash hidden after it was synced: its messages go, the rest stays', () async {
      h = await Harness.start(gmail: true, seed: (s) {
        s.deliver(allMail, rawMessage(id: 'n@x', subject: 'Hello'), labels: {r'\Inbox'});
        s.deliver(trash, rawMessage(id: 't@x', subject: 'Trashed'));
      });
      await h.sync();
      expect(await h.messages(), hasLength(2));
      h.server.mailboxes[trash]!.listed = false;
      await h.sync();
      expect((await h.messages()).values.map((m) => m.subject), ['Hello']);
    });
  });

  group('repair of refused operations', () {
    test('generic: a move the server refuses is undone locally by the next sync', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final lunch = await h.bySubject('Lunch?');
      h.server.intercept = (cmd, conn) {
        if (cmd.name != 'UID MOVE') return false;
        conn.send('${cmd.tag} NO [OVERQUOTA] Archive is full');
        return true;
      };
      await expectLater(h.perform(h.action(MailAction.archive, [lunch.threadId])), throwsA(isA<PermanentException>()));
      expect((await h.bySubject('Lunch?')).mailboxIds, {'Archives'}, reason: 'optimistic');
      h.server.intercept = null;
      await h.sync();
      expect((await h.bySubject('Lunch?')).mailboxIds, {'INBOX'});
    });

    test('Gmail: a label change the server refuses is undone; vanished mail is removed', () async {
      late FakeMessage m;
      h = await Harness.start(gmail: true, seed: (s) {
        s.addMailbox('Work');
        m = s.deliver(allMail, rawMessage(id: 'n@x', subject: 'Hello'), labels: {r'\Inbox'});
      });
      await h.sync();
      h.server.intercept = (cmd, conn) {
        if (cmd.name != 'UID STORE') return false;
        conn.send('${cmd.tag} NO Label change refused');
        return true;
      };
      final op = LabelOperation(accountId: h.accountId, scope: OperationScope.thread, ids: [hex(m.gmailThreadId)], add: {'Work'});
      await expectLater(h.perform(op), throwsA(isA<PermanentException>()));
      expect((await h.bySubject('Hello')).mailboxIds, {'INBOX', 'Work'});
      h.server.intercept = null;
      await h.sync();
      expect((await h.bySubject('Hello')).mailboxIds, {'INBOX'});
    });
  });

  test('Gmail deletions survive a sync pass cut short (3)', () async {
    late FakeMessage gone;
    h = await Harness.start(gmail: true, seed: (s) {
      s.deliver(allMail, rawMessage(id: 'k@x', subject: 'Keep'), labels: {r'\Inbox'});
      gone = s.deliver(allMail, rawMessage(id: 'g@x', subject: 'Deleted elsewhere'), labels: {r'\Inbox'});
    });
    await h.sync();
    h.server.remove(h.server.allMail, [gone]); // deleted for good on the web
    h.server.deliver(spam, rawMessage(id: 'sp2@x', subject: 'More spam'));
    var dropped = false;
    h.server.intercept = (cmd, conn) {
      if (!dropped && cmd.name == 'SELECT' && cmd.text.contains('Spam')) {
        dropped = true;
        unawaited(conn.close());
        return true;
      }
      return false;
    };
    await expectLater(h.sync(), throwsA(isA<TransientException>()));
    h.server.intercept = null;
    await h.sync();
    expect((await h.messages()).values.map((m) => m.subject), unorderedEquals(['Keep', 'More spam']));
  });

  group('login refusals that are not about the password (4)', () {
    for (final (reply, transient) in [
      ('NO [UNAVAILABLE] Temporary System Problem. Try again later.', true),
      ('NO [ALERT] Too many simultaneous connections. (Failure)', true),
      ('NO [LIMIT] Login rate exceeded', true),
      ('NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)', false),
      ('NO [ALERT] Application-specific password required: https://support.google.com (Failure)', false),
      ('NO LOGIN failed.', false),
    ]) {
      test(reply, () async {
        h = await Harness.start(seed: seedConversation);
        h.server.intercept = (cmd, conn) {
          if (cmd.name != 'AUTHENTICATE') return false;
          conn.send('${cmd.tag} $reply');
          return true;
        };
        await expectLater(h.sync(), throwsA(transient ? isA<TransientException>() : isA<AuthException>()));
        final check = await checkImapLogin(h.server.endpoint, 'ana@example.org', 'secret')
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect((check! as ConnectionCheckException).failure,
            transient ? ConnectionFailure.serverBusy : ConnectionFailure.authFailed);
      });
    }
  });

  group('no repeated new-mail notifications (5, 6)', () {
    test('Gmail: restoring from Trash is not new mail', () async {
      h = await Harness.start(gmail: true, seed: (s) {
        s.deliver(allMail, rawMessage(id: 'n@x', subject: 'Unread news'), labels: {r'\Inbox'});
      });
      await h.sync();
      final m = await h.bySubject('Unread news');
      await h.perform(h.action(MailAction.trash, [m.threadId]));
      await h.sync();
      await h.perform(h.action(MailAction.restore, [m.threadId]));
      expect((await h.sync()).newMessages, isEmpty);
      expect((await h.bySubject('Unread news')).mailboxIds, {'INBOX'});
    });

    test('generic: undoing an archive, and a restore by another client, are not new mail', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final lunch = await h.bySubject('Lunch?');
      await h.perform(h.action(MailAction.archive, [lunch.threadId]));
      await h.sync();
      await h.perform(h.action(MailAction.moveToInbox, [lunch.threadId]));
      expect((await h.sync()).newMessages, isEmpty);

      // Another client moves a message out of Trash into INBOX.
      final rich = await h.bySubject('Report');
      await h.perform(h.action(MailAction.trash, [rich.threadId]));
      await h.sync();
      final inTrash = h.server.mailboxes['Trash']!.entries.single.$2;
      h.server.setFlags(inTrash, {});
      h.server
        ..remove(h.server.mailboxes['Trash']!, [inTrash])
        ..deliver('INBOX', inTrash.text);
      final result = await h.sync();
      expect(result.newMessages, isEmpty);
      expect((await h.bySubject('Report')).mailboxIds, {'INBOX'});
    });

    test('mail arriving between SELECT and FETCH is announced once', () async {
      h = await Harness.start(gmail: true, seed: (s) {
        s.deliver(allMail, rawMessage(id: 'a@x', subject: 'First'), labels: {r'\Inbox'}, flags: {r'\Seen'});
      });
      await h.sync();
      h.server.deliver(allMail, rawMessage(id: 'm1@x', subject: 'M1'), labels: {r'\Inbox'});
      var done = false;
      h.server.intercept = (cmd, conn) {
        if (!done && cmd.name == 'UID FETCH' && cmd.text.contains(':*')) {
          done = true;
          h.server.deliver(allMail, rawMessage(id: 'm2@x', subject: 'M2'), labels: {r'\Inbox'});
        }
        return false;
      };
      final first = await h.sync();
      h.server.intercept = null;
      h.server.clearLog();
      final second = await h.sync();
      expect(first.newMessages.map((m) => m.subject), unorderedEquals(['M1', 'M2']));
      expect(second.newMessages, isEmpty);
      expect(h.server.commands('UID FETCH').where((c) => c.contains(':*') && !c.contains('CHANGEDSINCE')), isEmpty,
          reason: 'UIDNEXT moved past the late arrival: it is not fetched again');
      expect(h.server.commands('UID SEARCH').where((c) => c.startsWith('UID SEARCH RETURN (ALL) UID ')), isEmpty,
          reason: 'the late arrival was counted, so no deletion check is needed');
    });

    test('Gmail restore puts back the labels Trash took away', () async {
      late FakeMessage work;
      late FakeMessage mine;
      h = await Harness.start(gmail: true, seed: (s) {
        s.addMailbox('Work');
        work = s.deliver(allMail, rawMessage(id: 'w@x', subject: 'Q3 plan'), labels: {'Work', r'\Important'});
        mine = s.deliver(allMail, rawMessage(id: 'me@x', from: 'ana@example.org', subject: 'Sent by me'),
            labels: {r'\Sent'}, flags: {r'\Seen'});
      });
      await h.sync();
      final thread = hex(work.gmailThreadId);
      await h.perform(h.action(MailAction.trash, [thread]));
      expect(work.labels, isEmpty, reason: 'the fake strips labels in Trash like Gmail');
      await h.perform(h.action(MailAction.restore, [thread]));
      expect(work.labels, {'Work', r'\Important'}, reason: 'archived again, labels restored');
      expect((await h.bySubject('Q3 plan')).mailboxIds, {'Work', r'\Important'});

      // Trashed elsewhere (no record): the user's own mail is archived.
      h.server.gmailMove(mine, allMail, trash);
      await h.sync();
      await h.perform(h.action(MailAction.restore, [hex(mine.gmailThreadId)]));
      expect(mine.labels, isNot(contains(r'\Inbox')));
      await h.sync();
      expect((await h.bySubject('Sent by me')).mailboxIds, isNot(contains('INBOX')));
    });
  });

  test('queued Sent copies: a hung APPEND never fails the sync, and is given up after 5 tries (8)', () async {
    h = await Harness.start(
      seed: seedConversation,
      config: const ImapSyncConfig(client: ImapClientConfig(responseTimeout: Duration(milliseconds: 300))),
    );
    await h.sync();
    h.server.hang.add('APPEND');
    await h.provider.send(const OutgoingMessage(accountId: 'acc', from: Address('ana@example.org'), to: [Address('b@x.org')]));
    for (var i = 0; i < 6; i++) {
      await h.sync();
    }
    expect(h.server.commands('APPEND'), hasLength(5), reason: 'first try at send, then 4 retries');
    h.server.hang.clear();
    await h.sync();
    expect(h.server.commands('APPEND'), hasLength(5), reason: 'dropped');
  });

  test('Gmail label renamed on the web: messages follow (9)', () async {
    late FakeMessage m;
    h = await Harness.start(gmail: true, seed: (s) {
      s.addMailbox('Work');
      m = s.deliver(allMail, rawMessage(id: 'w@x', subject: 'Q3 plan'), labels: {'Work', r'\Inbox'});
    });
    await h.sync();
    expect((await h.bySubject('Q3 plan')).mailboxIds, {'Work', 'INBOX'});
    // Renamed without the message's change counter moving.
    h.server.mailboxes.remove('Work');
    h.server.addMailbox('Projects');
    m.labels = {'Projects', r'\Inbox'};
    await h.sync();
    expect((await h.bySubject('Q3 plan')).mailboxIds, {'Projects', 'INBOX'});
  });

  test('generic delete forever of a thread expunges its Trash copies on the server (10)', () async {
    h = await Harness.start(seed: seedConversation);
    await h.sync();
    final lunch = await h.bySubject('Lunch?');
    // Only the reply goes to Trash; the conversation stays in INBOX.
    final reply = (await h.inMailbox('Sent')).single;
    await h.perform(h.action(MailAction.trash, [reply.id], scope: OperationScope.message));
    expect(h.server.mailboxes['Trash']!.entries, hasLength(1));
    await h.perform(h.action(MailAction.deleteForever, [lunch.threadId]));
    expect(h.server.mailboxes['Trash']!.entries, isEmpty);
    expect(h.server.mailboxes['INBOX']!.entries, hasLength(3));
    await h.sync();
    expect((await h.store.messagesInThreads(h.accountId, [lunch.threadId])), hasLength(2));
  });

  group('message-scoped inverses with ids from before the move (7)', () {
    Future<List<String>> idsIn(String mailbox) async => [for (final m in await h.inMailbox(mailbox)) m.id];

    test('markNotSpam, restore and a folder move, undone with the original ids', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      for (final (forward, folder) in [(MailAction.markSpam, 'Junk'), (MailAction.trash, 'Trash')]) {
        final before = await idsIn('INBOX');
        final op = h.action(forward, before, scope: OperationScope.message);
        await h.perform(op);
        expect(await idsIn(folder), hasLength(before.length));
        // Original ids are gone (re-keyed); the inverse still reaches them.
        expect(await h.store.knownMessageIds(h.accountId, before), isEmpty);
        final inverse = MailEngine.inverseOf(op)!;
        final mutation = h.provider.localEffect(inverse, await h.store.mailboxes(h.accountId));
        expect(mutation.onlyIn, {folder});
        await h.perform(inverse);
        expect(await idsIn('INBOX'), hasLength(before.length));
        expect(await idsIn(folder), isEmpty);
        expect(h.server.mailboxes[folder]!.entries, isEmpty);
      }

      final kickoff = await h.bySubject('Kickoff');
      final move = LabelOperation(
        accountId: h.accountId,
        scope: OperationScope.message,
        ids: [kickoff.id],
        add: {'Projects'},
        remove: {'Projects/2026'},
      );
      await h.perform(move);
      expect(ImapIds.parse((await h.bySubject('Kickoff')).id)!.path, 'Projects');
      final back = MailEngine.inverseOf(move)!;
      expect(h.provider.localEffect(back, await h.store.mailboxes(h.accountId)).onlyIn, {'Projects'});
      await h.perform(back);
      final now = await h.bySubject('Kickoff');
      expect(now.mailboxIds, {'Projects/2026'});
      expect(ImapIds.parse(now.id)!.path, 'Projects/2026');
    });
  });
}
