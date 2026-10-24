import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/src/api/gmail_types.dart';
import 'package:plume_gmail/src/mapping/message_mapper.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('message mapping', () {
    test('maps metadata: keywords are not mailboxes, internalDate wins', () {
      final gm = GmailMessage.fromJson(gmailMessage(
        id: 'm1',
        threadId: 't1',
        labels: ['INBOX', 'UNREAD', 'STARRED', 'IMPORTANT', 'CATEGORY_UPDATES', 'Label_7'],
        subject: '=?UTF-8?Q?R=C3=A9union?= lundi',
        snippet: 'Rendez-vous &agrave; 10h &amp; caf&eacute;',
        internalDate: 1700000000000,
        extraHeaders: [
          header('Cc', '"Ops, Team" <ops@x.org>'),
          header('Reply-To', 'noreply@x.org'),
          header('In-Reply-To', '<parent@x.org>'),
          header('References', '<root@x.org>\r\n <parent@x.org>'),
          header('List-Unsubscribe', '<mailto:u@x.org>, <https://x.org/u>'),
        ],
      ));
      final m = GmailMessageMapper.toMessage('acc', gm);
      expect(m.accountId, 'acc');
      expect(m.id, 'm1');
      expect(m.threadId, 't1');
      expect(m.subject, 'Réunion lundi');
      expect(m.from, const Address('ana@example.com', 'Ana Lima'));
      expect(m.to, [const Address('me@example.com', 'Me')]);
      expect(m.cc, [const Address('ops@x.org', 'Ops, Team')]);
      expect(m.replyTo, [const Address('noreply@x.org')]);
      expect(m.isRead, isFalse);
      expect(m.isFlagged, isTrue);
      expect(m.isDraft, isFalse);
      expect(m.mailboxIds, {'INBOX', 'IMPORTANT', 'CATEGORY_UPDATES', 'Label_7'});
      expect(m.date, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
      expect(m.snippet, 'Rendez-vous à 10h & café');
      expect(m.messageIdHeader, '<m1@mail.example.com>');
      expect(m.inReplyTo, '<parent@x.org>');
      expect(m.references, ['<root@x.org>', '<parent@x.org>']);
      expect(m.listUnsubscribe, '<mailto:u@x.org>, <https://x.org/u>');
      expect(m.size, 1234);
      expect(m.attachments, isEmpty);
    });

    test('drafts and Date header fallback', () {
      final json = gmailMessage(id: 'd1', threadId: 't', labels: ['DRAFT'])..remove('internalDate');
      final m = GmailMessageMapper.toMessage('acc', GmailMessage.fromJson(json));
      expect(m.isDraft, isTrue);
      expect(m.isRead, isTrue);
      expect(m.mailboxIds, {'DRAFT'});
      expect(m.date, DateTime.utc(2023, 11, 14, 22, 13, 20));
    });
  });
}
