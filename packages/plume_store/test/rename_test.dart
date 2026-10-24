import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late DriftMailStore store;

  setUp(() async {
    store = await newStore();
    await store.upsertMessages('a1', [
      msg('1.10@INBOX', thread: 't', subject: 'Budget', minute: 1, read: false, attachments: const [pdf]),
      msg('1.11@INBOX', thread: 't', subject: 'Re: Budget', minute: 2, boxes: {'INBOX', 'Label_work'}),
      msg('other', thread: 'u', minute: 3),
    ]);
    await store.saveBody(
      'a1',
      '1.10@INBOX',
      MessageBody(html: '<p>hello budget</p>', inlineParts: {'logo': Uint8List.fromList([1, 2, 3])}),
    );
  });

  tearDown(() => store.close());

  test('renames keep metadata, membership, bodies, inline parts and search', () async {
    await store.renameMessages('a1', {'1.10@INBOX': '7.200@Archive', 'missing': 'x', 'other': 'other'});
    expect(await store.knownMessageIds('a1', ['1.10@INBOX', '7.200@Archive', 'other']), {'7.200@Archive', 'other'});
    final renamed = (await store.messagesInThreads('a1', ['t'])).firstWhere((m) => m.id == '7.200@Archive');
    expect(renamed.isRead, isFalse);
    expect(renamed.subject, 'Budget');
    expect(renamed.attachments.single.filename, 'report.pdf');
    expect(renamed.mailboxIds, {'INBOX'});
    final body = await store.body('a1', '7.200@Archive');
    expect(body!.html, '<p>hello budget</p>');
    expect(body.inlineParts['logo'], [1, 2, 3]);
    expect(await store.body('a1', '1.10@INBOX'), isNull);
    expect(await store.messagesWithoutBody('a1', ['7.200@Archive']), isEmpty);
    // The full-text entry follows the message.
    final hits = await store.searchLocal('hello');
    expect(hits.single.id, 't');
    final detail = await store.watchThread('a1', 't').first;
    expect(detail!.messages.map((m) => m.id), ['7.200@Archive', '1.11@INBOX']);
    expect(detail.summary.unreadCount, 1);
  });

  test('when the new id already exists the old copy goes, its body moves over', () async {
    await store.upsertMessages('a1', [msg('7.200@Archive', thread: 't', subject: 'Budget', minute: 1, boxes: {'Archive'})]);
    await store.renameMessages('a1', {'1.10@INBOX': '7.200@Archive'});
    final messages = await store.messagesInThreads('a1', ['t']);
    expect(messages.map((m) => m.id), unorderedEquals(['7.200@Archive', '1.11@INBOX']));
    expect(messages.firstWhere((m) => m.id == '7.200@Archive').mailboxIds, {'Archive'});
    expect((await store.body('a1', '7.200@Archive'))!.html, '<p>hello budget</p>');
    expect((await store.searchLocal('hello')).single.id, 't');
    expect((await summary(store, 'a1', 't'))!.messageCount, 2);
  });

  test('successive renames (moved twice) keep the body and referential integrity', () async {
    await store.renameMessages('a1', {'1.10@INBOX': '7.200@Archive'});
    await store.renameMessages('a1', {'7.200@Archive': '3.5@Projects'});
    expect(await store.knownMessageIds('a1', ['1.10@INBOX', '7.200@Archive', '3.5@Projects']), {'3.5@Projects'});
    expect((await store.body('a1', '3.5@Projects'))!.inlineParts['logo'], [1, 2, 3]);
    expect(await store.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect((await summary(store, 'a1', 't'))!.messageCount, 2);
  });
}
