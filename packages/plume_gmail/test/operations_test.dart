import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/plume_gmail.dart';
import 'package:test/test.dart';

import 'support/fake_gmail.dart';
import 'support/fake_sync_store.dart';
import 'support/fake_tokens.dart';
import 'support/fixtures.dart';

void main() {
  late FakeGmail gmail;
  late GmailProvider provider;
  late List<Duration> sleeps;

  setUp(() {
    sleeps = [];
    gmail = FakeGmail()
      ..addMessage(gmailMessage(id: 'a1', threadId: 'tA', labels: ['INBOX', 'UNREAD']))
      ..addMessage(gmailMessage(id: 'a2', threadId: 'tA', labels: ['INBOX']))
      ..addMessage(gmailMessage(id: 'b1', threadId: 'tB', labels: ['INBOX', 'STARRED']));
    provider = GmailProvider(
      account: testAccount,
      tokens: FakeTokenSource(),
      httpClient: gmail.client,
      clientConfig: const GmailClientConfig(quota: GmailQuota.unlimited, maxRetries: 1),
      sleep: (d) async => sleeps.add(d),
    );
  });

  ActionOperation action(MailAction a, {OperationScope scope = OperationScope.thread, List<String> ids = const ['tA']}) =>
      ActionOperation(accountId: 'acc1', scope: scope, ids: ids, action: a);

  group('localEffect', () {
    test('covers every action', () {
      final expected = <MailAction, LocalMutation>{
        MailAction.archive: const LocalMutation(removeMailboxes: {'INBOX'}),
        MailAction.moveToInbox: const LocalMutation(addMailboxes: {'INBOX'}),
        MailAction.trash: const LocalMutation(addMailboxes: {'TRASH'}, removeMailboxes: {'INBOX'}),
        MailAction.restore: const LocalMutation(removeMailboxes: {'TRASH'}),
        MailAction.deleteForever: const LocalMutation(delete: true),
        MailAction.markSpam: const LocalMutation(addMailboxes: {'SPAM'}, removeMailboxes: {'INBOX'}),
        MailAction.markNotSpam: const LocalMutation(addMailboxes: {'INBOX'}, removeMailboxes: {'SPAM'}),
        MailAction.markRead: const LocalMutation(setRead: true),
        MailAction.markUnread: const LocalMutation(setRead: false),
        MailAction.flag: const LocalMutation(setFlagged: true),
        MailAction.unflag: const LocalMutation(setFlagged: false),
      };
      expect(expected.keys.toSet(), MailAction.values.toSet());
      for (final scope in OperationScope.values) {
        for (final e in expected.entries) {
          final m = provider.localEffect(action(e.key, scope: scope), const []);
          final want = e.value;
          final reason = '${e.key} ($scope)';
          expect(m.addMailboxes, want.addMailboxes, reason: reason);
          expect(m.removeMailboxes, want.removeMailboxes, reason: reason);
          expect(m.setRead, want.setRead, reason: reason);
          expect(m.setFlagged, want.setFlagged, reason: reason);
          expect(m.delete, want.delete, reason: reason);
          expect(m.isNoop, isFalse, reason: reason);
        }
      }
    });

    test('label operations translate UNREAD and STARRED into keywords', () {
      final m = provider.localEffect(
        const LabelOperation(
            accountId: 'acc1', scope: OperationScope.message, ids: ['a1'], add: {'Label_1', 'STARRED'}, remove: {'UNREAD', 'INBOX'}),
        const [],
      );
      expect(m.addMailboxes, {'Label_1'});
      expect(m.removeMailboxes, {'INBOX'});
      expect(m.setRead, isTrue);
      expect(m.setFlagged, isTrue);

      final unread = provider.localEffect(
        const LabelOperation(accountId: 'acc1', scope: OperationScope.thread, ids: ['tA'], add: {'UNREAD'}, remove: {'STARRED'}),
        const [],
      );
      expect(unread.addMailboxes, isEmpty);
      expect(unread.setRead, isFalse);
      expect(unread.setFlagged, isFalse);
    });
  });

  group('execute', () {
    test('thread scope uses threads.modify; message scope uses batchModify', () async {
      await provider.execute(FakeSyncStore(), action(MailAction.archive, ids: ['tA', 'tB']));
      expect(gmail.labelsOf('a1'), ['UNREAD']);
      expect(gmail.labelsOf('b1'), ['STARRED']);
      expect(gmail.bodies['POST threads/tA/modify']!.single, {
        'removeLabelIds': ['INBOX'],
      });
      expect(gmail.batchSizes, [2]);

      await provider.execute(FakeSyncStore(), action(MailAction.markRead, scope: OperationScope.message, ids: ['a1', 'b1']));
      expect(gmail.bodies['POST messages/batchModify']!.single, {
        'ids': ['a1', 'b1'],
        'removeLabelIds': ['UNREAD'],
      });
      expect(gmail.labelsOf('a1'), isEmpty);

      await provider.execute(FakeSyncStore(), const LabelOperation(
          accountId: 'acc1', scope: OperationScope.message, ids: ['a2'], add: {'Label_9'}, remove: {'INBOX'}));
      expect(gmail.labelsOf('a2'), ['Label_9']);
    });

    test('label actions send the right label changes', () async {
      final cases = <MailAction, (List<String>, List<String>)>{
        MailAction.moveToInbox: (['INBOX'], []),
        MailAction.markSpam: (['SPAM'], ['INBOX']),
        MailAction.markNotSpam: (['INBOX'], ['SPAM']),
        MailAction.markUnread: (['UNREAD'], []),
        MailAction.flag: (['STARRED'], []),
        MailAction.unflag: ([], ['STARRED']),
      };
      for (final e in cases.entries) {
        gmail.bodies.clear();
        await provider.execute(FakeSyncStore(), action(e.key, scope: OperationScope.message, ids: ['b1']));
        final body = gmail.bodies['POST messages/batchModify']!.single! as Map;
        expect(body['addLabelIds'] ?? <Object?>[], e.value.$1, reason: '${e.key}');
        expect(body['removeLabelIds'] ?? <Object?>[], e.value.$2, reason: '${e.key}');
      }
    });

    test('trash, restore and delete use their endpoints in both scopes', () async {
      await provider.execute(FakeSyncStore(), action(MailAction.trash));
      expect(gmail.labelsOf('a1'), containsAll(['TRASH']));
      expect(gmail.log, contains('POST threads/tA/trash'));
      await provider.execute(FakeSyncStore(), action(MailAction.restore));
      expect(gmail.log, contains('POST threads/tA/untrash'));
      expect(gmail.labelsOf('a1'), isNot(contains('TRASH')));

      await provider.execute(FakeSyncStore(), action(MailAction.trash, scope: OperationScope.message, ids: ['b1']));
      expect(gmail.log, contains('POST messages/b1/trash'));
      await provider.execute(FakeSyncStore(), action(MailAction.restore, scope: OperationScope.message, ids: ['b1']));
      expect(gmail.log, contains('POST messages/b1/untrash'));

      await provider.execute(FakeSyncStore(), action(MailAction.deleteForever, scope: OperationScope.message, ids: ['b1']));
      expect(gmail.bodies['POST messages/batchDelete']!.single, {
        'ids': ['b1'],
      });
      expect(gmail.messages.containsKey('b1'), isFalse);
      await provider.execute(FakeSyncStore(), action(MailAction.deleteForever));
      expect(gmail.log, contains('DELETE threads/tA'));
      expect(gmail.messages, isEmpty);
    });

    test('objects that no longer exist are ignored; >1000 ids are chunked', () async {
      await provider.execute(FakeSyncStore(), action(MailAction.archive, ids: ['tA', 'missing']));
      expect(gmail.labelsOf('a1'), ['UNREAD']);

      final ids = [for (var i = 0; i < 2500; i++) 'id$i'];
      await provider.execute(FakeSyncStore(), action(MailAction.markRead, scope: OperationScope.message, ids: ids));
      final calls = gmail.bodies['POST messages/batchModify']!.cast<Map<String, Object?>>();
      expect(calls.map((c) => (c['ids']! as List).length), [1000, 1000, 500]);
    });

    test('server failures surface as core exceptions', () async {
      gmail.failures['POST messages/batchModify'] = [500, 500];
      await expectLater(provider.execute(FakeSyncStore(), action(MailAction.flag, scope: OperationScope.message, ids: ['a1'])),
          throwsA(isA<TransientException>()));
    });
  });

  group('send and drafts', () {
    OutgoingMessage outgoing({String? threadId, String? draftId}) => OutgoingMessage(
          accountId: 'acc1',
          from: const Address('me@example.com', 'Me'),
          to: const [Address('ana@example.com', 'Ana')],
          subject: 'Re: Hello',
          textBody: 'Thanks!',
          threadId: threadId,
          inReplyTo: '<a2@mail.example.com>',
          references: const ['<a1@mail.example.com>', '<a2@mail.example.com>'],
          draftId: draftId,
        );

    test('send posts raw MIME with the thread id', () async {
      final id = await provider.send(outgoing(threadId: 'tA'));
      final body = gmail.bodies['POST messages/send']!.single! as Map;
      expect(body['threadId'], 'tA');
      final raw = utf8.decode(base64Url.decode(body['raw']! as String));
      expect(raw, contains('Subject: Re: Hello\r\n'));
      expect(raw, contains('In-Reply-To: <a2@mail.example.com>\r\n'));
      expect(raw, contains('References: <a1@mail.example.com> <a2@mail.example.com>\r\n'));
      expect(gmail.messages[id]!['threadId'], 'tA');
    });

    test('drafts are created, updated, sent and deleted', () async {
      final draftId = await provider.saveDraft(outgoing());
      expect(gmail.drafts, contains(draftId));
      final again = await provider.saveDraft(outgoing(draftId: draftId));
      expect(again, draftId);
      expect(gmail.log, contains('PUT drafts/$draftId'));

      final sentId = await provider.send(outgoing(draftId: draftId, threadId: 'tA'));
      expect(gmail.log, contains('POST drafts/send'));
      expect(gmail.drafts, isEmpty);
      expect(gmail.labelsOf(sentId), ['SENT']);

      await provider.deleteDraft('does-not-exist');
      final other = await provider.saveDraft(outgoing());
      await provider.deleteDraft(other);
      expect(gmail.drafts, isEmpty);
    });

    test('a vanished draft or thread does not block sending', () async {
      final updated = await provider.saveDraft(outgoing(draftId: 'deleted-elsewhere'));
      expect(updated, isNot('deleted-elsewhere'));
      expect(gmail.log, contains('POST drafts'));

      gmail.log.clear();
      await provider.send(outgoing(draftId: 'deleted-elsewhere'));
      expect(gmail.log, ['POST drafts/send', 'POST messages/send']);
    });

    test('an ambiguous send failure checks whether the message went out', () async {
      gmail.failures['POST messages/send'] = [500];
      // The fake applies the failure before storing, so nothing was sent.
      await expectLater(provider.send(outgoing()), throwsA(isA<TransientException>()));
      expect(gmail.log.last, startsWith('GET messages?'));
      expect(gmail.log.last, contains('rfc822msgid'));

      // Sent, but the response was lost: found by Message-ID, not resent.
      gmail.failuresAfterApplying['POST messages/send'] = [502];
      gmail.log.clear();
      final sentId = await provider.send(outgoing());
      expect(gmail.log.where((l) => l == 'POST messages/send'), hasLength(1));
      final raw = gmail.rawMessages[sentId]!;
      final messageId = RegExp(r'Message-ID: <([^>]+)>').firstMatch(raw)!.group(1)!;
      expect(messageId, endsWith('@example.com'));
      expect(gmail.log.last, contains(Uri.encodeQueryComponent('rfc822msgid:$messageId')));
      expect(sleeps, contains(const Duration(seconds: 2)));
    });
  });
}
