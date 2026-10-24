import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/plume_gmail.dart';
import 'package:test/test.dart';

import 'support/fake_gmail.dart';
import 'support/fake_sync_store.dart';
import 'support/fake_tokens.dart';
import 'support/fixtures.dart';

const acc = 'acc1';

final class Harness {
  Harness({GmailSyncConfig config = const GmailSyncConfig()}) {
    provider = GmailProvider(
      account: testAccount,
      tokens: tokens,
      httpClient: gmail.client,
      clientConfig: const GmailClientConfig(quota: GmailQuota.unlimited, maxRetries: 2),
      syncConfig: config,
      sleep: (_) async {},
    );
  }

  final gmail = FakeGmail();
  final store = FakeSyncStore();
  final tokens = FakeTokenSource();
  late final GmailProvider provider;

  Message? msg(String id) => store.message(acc, id);
  String? state(String key) => store.state['$acc|$key'];
}

/// Inbox threads i1..i6 (newest first), a sent-only thread, a draft, an
/// archived labelled thread, and spam/trash threads.
void seed(FakeGmail g) {
  g
    ..addSystemLabels()
    ..addLabel(gmailLabel('Label_1', 'Work', color: '#16a766'))
    ..addLabel(gmailLabel('Label_2', 'Work/Clients'));
  var date = 1700000100000;
  void add(String id, String thread, List<String> labels, {String subject = 'Hello', String from = 'Ana <ana@example.com>'}) {
    g.addMessage(gmailMessage(id: id, threadId: thread, labels: labels, internalDate: date, subject: subject, from: from));
    date -= 1000;
  }

  add('mi1', 'i1', ['INBOX', 'UNREAD', 'CATEGORY_PERSONAL'], subject: 'Invoice 42');
  add('mi2', 'i2', ['INBOX', 'STARRED']);
  add('mi3', 'i3', ['INBOX', 'UNREAD']);
  add('sent1', 's1', ['SENT'], from: 'Me <me@example.com>');
  add('draft1', 'd1', ['DRAFT']);
  add('mi4', 'i4', ['INBOX']);
  add('mi5', 'i5', ['INBOX'], subject: 'Old invoice');
  add('arch1', 'a1', ['Label_1']);
  add('mi6', 'i6', ['INBOX']);
  add('spam1', 'x1', ['SPAM']);
  add('trash1', 'x2', ['TRASH']);
  // A reply in thread i3, from me.
  add('mi3r', 'i3', ['SENT'], from: 'Me <me@example.com>');
}

void main() {
  group('initial sync', () {
    test('stores mailboxes, a window of threads, page tokens and the cursor', () async {
      final h = Harness(config: const GmailSyncConfig(
        initialInboxThreads: 3,
        initialSentThreads: 1,
        initialDraftThreads: 10,
        initialAllMailThreads: 4,
      ));
      seed(h.gmail);

      final result = await h.provider.sync(h.store);

      expect(result.fullResync, isTrue);
      expect(result.newMessages, isEmpty);
      expect(h.state(GmailProvider.historyKey), '5000');
      expect(h.store.writesOutsideTransaction, isEmpty);
      expect(h.store.clearMailCalls, 0);

      final boxes = h.store.mailboxes[acc]!;
      expect(boxes['INBOX']!.role, MailboxRole.inbox);
      expect(boxes['INBOX']!.totalThreads, 6);
      expect(boxes['INBOX']!.unreadThreads, 2);
      expect(boxes['Label_2']!.parentId, 'Label_1');
      expect(boxes['Label_2']!.name, 'Clients');
      expect(boxes['UNREAD']!.hidden, isTrue);

      // Inbox (3 newest), sent (1), drafts, all mail (4 newest, no spam/trash).
      expect(h.store.msgs(acc).keys.toSet(), {'mi1', 'mi2', 'mi3', 'mi3r', 'sent1', 'draft1'});
      expect(h.msg('mi1')!.isRead, isFalse);
      expect(h.msg('mi1')!.mailboxIds, {'INBOX', 'CATEGORY_PERSONAL'});
      expect(h.msg('mi2')!.isFlagged, isTrue);
      expect(h.msg('draft1')!.isDraft, isTrue);
      expect(h.msg('spam1'), isNull);

      final pages = jsonDecode(h.state(GmailProvider.pagesKey)!) as Map;
      expect(pages['INBOX'], isNotEmpty);
      expect(pages['SENT'], isNotEmpty);
      expect(pages['DRAFT'], '', reason: 'all drafts fetched');
      expect(pages['*'], isNotEmpty);

      // Metadata only, fetched through batches.
      final threadGets = h.gmail.log.where((l) => l.contains('GET threads/') && !l.contains('GET threads?'));
      expect(threadGets, isNotEmpty);
      expect(threadGets.every((l) => l.contains('format=metadata') && l.contains('metadataHeaders=List-Unsubscribe')),
          isTrue);
      expect(h.gmail.batchSizes, isNotEmpty);
      // Profile (the cursor) is read before anything else.
      expect(h.gmail.log.first, 'GET profile');
    });
  });

  group('incremental sync', () {
    late Harness h;
    setUp(() async {
      h = Harness();
      seed(h.gmail);
      await h.provider.sync(h.store);
      h.store.writes.clear();
    });

    test('applies added, deleted and relabelled messages from history', () async {
      final g = h.gmail;
      var date = 1700001000000;
      Map<String, Object?> newMsg(String id, String thread, List<String> labels, {String from = 'Bo <bo@x.org>'}) {
        final m = gmailMessage(id: id, threadId: thread, labels: labels, internalDate: date += 1000, from: from);
        g.addMessage(m);
        return m;
      }

      final reply = newMsg('m9', 'i1', ['INBOX', 'UNREAD']); // known thread
      final fresh = newMsg('m10', 't8', ['INBOX', 'UNREAD', 'CATEGORY_UPDATES']); // new thread
      final mine = newMsg('m11', 'i2', ['SENT', 'INBOX', 'UNREAD'], from: 'Me <ME@example.com>');
      final draft = newMsg('m12', 't9', ['DRAFT']);
      final ephemeral = gmailMessage(id: 'm13', threadId: 'i1', labels: ['DRAFT']);
      final vanished = gmailMessage(id: 'm14', threadId: 't14');
      final snoozed = newMsg('m20', 't20', ['INBOX']); // existed before, unknown locally
      g.addMessage(gmailMessage(id: 'm20a', threadId: 't20', labels: [], internalDate: 1600000000000));
      final mi1 = g.messages['mi1']!;
      final mi2 = g.messages['mi2']!;
      final arch = g.messages['arch1']!;
      g
        ..messages.remove('mi2')
        ..setLabels('mi1', ['INBOX', 'STARRED', 'CATEGORY_PERSONAL'])
        ..setLabels('arch1', ['Label_1', 'Label_2'])
        ..historyId = '6000'
        ..history.addAll([
          historyRecord('5001', added: [reply, fresh, ephemeral, vanished]),
          historyRecord('5002', deleted: [mi2, ephemeral], added: [mine]),
          historyRecord('5003', labelsRemoved: [(mi1, ['UNREAD'])], labelsAdded: [(mi1, ['STARRED'])]),
          historyRecord('5004', labelsAdded: [(arch, ['Label_2']), (snoozed, ['INBOX'])], added: [draft]),
          historyRecord('5005', labelsAdded: [(mi1, ['Label_1'])], labelsRemoved: [(mi1, ['Label_1'])]),
        ]);
      g.log.clear();

      final result = await h.provider.sync(h.store);

      expect(result.fullResync, isFalse);
      expect(result.newMessages.map((m) => m.id).toSet(), {'m9', 'm10'});
      expect(h.state(GmailProvider.historyKey), '6000');
      expect(h.store.writesOutsideTransaction, isEmpty);

      // Added.
      expect(h.msg('m9')!.threadId, 'i1');
      expect(h.msg('m10')!.mailboxIds, {'INBOX', 'CATEGORY_UPDATES'});
      expect(h.msg('m11')!.mailboxIds, contains('SENT'));
      expect(h.msg('m12')!.isDraft, isTrue);
      expect(h.msg('m13'), isNull, reason: 'added and deleted in the same window');
      expect(h.msg('m14'), isNull, reason: 'gone before it could be fetched');
      // Discovered through a label change: fetched with its whole thread.
      expect(h.msg('m20'), isNotNull);
      expect(h.msg('m20a'), isNotNull);
      // Deleted.
      expect(h.msg('mi2'), isNull);
      // Relabelled: UNREAD/STARRED become keywords; net-zero changes ignored.
      expect(h.msg('mi1')!.isRead, isTrue);
      expect(h.msg('mi1')!.isFlagged, isTrue);
      expect(h.msg('mi1')!.mailboxIds, {'INBOX', 'CATEGORY_PERSONAL'});
      expect(h.msg('arch1')!.mailboxIds, {'Label_1', 'Label_2'});

      // Known thread: messages.get; unknown threads: threads.get.
      expect(g.log.any((l) => l.contains('GET messages/m9?format=metadata')), isTrue);
      expect(g.log.any((l) => l.contains('GET threads/t8?format=metadata')), isTrue);
      expect(g.log.any((l) => l.contains('threads/i1?')), isFalse);
      expect(g.log.any((l) => l.contains('m13')), isFalse);

      // Counts refreshed for touched labels.
      expect(h.store.writes, contains('updateMailboxCounts'));
      expect(h.store.mailboxes[acc]!['INBOX']!.unreadThreads, 4, reason: 'i1 (m9), i2 (m11), i3, t8');
    });

    test('no changes: only the cursor moves', () async {
      h.gmail.historyId = '5100';
      final result = await h.provider.sync(h.store);
      expect(result.newMessages, isEmpty);
      expect(h.state(GmailProvider.historyKey), '5100');
      expect(h.store.writes, ['writeState:gmail.historyId']);
    });

    test('follows history pages', () async {
      final g = h.gmail..historyPageSize = 2;
      for (var i = 0; i < 5; i++) {
        g.history.add(historyRecord('${5001 + i}', added: [
          gmailMessage(id: 'p$i', threadId: 'pt$i')..also(g.addMessage),
        ]));
      }
      g.historyId = '5005';
      final result = await h.provider.sync(h.store);
      expect(result.newMessages, hasLength(5));
      expect(g.log.where((l) => l.startsWith('GET history')), hasLength(3));
    });

    test('an expired cursor clears the store and runs a full sync', () async {
      h.gmail
        ..historyExpired = true
        ..historyId = '9000';
      h.store.msgs(acc)['stale'] = Message(
          accountId: acc, id: 'stale', threadId: 'gone', subject: '', date: DateTime.utc(2020));

      final result = await h.provider.sync(h.store);

      expect(result.fullResync, isTrue);
      expect(h.store.clearMailCalls, 1);
      expect(h.msg('stale'), isNull);
      expect(h.msg('mi1'), isNotNull);
      expect(h.state(GmailProvider.historyKey), '9000');
      expect(h.store.writesOutsideTransaction, isEmpty);
    });

    test('label renames and new labels replace the mailbox list', () async {
      h.gmail
        ..addLabel(gmailLabel('Label_1', 'Job', color: '#000000'))
        ..addLabel(gmailLabel('Label_3', 'Travel'));
      await h.provider.sync(h.store);
      final boxes = h.store.mailboxes[acc]!;
      expect(boxes['Label_1']!.name, 'Job');
      expect(boxes['Label_1']!.color, 0xFF000000);
      expect(boxes['Label_3'], isNotNull);
      expect(boxes['Label_2']!.parentId, isNull, reason: '"Work" no longer exists');
    });
  });

  group('paging, bodies, attachments and search', () {
    late Harness h;
    setUp(() async {
      h = Harness(config: const GmailSyncConfig(
        initialInboxThreads: 2,
        initialSentThreads: 1,
        initialDraftThreads: 1,
        initialAllMailThreads: 2,
      ));
      seed(h.gmail);
      await h.provider.sync(h.store);
    });

    test('loadMore pages older inbox threads until exhausted', () async {
      expect(h.msg('mi4'), isNull);
      // i3 is already stored (it came in through the Sent window).
      expect(h.msg('mi3'), isNotNull);
      var r = await h.provider.loadMore(h.store, mailboxId: 'INBOX', pageSize: 2);
      expect(r.loaded, 1);
      expect(r.hasMore, isTrue);
      expect(h.msg('mi4'), isNotNull);
      expect(h.msg('mi5'), isNull);
      r = await h.provider.loadMore(h.store, mailboxId: 'INBOX', pageSize: 2);
      expect(r.loaded, 2);
      expect(r.hasMore, isFalse);
      expect(h.msg('mi6'), isNotNull);
      final calls = h.gmail.log.length;
      r = await h.provider.loadMore(h.store, mailboxId: 'INBOX');
      expect(r.hasMore, isFalse);
      expect(r.loaded, 0);
      expect(h.gmail.log.length, calls, reason: 'exhausted: no request');
    });

    test('loadMore for a label without a token starts from the newest', () async {
      final r = await h.provider.loadMore(h.store, mailboxId: 'Label_1');
      expect(r.loaded, 1);
      expect(r.hasMore, isFalse);
      expect(h.msg('arch1'), isNotNull);
      final all = await h.provider.loadMore(h.store, pageSize: 3);
      expect(all.loaded, greaterThan(0));
      expect(h.gmail.log.any((l) => l.contains('q=-in%3Aspam+-in%3Atrash')), isTrue);
    });

    test('fetchBodies saves bodies and full metadata; missing messages are removed', () async {
      h.gmail.addMessage(gmailMessage(
        id: 'mi1',
        threadId: 'i1',
        subject: 'Invoice 42',
        payload: part('multipart/mixed', parts: [
          part('multipart/alternative', partId: '0', parts: [
            textPart('text/plain', 'Plain body', partId: '0.0'),
            textPart('text/html', '<p>Html body</p>', partId: '0.1'),
          ]),
          part('application/pdf', partId: '1', filename: 'invoice.pdf', attachmentId: 'att-pdf', size: 3),
        ]),
      ));
      h.gmail.attachments['att-pdf'] = [1, 2, 3];
      h.store.msgs(acc)['ghost'] =
          Message(accountId: acc, id: 'ghost', threadId: 'g', subject: '', date: DateTime.utc(2020));

      await h.provider.fetchBodies(h.store, ['mi1', 'ghost']);

      final body = h.store.bodies[acc]!['mi1']!;
      expect(body.html, '<p>Html body</p>');
      expect(body.text, 'Plain body');
      expect(h.msg('mi1')!.attachments.single.filename, 'invoice.pdf');
      expect(h.msg('mi1')!.hasAttachments, isTrue);
      expect(h.msg('ghost'), isNull);
      expect(h.store.writesOutsideTransaction, isEmpty);
      expect(h.gmail.log.any((l) => l.contains('messages/mi1?format=full')), isTrue);

      final bytes = await h.provider.fetchAttachment('mi1', h.msg('mi1')!.attachments.single);
      expect(bytes, [1, 2, 3]);
    });

    test('fetchAttachment finds small inline parts by part id', () async {
      h.gmail.addMessage(gmailMessage(
        id: 'mi2',
        threadId: 'i2',
        payload: part('multipart/mixed', parts: [
          textPart('text/plain', 'x', partId: '0'),
          part('text/csv', partId: '1', filename: 'data.csv', data: b64('a,b\n1,2\n')),
        ]),
      ));
      const info = AttachmentInfo(partId: '1', filename: 'data.csv', mimeType: 'text/csv', size: 8);
      expect(utf8.decode(await h.provider.fetchAttachment('mi2', info)), 'a,b\n1,2\n');
      // A stale attachment id falls back to the part id.
      const stale = AttachmentInfo(partId: '1', providerId: 'expired', filename: 'data.csv', mimeType: 'text/csv', size: 8);
      expect(utf8.decode(await h.provider.fetchAttachment('mi2', stale)), 'a,b\n1,2\n');
    });

    test('search stores unknown threads and returns ids in result order', () async {
      final page = await h.provider.search(h.store, 'invoice');
      expect(page.threadIds, ['i1', 'i5']);
      expect(page.nextPageToken, isNull);
      expect(h.msg('mi5'), isNotNull);
      expect(h.gmail.log.where((l) => l.contains('threads/i1?')), hasLength(1),
          reason: 'i1 was already stored by the initial sync');
    });
  });
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
