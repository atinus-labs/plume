import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/src/api/gmail_types.dart';
import 'package:plume_gmail/src/mapping/label_mapper.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  List<GmailLabel> labels(List<Map<String, Object?>> json) => [for (final j in json) GmailLabel.fromJson(j)];

  final systemIds = [
    'INBOX', 'SENT', 'DRAFT', 'TRASH', 'SPAM', 'IMPORTANT', 'STARRED', 'UNREAD', 'CHAT', //
    'CATEGORY_PERSONAL', 'CATEGORY_SOCIAL', 'CATEGORY_PROMOTIONS', 'CATEGORY_UPDATES', 'CATEGORY_FORUMS',
  ];

  test('maps system labels onto roles, categories and hidden keywords', () {
    final mapped = GmailLabelMapper.map('a', labels([for (final id in systemIds) gmailLabel(id, id, type: 'system')]));
    final byId = {for (final m in mapped) m.id: m};

    expect(byId['INBOX']!.role, MailboxRole.inbox);
    expect(byId['INBOX']!.name, 'Inbox');
    expect(byId['SENT']!.role, MailboxRole.sent);
    expect(byId['DRAFT']!.role, MailboxRole.drafts);
    expect(byId['TRASH']!.role, MailboxRole.trash);
    expect(byId['SPAM']!.role, MailboxRole.junk);
    expect(byId['IMPORTANT']!.role, MailboxRole.important);
    for (final (id, category, name) in [
      ('CATEGORY_PERSONAL', MailCategory.primary, 'Primary'),
      ('CATEGORY_SOCIAL', MailCategory.social, 'Social'),
      ('CATEGORY_PROMOTIONS', MailCategory.promotions, 'Promotions'),
      ('CATEGORY_UPDATES', MailCategory.updates, 'Updates'),
      ('CATEGORY_FORUMS', MailCategory.forums, 'Forums'),
    ]) {
      expect(byId[id]!.role, MailboxRole.category, reason: id);
      expect(byId[id]!.category, category, reason: id);
      expect(byId[id]!.name, name);
      expect(byId[id]!.hidden, isFalse);
    }
    for (final id in ['UNREAD', 'STARRED', 'CHAT']) {
      expect(byId[id]!.hidden, isTrue, reason: id);
      expect(byId[id]!.role, isNull);
    }
    expect(mapped.every((m) => m.kind == MailboxKind.system), isTrue);
    expect(mapped.every((m) => m.accountId == 'a'), isTrue);
  });

  test('system labels come first in a sensible order, then user labels alphabetically', () {
    final mapped = GmailLabelMapper.map(
      'a',
      labels([
        gmailLabel('Label_9', 'zebra'),
        gmailLabel('TRASH', 'TRASH', type: 'system'),
        gmailLabel('Label_1', 'Work'),
        gmailLabel('SENT', 'SENT', type: 'system'),
        gmailLabel('Label_3', 'Work/Clients'),
        gmailLabel('Label_2', 'apple'),
        gmailLabel('INBOX', 'INBOX', type: 'system'),
        gmailLabel('Label_4', 'Work-Archive'),
        gmailLabel('SPAM', 'SPAM', type: 'system'),
        gmailLabel('DRAFT', 'DRAFT', type: 'system'),
        gmailLabel('CATEGORY_SOCIAL', 'CATEGORY_SOCIAL', type: 'system'),
      ]),
    );
    expect(mapped.map((m) => m.id), [
      'INBOX', 'CATEGORY_SOCIAL', 'SENT', 'DRAFT', 'SPAM', 'TRASH', //
      'Label_2', 'Label_1', 'Label_3', 'Label_4', 'Label_9',
    ]);
    final orders = mapped.map((m) => m.sortOrder).toList();
    expect(orders, orderedEquals([...orders]..sort()));
  });

  test('nested user labels get the parent id and the leaf name', () {
    final mapped = GmailLabelMapper.map(
      'a',
      labels([
        gmailLabel('L1', 'Work'),
        gmailLabel('L2', 'Work/Clients'),
        gmailLabel('L3', 'Work/Clients/Acme'),
        gmailLabel('L4', 'Orphan/Child'),
        gmailLabel('L5', 'Work/Ghost/Deep'),
      ]),
    );
    final byId = {for (final m in mapped) m.id: m};
    expect(byId['L1']!.parentId, isNull);
    expect(byId['L1']!.name, 'Work');
    expect(byId['L2']!.parentId, 'L1');
    expect(byId['L2']!.name, 'Clients');
    expect(byId['L3']!.parentId, 'L2');
    expect(byId['L3']!.name, 'Acme');
    // No "Orphan" label exists: stays top level with its full name.
    expect(byId['L4']!.parentId, isNull);
    expect(byId['L4']!.name, 'Orphan/Child');
    // Nearest existing ancestor is "Work".
    expect(byId['L5']!.parentId, 'L1');
    expect(byId['L5']!.name, 'Ghost/Deep');
    expect(mapped.every((m) => m.kind == MailboxKind.user), isTrue);
  });

  test('carries colours as ARGB, counts, and the hidden visibility', () {
    final mapped = GmailLabelMapper.map('a', [
      GmailLabel.fromJson({
        ...gmailLabel('L1', 'Receipts', color: '#16a766'),
        'threadsTotal': 42,
        'threadsUnread': 3,
        'messagesTotal': 50,
      }),
      GmailLabel.fromJson(gmailLabel('L2', 'Hidden', visibility: 'labelHide')),
      GmailLabel.fromJson({...gmailLabel('INBOX', 'INBOX', type: 'system'), 'threadsTotal': 7, 'threadsUnread': 2}),
      GmailLabel.fromJson(gmailLabel('YELLOW_STAR', 'YELLOW_STAR', type: 'system')),
    ]);
    final byId = {for (final m in mapped) m.id: m};
    expect(byId['L1']!.color, 0xFF16A766);
    expect(byId['L1']!.totalThreads, 42);
    expect(byId['L1']!.unreadThreads, 3);
    expect(byId['L1']!.hidden, isFalse);
    expect(byId['L2']!.hidden, isTrue);
    expect(byId['L2']!.color, isNull);
    expect(byId['INBOX']!.totalThreads, 7);
    expect(byId['INBOX']!.unreadThreads, 2);
    expect(byId['YELLOW_STAR']!.hidden, isTrue, reason: 'unknown system labels are internal');
    expect(GmailLabelMapper.parseLabelColor('#fff'), 0xFFFFFFFF);
    expect(GmailLabelMapper.parseLabelColor('nope'), isNull);
  });

  test('signature is order independent and changes on rename or recolour', () {
    final a = labels([gmailLabel('L1', 'Work'), gmailLabel('L2', 'Home')]);
    final b = labels([gmailLabel('L2', 'Home'), gmailLabel('L1', 'Work')]);
    final renamed = labels([gmailLabel('L1', 'Work!'), gmailLabel('L2', 'Home')]);
    final recoloured = labels([gmailLabel('L1', 'Work', color: '#000000'), gmailLabel('L2', 'Home')]);
    expect(GmailLabelMapper.signature(a), GmailLabelMapper.signature(b));
    expect(GmailLabelMapper.signature(a), isNot(GmailLabelMapper.signature(renamed)));
    expect(GmailLabelMapper.signature(a), isNot(GmailLabelMapper.signature(recoloured)));
  });
}
