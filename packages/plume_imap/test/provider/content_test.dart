import 'dart:async';
import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/provider/ids.dart';
import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

import '../support/provider_harness.dart';
import 'generic_sync_test.dart' show seedConversation;

void main() {
  late Harness h;

  tearDown(() async => h.dispose());

  group('bodies', () {
    test('small messages are fetched whole, with inline images; attachments by part number', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final rich = await h.bySubject('Report');
      h.server.clearLog();
      await h.provider.fetchBodies(h.store, [rich.id]);
      expect(h.server.commands('EXAMINE'), isNotEmpty, reason: 'read-only on the fetch connection');
      expect(h.server.commands('UID FETCH').where((c) => c.contains('BODY.PEEK[]')), hasLength(1));
      final body = (await h.store.body(h.accountId, rich.id))!;
      expect(body.html, contains('Quarterly numbers — see attached.'));
      expect(body.inlineParts['logo@x'], [137, 80, 78, 71, 1, 2, 3]);

      final pdf = rich.attachments.singleWhere((a) => a.filename == 'q3.pdf');
      final bytes = await h.provider.fetchAttachment(rich.id, pdf);
      expect(bytes, List<int>.generate(3000, (i) => (i * 7) & 0xFF));
      expect(h.server.commands('UID FETCH').last, contains('BODY.PEEK[2]'));
    });

    test('large messages: only text parts are downloaded', () async {
      h = await Harness.start(
        config: const ImapSyncConfig(fullBodyLimit: 10000),
        seed: (s) => s.deliver('INBOX', richMessage(id: 'big@x', subject: 'Huge', pdfBytes: 200000)),
      );
      await h.sync();
      final big = await h.bySubject('Huge');
      h.server.clearLog();
      await h.provider.fetchBodies(h.store, [big.id]);
      final fetches = h.server.commands('UID FETCH');
      expect(fetches.where((c) => c.contains('BODY.PEEK[]')), isEmpty);
      expect(fetches.where((c) => c.contains('BODY.PEEK[1.1]')), hasLength(1));
      final body = (await h.store.body(h.accountId, big.id))!;
      expect(body.html, contains('Quarterly numbers'));
      expect(body.inlineParts, isEmpty, reason: 'fetched on demand instead');
    });

    test('bodies of messages that disappeared remove them; renamed ids still resolve', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final inbox = h.server.mailboxes['INBOX']!;
      final first = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
      final follow = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<follow@example.com>');
      h.server.remove(inbox, [inbox.entries[1].$2]);
      await h.provider.fetchBodies(h.store, [first.id, follow.id]);
      expect(await h.store.knownMessageIds(h.accountId, [first.id, follow.id]), {first.id});
      expect((await h.store.body(h.accountId, first.id))!.text, 'Shall we have lunch on Friday?');

      await h.perform(h.action(MailAction.archive, [first.id], scope: OperationScope.message));
      final moved = (await h.messages()).values.singleWhere((m) => m.messageIdHeader == '<root@example.com>');
      expect(moved.id, isNot(first.id));
      expect((await h.store.body(h.accountId, moved.id))!.text, 'Shall we have lunch on Friday?');
      // A stale id (an open reader) still downloads the attachment-less body.
      await h.store.deleteMessages(h.accountId, []);
      final rich = await h.bySubject('Report');
      final pdf = rich.attachments.singleWhere((a) => a.filename == 'q3.pdf');
      await h.perform(h.action(MailAction.archive, [rich.id], scope: OperationScope.message));
      expect((await h.provider.fetchAttachment(rich.id, pdf)).length, 3000);
      await expectLater(
        h.provider.fetchAttachment('1.999@INBOX', pdf),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('send', () {
    OutgoingMessage reply({String? draftId}) => OutgoingMessage(
          accountId: 'acc',
          from: const Address('ana@example.org', 'Ana'),
          to: const [Address('ben@example.com', 'Ben Okafor')],
          cc: const [Address('carla@example.net')],
          bcc: const [Address('boss@example.org')],
          subject: 'Re: Lunch?',
          textBody: 'See you there.',
          inReplyTo: '<follow@example.com>',
          references: const ['<root@example.com>', '<reply@example.org>', '<follow@example.com>'],
          draftId: draftId,
        );

    test('SMTP without Bcc header, Sent copy with it, same thread after sync', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final id = await h.provider.send(reply());
      final sent = h.sender.sent.single;
      expect(sent.from, 'ana@example.org');
      expect(sent.recipients, ['ben@example.com', 'carla@example.net', 'boss@example.org']);
      expect(sent.password, 'secret');
      final wire = utf8.decode(sent.data);
      expect(wire, isNot(contains('Bcc:')));
      final copy = h.server.mailboxes['Sent']!.entries.last.$2;
      expect(copy.flags, {r'\Seen'});
      expect(copy.text, contains('Bcc: boss@example.org'));
      expect(parseMimeMessage(copy.raw).header('Message-ID'), parseMimeMessage(sent.data).header('Message-ID'));
      expect(ImapIds.parse(id)!.path, 'Sent');

      await h.sync();
      final thread = (await h.bySubject('Lunch?')).threadId;
      final messages = await h.store.messagesInThreads(h.accountId, [thread]);
      expect(messages, hasLength(4), reason: 'the sent reply joins the conversation');
      expect(messages.where((m) => m.id == id), hasLength(1));
    });

    test('a failing Sent copy never fails the send; it is filed at the next sync', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      h.server.intercept = (cmd, conn) {
        if (cmd.name != 'APPEND') return false;
        conn.send('${cmd.tag} NO [OVERQUOTA] Quota exceeded');
        return true;
      };
      final id = await h.provider.send(reply());
      expect(id, startsWith('<'), reason: 'best effort: the Message-ID');
      expect(h.sender.sent, hasLength(1));
      expect(h.server.mailboxes['Sent']!.entries, hasLength(1));

      // Connection trouble: queued and filed by the next sync.
      h.server.intercept = (cmd, conn) {
        if (cmd.name != 'APPEND') return false;
        unawaited(conn.close());
        return true;
      };
      await h.provider.send(reply());
      expect(h.sender.sent, hasLength(2));
      h.server.intercept = null;
      await h.sync();
      expect(h.server.mailboxes['Sent']!.entries, hasLength(2));
    });

    test('SMTP failures propagate (before anything was sent)', () async {
      h = await Harness.start(seed: seedConversation);
      h.sender.failWith = const TransientException('451 try later');
      await expectLater(h.provider.send(reply()), throwsA(isA<TransientException>()));
      expect(h.server.commands('APPEND'), isEmpty);
      await expectLater(
        h.provider.send(const OutgoingMessage(accountId: 'acc', from: Address('ana@example.org'))),
        throwsA(isA<PermanentException>()),
      );
    });

    test('drafts: save, replace, delete after send', () async {
      h = await Harness.start(seed: seedConversation);
      await h.sync();
      final first = await h.provider.saveDraft(reply());
      final drafts = h.server.mailboxes['Drafts']!;
      expect(drafts.entries.single.$2.flags, {r'\Draft', r'\Seen'});
      expect(ImapIds.parse(first)!.path, 'Drafts');
      final second = await h.provider.saveDraft(reply(draftId: first));
      expect(second, isNot(first));
      expect(drafts.entries, hasLength(1), reason: 'the old version is gone');
      await h.sync();
      final draft = (await h.inMailbox('Drafts')).single;
      expect(draft.isDraft, isTrue);
      expect(draft.id, second);
      expect(draft.threadId, (await h.bySubject('Lunch?')).threadId);

      await h.provider.send(reply(draftId: second));
      expect(drafts.entries, isEmpty);
      await h.provider.deleteDraft(second); // already gone: no error
    });
  });

  test('search across folders, paged newest first, stored in the store', () async {
    h = await Harness.start(
      config: const ImapSyncConfig(primaryWindow: 2, otherWindow: 2, searchPageSize: 3),
      seed: (s) {
        s.addMailbox('Projects');
        for (var i = 1; i <= 4; i++) {
          s.deliver('INBOX', rawMessage(id: 'in$i@x', subject: 'Invoice $i', body: 'Your invoice', date: 'Mon, 0$i Mar 2026 10:00:00 +0000'));
        }
        s.deliver('Projects', rawMessage(id: 'p@x', subject: 'Invoice for project', body: 'invoice', date: 'Thu, 05 Mar 2026 10:00:00 +0000'));
        s.deliver('Sent', rawMessage(id: 's@x', from: 'ana@example.org', subject: 'Unrelated', body: 'hello'));
      },
    );
    await h.sync();
    final page1 = await h.provider.search(h.store, 'invoice');
    final subjects1 = [for (final t in page1.threadIds) (await h.store.messagesInThreads(h.accountId, [t])).single.subject];
    expect(subjects1, ['Invoice for project', 'Invoice 4', 'Invoice 3']);
    expect(page1.nextPageToken, isNotNull);
    final page2 = await h.provider.search(h.store, 'invoice', pageToken: page1.nextPageToken);
    final subjects2 = [for (final t in page2.threadIds) (await h.store.messagesInThreads(h.accountId, [t])).single.subject];
    expect(subjects2, ['Invoice 2', 'Invoice 1']);
    expect(page2.nextPageToken, isNull);
    expect((await h.provider.search(h.store, 'Grüße')).threadIds, isEmpty);
    expect(h.server.commands('UID SEARCH').last, contains('CHARSET UTF-8'));
  });
}
