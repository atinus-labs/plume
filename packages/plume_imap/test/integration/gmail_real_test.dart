@Tags(['live'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/imap/imap_client.dart';
import 'package:plume_imap/src/imap/uid_set.dart';
import 'package:plume_imap/src/provider/context.dart';
import 'package:plume_store/plume_store.dart' show DriftMailStore;
import 'package:test/test.dart';

import '../support/provider_harness.dart';

String? _loadPassword() {
  final f = File('/tmp/.gmail_pass');
  if (f.existsSync()) {
    final s = f.readAsStringSync().trim();
    if (s.isNotEmpty) return s;
  }
  return Platform.environment['GMAIL_APP_PASSWORD'];
}

Future<Map<String, List<String>>> _readTrashedLabels(DriftMailStore store, String accountId) async {
  final raw = await store.readState(accountId, ImapContext.trashedLabelsKey);
  if (raw == null) return {};
  try {
    return {
      for (final e in (jsonDecode(raw) as Map).cast<String, Object?>().entries)
        if (e.value is List) e.key: (e.value! as List).cast<String>(),
    };
  } on Object {
    return {};
  }
}

void logStep(String msg) {
  print('[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
}

void main() {
  final password = _loadPassword();
  final skipReason = password == null ? 'Set GMAIL_APP_PASSWORD to run against real Gmail' : null;

  const email = 'amanme9285@gmail.com';
  const endpoint = ServerEndpoint(host: 'imap.gmail.com', port: 993, security: ConnectionSecurity.tls);

  group('Real Gmail Trash & Restore', skip: skipReason, () {
    late ImapClient rawClient;
    late DriftMailStore store;
    late ImapProvider provider;
    late Account account;
    final testMsgIdsToCleanup = <String>[];

    setUpAll(() async {
      rawClient = await ImapClient.connect(endpoint);
      await rawClient.login(email, password!);
      try {
        await rawClient.create('PlumeTestLabel');
      } catch (_) {}
    });

    tearDownAll(() async {
      logStep('Starting tearDownAll cleanup...');
      try {
        if (testMsgIdsToCleanup.isNotEmpty) {
          final sel = await rawClient.select('[Gmail]/All Mail');
          if (sel.exists > 0) {
            final uids = await ImapContext.searchGmailIds(rawClient, testMsgIdsToCleanup);
            if (uids.isNotEmpty) {
              await rawClient.move(UidSet.of(uids.values), '[Gmail]/Bin');
              await rawClient.select('[Gmail]/Bin');
              final binUids = await ImapContext.searchGmailIds(rawClient, testMsgIdsToCleanup);
              if (binUids.isNotEmpty) {
                await rawClient.store(UidSet.of(binUids.values), '+FLAGS.SILENT', const [r'\Deleted']);
                await rawClient.expunge(UidSet.of(binUids.values));
              }
            }
          }
        }
      } catch (e) {
        logStep('Cleanup error: $e');
      }
      await rawClient.logout();
      logStep('tearDownAll finished.');
    });

    setUp(() async {
      store = DriftMailStore.inMemory();
      account = Account(
        id: 'real_gmail_test',
        provider: 'imap',
        email: email,
        displayName: 'Test User',
        color: 0xFF336699,
        providerConfig: MailServerSettings(
          imap: endpoint,
          smtp: const ServerEndpoint(host: 'smtp.gmail.com', port: 465, security: ConnectionSecurity.tls),
          username: email,
          saveSentCopy: false,
        ).toJson(),
      );
      await store.saveAccount(account);
      provider = ImapProvider(
        account: account,
        tokens: PasswordTokens(password!),
        sender: FakeSender(),
        config: const ImapSyncConfig(
          gmailAllMailWindow: 20,
          gmailInboxWindow: 20,
          primaryWindow: 20,
          otherWindow: 20,
        ),
      );
    });

    tearDown(() async {
      await provider.dispose();
      await store.close();
    });

    test('Inbox message with custom label: trash saves note, restore recovers label and Inbox', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final subject = 'Plume Inbox Test $now';
      final raw = 'From: <$email>\r\n'
          'To: <$email>\r\n'
          'Subject: $subject\r\n'
          'Date: Mon, 25 Oct 2026 12:00:00 +0000\r\n'
          'Message-ID: <test_inbox_$now@plume.test>\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'Test body for inbox trash and restore';

      logStep('Appending message to INBOX...');
      await rawClient.select('INBOX');
      await rawClient.append('INBOX', Uint8List.fromList(utf8.encode(raw)), flags: [r'\Seen']);

      final searchRes = await rawClient.search(['SUBJECT "$subject"']);
      expect(searchRes.ids.isNotEmpty, isTrue, reason: 'Message should be found in INBOX');
      final inboxUid = searchRes.ids.max;
      logStep('Adding PlumeTestLabel to message uid $inboxUid...');
      await rawClient.store(UidSet.of([inboxUid]), '+X-GM-LABELS', ['PlumeTestLabel']);

      final fetch = await rawClient.fetch('$inboxUid', ['UID', 'X-GM-MSGID', 'X-GM-THRID', 'X-GM-LABELS']);
      final hexMsgId = fetch.messages.single.gmailMessageId!;
      final hexThrId = fetch.messages.single.gmailThreadId!;
      testMsgIdsToCleanup.add(hexMsgId);

      logStep('Created test message: hexMsgId=$hexMsgId, hexThrId=$hexThrId');

      logStep('Running initial provider.sync(store)...');
      await provider.sync(store);
      logStep('Initial sync complete.');

      final inStoreBefore = (await store.messagesInThreads(account.id, [hexThrId])).firstWhere((m) => m.id == hexMsgId);
      logStep('Before trash, store mailboxIds: ${inStoreBefore.mailboxIds}');
      expect(inStoreBefore.mailboxIds, contains('INBOX'));
      expect(inStoreBefore.mailboxIds, contains('PlumeTestLabel'));

      logStep('Performing Trash action...');
      final trashOp = ActionOperation(accountId: account.id, scope: OperationScope.thread, ids: [hexThrId], action: MailAction.trash);
      final trashMut = provider.localEffect(trashOp, await store.mailboxes(account.id));
      await store.applyLocalMutation(account.id, trashOp.scope, trashOp.ids, trashMut);
      await provider.execute(store, trashOp);
      logStep('Trash action execute completed.');

      // Verify: note was saved in store
      final trashedNotes = await _readTrashedLabels(store, account.id);
      logStep('Saved trashedLabels note: $trashedNotes');
      expect(trashedNotes, contains(hexMsgId));
      expect(trashedNotes[hexMsgId], contains('PlumeTestLabel'));
      expect(trashedNotes[hexMsgId], contains(r'\Inbox'));

      // Verify on real Gmail server: message moved to [Gmail]/Bin
      final binSel = await rawClient.select('[Gmail]/Bin');
      expect(binSel.exists > 0, isTrue);
      final binSearch = await rawClient.search(['X-GM-MSGID ${BigInt.parse(hexMsgId, radix: 16)}']);
      expect(binSearch.ids.isNotEmpty, isTrue, reason: 'Message should now be in [Gmail]/Bin on Gmail');
      logStep('Verified message is in [Gmail]/Bin on server.');

      // Restore the thread
      logStep('Performing Restore action...');
      final restoreOp = ActionOperation(accountId: account.id, scope: OperationScope.thread, ids: [hexThrId], action: MailAction.restore);
      final restoreMut = provider.localEffect(restoreOp, await store.mailboxes(account.id));
      await store.applyLocalMutation(account.id, restoreOp.scope, restoreOp.ids, restoreMut);
      await provider.execute(store, restoreOp);
      logStep('Restore action execute completed.');

      // Verify: note in store should be removed
      final trashedNotesAfter = await _readTrashedLabels(store, account.id);
      logStep('Trashed labels note after restore: $trashedNotesAfter');
      expect(trashedNotesAfter.containsKey(hexMsgId), isFalse, reason: 'Note should be consumed on restore');

      // Verify on real Gmail server directly:
      final allSel = await rawClient.select('[Gmail]/All Mail');
      expect(allSel.exists > 0, isTrue);
      final allSearch = await rawClient.search(['X-GM-MSGID ${BigInt.parse(hexMsgId, radix: 16)}']);
      expect(allSearch.ids.isNotEmpty, isTrue, reason: 'Message should be back in All Mail');
      final restoredFetch = await rawClient.fetch('${allSearch.ids.max}', ['UID', 'X-GM-LABELS']);
      final serverLabels = restoredFetch.messages.single.gmailLabels ?? const [];
      logStep('Server labels on real Gmail after restore: $serverLabels');
      expect(serverLabels, contains(r'\Inbox'), reason: 'Inbox label should be restored');
      expect(serverLabels, contains('PlumeTestLabel'), reason: 'Custom label should be restored');

      // Sync again to verify full store convergence
      logStep('Running post-restore provider.sync(store)...');
      await provider.sync(store);
      final inStoreAfter = (await store.messagesInThreads(account.id, [hexThrId])).firstWhere((m) => m.id == hexMsgId);
      logStep('After restore and sync, store mailboxIds: ${inStoreAfter.mailboxIds}');
      expect(inStoreAfter.mailboxIds, contains('INBOX'));
      expect(inStoreAfter.mailboxIds, contains('PlumeTestLabel'));
      expect(inStoreAfter.mailboxIds, isNot(contains(r'\Trash')));
      logStep('Test 1 passed successfully!');
    });

    test('Archived message with custom label: restore removes \\Inbox and restores custom label', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final subject = 'Plume Archived Test $now';
      final raw = 'From: <$email>\r\n'
          'To: <$email>\r\n'
          'Subject: $subject\r\n'
          'Date: Mon, 25 Oct 2026 12:00:00 +0000\r\n'
          'Message-ID: <test_archived_$now@plume.test>\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          'Test body for archived trash and restore';

      logStep('Appending archived message to [Gmail]/All Mail...');
      await rawClient.select('[Gmail]/All Mail');
      await rawClient.append('[Gmail]/All Mail', Uint8List.fromList(utf8.encode(raw)), flags: [r'\Seen']);

      final searchRes = await rawClient.search(['SUBJECT "$subject"']);
      expect(searchRes.ids.isNotEmpty, isTrue);
      final allUid = searchRes.ids.max;
      logStep('Adding PlumeTestLabel to message uid $allUid...');
      await rawClient.store(UidSet.of([allUid]), '+X-GM-LABELS', ['PlumeTestLabel']);

      final fetch = await rawClient.fetch('$allUid', ['UID', 'X-GM-MSGID', 'X-GM-THRID', 'X-GM-LABELS']);
      final hexMsgId = fetch.messages.single.gmailMessageId!;
      final hexThrId = fetch.messages.single.gmailThreadId!;
      final initialLabels = fetch.messages.single.gmailLabels ?? const [];
      testMsgIdsToCleanup.add(hexMsgId);

      logStep('Archived message initial labels on Gmail: $initialLabels');
      expect(initialLabels, isNot(contains(r'\Inbox')));
      expect(initialLabels, contains('PlumeTestLabel'));

      logStep('Running initial provider.sync(store)...');
      await provider.sync(store);
      final inStoreBefore = (await store.messagesInThreads(account.id, [hexThrId])).firstWhere((m) => m.id == hexMsgId);
      logStep('Before trash, archived store mailboxIds: ${inStoreBefore.mailboxIds}');
      expect(inStoreBefore.mailboxIds, isNot(contains('INBOX')));
      expect(inStoreBefore.mailboxIds, contains('PlumeTestLabel'));

      logStep('Trashing archived message...');
      final trashOp = ActionOperation(accountId: account.id, scope: OperationScope.thread, ids: [hexThrId], action: MailAction.trash);
      final trashMut = provider.localEffect(trashOp, await store.mailboxes(account.id));
      await store.applyLocalMutation(account.id, trashOp.scope, trashOp.ids, trashMut);
      await provider.execute(store, trashOp);
      logStep('Trash execute finished.');

      // Verify note saved without \Inbox
      final trashedNotes = await _readTrashedLabels(store, account.id);
      logStep('Saved trashedLabels note for archived: $trashedNotes');
      expect(trashedNotes[hexMsgId], contains('PlumeTestLabel'));
      expect(trashedNotes[hexMsgId], isNot(contains(r'\Inbox')));

      logStep('Restoring archived message...');
      final restoreOp = ActionOperation(accountId: account.id, scope: OperationScope.thread, ids: [hexThrId], action: MailAction.restore);
      final restoreMut = provider.localEffect(restoreOp, await store.mailboxes(account.id));
      await store.applyLocalMutation(account.id, restoreOp.scope, restoreOp.ids, restoreMut);
      await provider.execute(store, restoreOp);
      logStep('Restore execute finished.');

      // Verify on real Gmail server directly:
      await rawClient.select('[Gmail]/All Mail');
      final allSearch2 = await rawClient.search(['X-GM-MSGID ${BigInt.parse(hexMsgId, radix: 16)}']);
      final restoredFetch = await rawClient.fetch('${allSearch2.ids.max}', ['UID', 'X-GM-LABELS']);
      final serverLabels = restoredFetch.messages.single.gmailLabels ?? const [];
      logStep('Server labels on real Gmail after restore of archived message: $serverLabels');
      expect(serverLabels, isNot(contains(r'\Inbox')), reason: 'Inbox label should have been removed because message was archived');
      expect(serverLabels, contains('PlumeTestLabel'), reason: 'Custom label should be restored');

      // Sync again to verify full store convergence
      logStep('Running post-restore provider.sync(store)...');
      await provider.sync(store);
      final inStoreAfter = (await store.messagesInThreads(account.id, [hexThrId])).firstWhere((m) => m.id == hexMsgId);
      logStep('After restore and sync, archived store mailboxIds: ${inStoreAfter.mailboxIds}');
      expect(inStoreAfter.mailboxIds, isNot(contains('INBOX')));
      expect(inStoreAfter.mailboxIds, contains('PlumeTestLabel'));
      expect(inStoreAfter.mailboxIds, isNot(contains(r'\Trash')));
      logStep('Test 2 passed successfully!');
    });
  });
}
