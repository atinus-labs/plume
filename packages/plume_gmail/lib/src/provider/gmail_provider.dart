import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart' show MimeMessageBuilder;

import '../api/gmail_api.dart';
import '../api/gmail_client.dart';
import '../api/gmail_types.dart';
import '../imap/imap_doorbell.dart';
import '../mapping/content_extractor.dart';
import '../mapping/label_mapper.dart';
import '../mapping/message_mapper.dart';
import '../util/backoff.dart';
import '../util/gmail_data.dart';
import '../util/json.dart';
import '../util/mutex.dart';

final Logger _log = Logger('plume.gmail');

/// Sync window and paging settings.
final class GmailSyncConfig {
  const GmailSyncConfig({
    this.initialInboxThreads = 150,
    this.initialSentThreads = 50,
    this.initialDraftThreads = 100,
    this.initialAllMailThreads = 300,
    this.searchPageSize = 50,
    this.maxHistoryPages = 40,
    this.maxDiscoveredThreads = 300,
    this.threadsPerWrite = 25,
  });

  final int initialInboxThreads;
  final int initialSentThreads;
  final int initialDraftThreads;
  final int initialAllMailThreads;
  final int searchPageSize;

  /// History longer than this many pages (500 records each) is replaced by
  /// a full resync, which is cheaper at that point.
  final int maxHistoryPages;

  /// Upper bound of previously unknown threads fetched in one incremental
  /// sync because labels were added to them (bulk relabelling elsewhere).
  final int maxDiscoveredThreads;

  /// Threads fetched per store transaction, so lists fill progressively.
  final int threadsPerWrite;
}

/// [MailProvider] for Gmail: REST API for data, IMAP IDLE as the real-time
/// doorbell.
///
/// Sync state lives in the store under `gmail.*` keys: the history id
/// cursor, a signature of the label set, and per-mailbox page tokens for
/// [loadMore].
final class GmailProvider implements MailProvider {
  GmailProvider({
    required this.account,
    required TokenSource tokens,
    http.Client? httpClient,
    GmailClientConfig clientConfig = const GmailClientConfig(),
    this.syncConfig = const GmailSyncConfig(),
    this._imapConfig = const ImapDoorbellConfig(),
    this._imapConnector,
    MimeMessageBuilder? mimeBuilder,
    Sleep? sleep,
  })  : _tokens = tokens,
        _mime = mimeBuilder ?? MimeMessageBuilder(),
        _sleep = sleep ?? defaultSleep {
    _client = GmailClient(tokens: tokens, httpClient: httpClient, config: clientConfig, sleep: sleep);
    api = GmailApi(_client);
  }

  static const kind = 'gmail';

  static const historyKey = 'gmail.historyId';
  static const labelsKey = 'gmail.labelsSignature';
  static const pagesKey = 'gmail.pageTokens';

  /// Page-token value meaning "no older threads".
  static const _pagesEnd = '';
  static const _allMailKey = '*';
  static const allMailQuery = '-in:spam -in:trash';

  @override
  final Account account;
  final GmailSyncConfig syncConfig;
  final TokenSource _tokens;
  final ImapDoorbellConfig _imapConfig;
  final ImapConnector? _imapConnector;
  final MimeMessageBuilder _mime;
  final Sleep _sleep;
  late final GmailClient _client;

  /// The underlying REST client.
  late final GmailApi api;

  final _pagesLock = Mutex();

  String get _accountId => account.id;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        labels: true,
        categories: true,
        serverSearch: true,
        serverDrafts: true,
        push: true,
      );

  // Sync -------------------------------------------------------------------

  @override
  Future<SyncResult> sync(SyncStore store) async {
    final historyId = await store.readState(_accountId, historyKey);
    if (historyId == null || historyId.isEmpty) return _fullSync(store, clear: false);
    try {
      return await _incrementalSync(store, historyId);
    } on SyncCursorExpiredException catch (e) {
      _log.info('Gmail history cursor expired for account $_accountId; full resync (${e.message})');
      return _fullSync(store, clear: true);
    }
  }

  Future<SyncResult> _fullSync(SyncStore store, {required bool clear}) async {
    // The cursor is read first so that nothing that happens during the
    // (long) initial fetch is missed by the next incremental sync.
    final profile = await api.getProfile();
    final labels = await _loadMailboxes();
    await store.transaction(() async {
      if (clear) await store.clearMail(_accountId);
      await store.writeState(_accountId, historyKey, null);
      await store.writeState(_accountId, pagesKey, null);
      await store.replaceMailboxes(_accountId, labels.mailboxes);
      await store.writeState(_accountId, labelsKey, labels.signature);
    });

    final inbox = await _listThreadIds(labelIds: [GmailLabels.inbox], limit: syncConfig.initialInboxThreads);
    // Inbox first, so that it fills before anything else.
    await _fetchThreadsInto(store, inbox.ids);
    final sent = await _listThreadIds(labelIds: [GmailLabels.sent], limit: syncConfig.initialSentThreads);
    final drafts = await _listThreadIds(labelIds: [GmailLabels.draft], limit: syncConfig.initialDraftThreads);
    final all = await _listThreadIds(query: allMailQuery, limit: syncConfig.initialAllMailThreads);
    final rest = {...sent.ids, ...drafts.ids, ...all.ids}..removeAll(inbox.ids);
    await _fetchThreadsInto(store, rest.toList());

    await _pagesLock.run(() => store.transaction(() async {
          await store.writeState(
              _accountId,
              pagesKey,
              jsonEncode({
                GmailLabels.inbox: inbox.next ?? _pagesEnd,
                GmailLabels.sent: sent.next ?? _pagesEnd,
                GmailLabels.draft: drafts.next ?? _pagesEnd,
                _allMailKey: all.next ?? _pagesEnd,
              }));
          await store.writeState(_accountId, historyKey, profile.historyId);
        }));
    _log.info('Gmail initial sync done for account $_accountId: ${inbox.ids.length + rest.length} threads');
    return const SyncResult(fullResync: true);
  }

  Future<SyncResult> _incrementalSync(SyncStore store, String startHistoryId) async {
    final records = <GmailHistoryRecord>[];
    String? pageToken;
    String? latestHistoryId;
    var pages = 0;
    do {
      final page = await api.listHistory(startHistoryId: startHistoryId, pageToken: pageToken);
      records.addAll(page.history);
      latestHistoryId = page.historyId ?? latestHistoryId;
      pageToken = page.nextPageToken;
      if (++pages > syncConfig.maxHistoryPages && pageToken != null) {
        throw const SyncCursorExpiredException('History too long to replay');
      }
    } while (pageToken != null);

    final net = _NetHistory.of(records);
    final candidates = {...net.added.keys, ...net.discoveries.keys};
    final known = candidates.isEmpty ? <String>{} : await store.knownMessageIds(_accountId, candidates);
    final newIds = {for (final id in net.added.keys) if (!known.contains(id)) id};
    final discoveredIds = {
      for (final id in net.discoveries.keys)
        if (!known.contains(id) && !net.added.containsKey(id)) id,
    };

    // Unknown messages in threads we already have are fetched one by one;
    // unknown threads are fetched whole so the conversation has context.
    final threadOf = <String, String>{
      for (final id in newIds) id: net.added[id]!.threadId,
      for (final id in discoveredIds) id: net.discoveries[id]!.threadId,
    };
    final threadIds = threadOf.values.toSet();
    final storedThreads = threadIds.isEmpty
        ? <String>{}
        : (await store.messagesInThreads(_accountId, threadIds)).map((m) => m.threadId).toSet();
    final messageFetch = [
      for (final e in threadOf.entries)
        if (storedThreads.contains(e.value)) e.key,
    ];
    final threadFetch = <String>{};
    for (final id in newIds) {
      final t = threadOf[id]!;
      if (!storedThreads.contains(t)) threadFetch.add(t);
    }
    var discoveredThreads = 0;
    for (final id in discoveredIds) {
      final t = threadOf[id]!;
      if (storedThreads.contains(t) || threadFetch.contains(t)) continue;
      if (discoveredThreads++ >= syncConfig.maxDiscoveredThreads) break;
      threadFetch.add(t);
    }

    final fetched = <Message>[];
    final goneThreads = <String>[];
    final threadResults = await api.getThreads(threadFetch.toList());
    final threadList = threadFetch.toList();
    for (var i = 0; i < threadResults.length; i++) {
      final r = threadResults[i];
      if (r.isOk) {
        fetched.addAll(r.value!.messages.map((m) => GmailMessageMapper.toMessage(_accountId, m)));
      } else if (r.error is NotFoundException) {
        goneThreads.add(threadList[i]);
      } else {
        _throwIfSystemic(r.error!);
      }
    }
    final messageResults = await api.getMessages(messageFetch);
    for (final r in messageResults) {
      if (r.isOk) {
        fetched.add(GmailMessageMapper.toMessage(_accountId, r.value!));
      } else if (r.error is! NotFoundException) {
        _throwIfSystemic(r.error!);
      }
    }
    final fetchedIds = {for (final m in fetched) m.id};

    final deltas = <MessageDelta>[];
    for (final id in {...net.labelsAdded.keys, ...net.labelsRemoved.keys}) {
      if (fetchedIds.contains(id) || net.deleted.contains(id)) continue;
      final add = net.labelsAdded[id] ?? const <String>{};
      final remove = net.labelsRemoved[id] ?? const <String>{};
      if (add.isEmpty && remove.isEmpty) continue;
      deltas.add(MessageDelta(
        id,
        addMailboxes: add.difference(GmailLabels.keywordLabels),
        removeMailboxes: remove.difference(GmailLabels.keywordLabels),
        isRead: add.contains(GmailLabels.unread) ? false : (remove.contains(GmailLabels.unread) ? true : null),
        isFlagged: add.contains(GmailLabels.starred) ? true : (remove.contains(GmailLabels.starred) ? false : null),
      ));
    }

    final mailboxUpdate = await _mailboxRefresh(store, net.touchedLabels, hasChanges: records.isNotEmpty);
    final me = account.email.toLowerCase();
    final newMessages = [
      for (final m in fetched)
        if (newIds.contains(m.id) &&
            m.mailboxIds.contains(GmailLabels.inbox) &&
            !m.isRead &&
            !m.isDraft &&
            !m.mailboxIds.contains(GmailLabels.sent) &&
            m.from?.email.toLowerCase() != me)
          m,
    ];

    await store.transaction(() async {
      if (net.deleted.isNotEmpty) await store.deleteMessages(_accountId, net.deleted.toList());
      if (goneThreads.isNotEmpty) await store.deleteThreads(_accountId, goneThreads);
      if (fetched.isNotEmpty) await store.upsertMessages(_accountId, fetched);
      if (deltas.isNotEmpty) await store.applyDeltas(_accountId, deltas);
      await mailboxUpdate?.call();
      await store.writeState(_accountId, historyKey, latestHistoryId ?? net.maxRecordId ?? startHistoryId);
    });
    if (records.isNotEmpty) {
      _log.fine('Gmail incremental sync for account $_accountId: ${records.length} records, '
          '${fetched.length} fetched, ${net.deleted.length} deleted, ${deltas.length} deltas');
    }
    return SyncResult(newMessages: newMessages);
  }

  /// Checks the label set (history does not report label creation, renames
  /// or colour changes) and refreshes counts of labels touched by history.
  /// Returns the store writes to perform inside the sync transaction.
  Future<Future<void> Function()?> _mailboxRefresh(SyncStore store, Set<String> touched,
      {required bool hasChanges}) async {
    final labels = await api.listLabels();
    final signature = GmailLabelMapper.signature(labels);
    if (signature != await store.readState(_accountId, labelsKey)) {
      final loaded = await _loadMailboxes(listed: labels);
      return () async {
        await store.replaceMailboxes(_accountId, loaded.mailboxes);
        await store.writeState(_accountId, labelsKey, loaded.signature);
      };
    }
    if (!hasChanges) return null;
    final existing = {for (final l in labels) l.id};
    final ids = [
      for (final id in {...touched, GmailLabels.inbox})
        if (existing.contains(id)) id,
    ];
    final results = await api.getLabels(ids);
    final counts = <String, ({int unread, int total})>{};
    for (final r in results) {
      if (r.isOk) {
        final l = r.value!;
        counts[l.id] = (unread: l.threadsUnread ?? 0, total: l.threadsTotal ?? 0);
      } else {
        _throwIfSystemic(r.error!);
      }
    }
    if (counts.isEmpty) return null;
    return () => store.updateMailboxCounts(_accountId, counts);
  }

  /// labels.list plus labels.get for the counts.
  Future<({List<Mailbox> mailboxes, String signature})> _loadMailboxes({List<GmailLabel>? listed}) async {
    final labels = listed ?? await api.listLabels();
    final detailed = await api.getLabels([for (final l in labels) l.id]);
    final merged = <GmailLabel>[];
    for (var i = 0; i < labels.length; i++) {
      final r = detailed[i];
      if (r.isOk) {
        merged.add(r.value!);
      } else {
        _throwIfSystemic(r.error!);
        merged.add(labels[i]);
      }
    }
    return (mailboxes: GmailLabelMapper.map(_accountId, merged), signature: GmailLabelMapper.signature(labels));
  }

  Future<({List<String> ids, String? next})> _listThreadIds({
    List<String> labelIds = const [],
    String? query,
    required int limit,
  }) async {
    final ids = <String>[];
    String? token;
    do {
      final page = await api.listThreads(
        labelIds: labelIds,
        query: query,
        pageToken: token,
        maxResults: (limit - ids.length).clamp(1, 500),
      );
      ids.addAll(page.threads.map((t) => t.id));
      token = page.nextPageToken;
    } while (token != null && ids.length < limit);
    return (ids: ids, next: token);
  }

  /// Fetches thread metadata in batches and writes each batch in its own
  /// transaction. Returns the number of threads stored and those that no
  /// longer exist.
  Future<({int loaded, Set<String> gone})> _fetchThreadsInto(SyncStore store, List<String> threadIds) async {
    var loaded = 0;
    final gone = <String>{};
    final step = syncConfig.threadsPerWrite < 1 ? 25 : syncConfig.threadsPerWrite;
    for (var start = 0; start < threadIds.length; start += step) {
      final chunk = threadIds.sublist(start, start + step > threadIds.length ? threadIds.length : start + step);
      final results = await api.getThreads(chunk);
      final messages = <Message>[];
      final missing = <String>[];
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r.isOk) {
          messages.addAll(r.value!.messages.map((m) => GmailMessageMapper.toMessage(_accountId, m)));
          loaded++;
        } else if (r.error is NotFoundException) {
          missing.add(chunk[i]);
        } else {
          _throwIfSystemic(r.error!);
          _log.warning('Skipping Gmail thread ${chunk[i]}: ${r.error!.message}');
        }
      }
      gone.addAll(missing);
      await store.transaction(() async {
        if (missing.isNotEmpty) await store.deleteThreads(_accountId, missing);
        if (messages.isNotEmpty) await store.upsertMessages(_accountId, messages);
      });
    }
    return (loaded: loaded, gone: gone);
  }

  Future<Set<String>> _storedThreadIds(SyncStore store, List<String> threadIds) async {
    if (threadIds.isEmpty) return {};
    return (await store.messagesInThreads(_accountId, threadIds)).map((m) => m.threadId).toSet();
  }

  // Paging -----------------------------------------------------------------

  @override
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, int pageSize = 50}) async {
    final key = mailboxId ?? _allMailKey;
    var token = (await _readPages(store))[key];
    if (token == _pagesEnd) return const LoadMoreResult(loaded: 0, hasMore: false);
    final spamOrTrash = mailboxId == GmailLabels.spam || mailboxId == GmailLabels.trash;
    var loaded = 0;
    var rounds = 0;
    var tokenReset = false;
    while (true) {
      GmailThreadPage page;
      try {
        page = await api.listThreads(
          labelIds: mailboxId == null ? const [] : [mailboxId],
          query: mailboxId == null ? allMailQuery : null,
          pageToken: token,
          maxResults: pageSize,
          includeSpamTrash: spamOrTrash,
        );
      } on PermanentException {
        // An expired or invalid page token: start over from the newest
        // threads, skipping the ones already stored.
        if (token == null || tokenReset) rethrow;
        tokenReset = true;
        token = null;
        continue;
      }
      final ids = [for (final t in page.threads) t.id];
      final stored = await _storedThreadIds(store, ids);
      final result = await _fetchThreadsInto(store, [for (final id in ids) if (!stored.contains(id)) id]);
      loaded += result.loaded;
      token = page.nextPageToken;
      // Keep paging past already-stored threads so a call makes progress.
      if (token == null || loaded > 0 || ++rounds >= 5) break;
    }
    final next = token;
    await _pagesLock.run(() async {
      final pages = await _readPages(store);
      pages[key] = next ?? _pagesEnd;
      await store.writeState(_accountId, pagesKey, jsonEncode(pages));
    });
    return LoadMoreResult(loaded: loaded, hasMore: next != null);
  }

  Future<Map<String, String>> _readPages(SyncStore store) async {
    final raw = await store.readState(_accountId, pagesKey);
    if (raw == null) return {};
    try {
      final json = asJsonMap(jsonDecode(raw));
      return {
        for (final e in (json ?? const <String, Object?>{}).entries)
          if (e.value is String) e.key: e.value! as String,
      };
    } on FormatException {
      return {};
    }
  }

  // Bodies and attachments -------------------------------------------------

  @override
  Future<void> fetchBodies(SyncStore store, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final results = await api.getMessages(messageIds, format: GmailFormat.full);
    final messages = <Message>[];
    final bodies = <String, MessageBody>{};
    final gone = <String>[];
    MailException? deferred;
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      if (!r.isOk) {
        final error = r.error!;
        if (error is NotFoundException) {
          gone.add(messageIds[i]);
        } else if (error is AuthException) {
          throw error;
        } else {
          deferred ??= error;
        }
        continue;
      }
      final gm = r.value!;
      final payload = gm.payload ?? const GmailMessagePart(mimeType: 'text/plain');
      var content = extractContent(payload);
      if (content.unresolvedBodyParts.isNotEmpty) {
        final resolved = <String, List<int>>{};
        for (final part in content.unresolvedBodyParts) {
          final id = part.handle!;
          resolved[id] = await api.getAttachment(gm.id, id);
        }
        content = extractContent(payload, resolved: resolved);
      }
      messages.add(GmailMessageMapper.toMessage(_accountId, gm, content: content));
      bodies[gm.id] = content.toBody();
    }
    await store.transaction(() async {
      if (gone.isNotEmpty) await store.deleteMessages(_accountId, gone);
      if (messages.isNotEmpty) await store.upsertMessages(_accountId, messages);
      for (final e in bodies.entries) {
        await store.saveBody(_accountId, e.key, e.value);
      }
    });
    if (deferred != null) throw deferred;
  }

  @override
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment) async {
    final handle = attachment.providerId;
    if (handle != null) {
      try {
        return await api.getAttachment(messageId, handle);
      } on MailException catch (e) {
        // Attachment handles are not guaranteed to stay valid; fall back to
        // locating the part again.
        if (e is! NotFoundException && e is! PermanentException) rethrow;
      }
    }
    final gm = await api.getMessage(messageId, format: GmailFormat.full);
    final part = _findPart(gm.payload, attachment.partId);
    if (part == null) throw NotFoundException('Attachment ${attachment.partId} of $messageId not found');
    final data = part.body.data;
    if (data != null) return decodeGmailData(data);
    final id = part.body.attachmentId;
    if (id != null) return api.getAttachment(messageId, id);
    return Uint8List(0);
  }

  static GmailMessagePart? _findPart(GmailMessagePart? part, String partId) {
    if (part == null) return null;
    if (part.partId == partId) return part;
    for (final child in part.parts) {
      final found = _findPart(child, partId);
      if (found != null) return found;
    }
    return null;
  }

  // Operations -------------------------------------------------------------

  @override
  LocalMutation localEffect(MailOperation operation, List<Mailbox> mailboxes) => switch (operation) {
        ActionOperation(:final action) => switch (action) {
            MailAction.archive => const LocalMutation(removeMailboxes: {GmailLabels.inbox}),
            MailAction.moveToInbox => const LocalMutation(addMailboxes: {GmailLabels.inbox}),
            MailAction.trash =>
              const LocalMutation(addMailboxes: {GmailLabels.trash}, removeMailboxes: {GmailLabels.inbox}),
            MailAction.restore => const LocalMutation(removeMailboxes: {GmailLabels.trash}),
            MailAction.deleteForever => const LocalMutation(delete: true),
            MailAction.markSpam =>
              const LocalMutation(addMailboxes: {GmailLabels.spam}, removeMailboxes: {GmailLabels.inbox}),
            MailAction.markNotSpam =>
              const LocalMutation(addMailboxes: {GmailLabels.inbox}, removeMailboxes: {GmailLabels.spam}),
            MailAction.markRead => const LocalMutation(setRead: true),
            MailAction.markUnread => const LocalMutation(setRead: false),
            MailAction.flag => const LocalMutation(setFlagged: true),
            MailAction.unflag => const LocalMutation(setFlagged: false),
          },
        LabelOperation(:final add, :final remove) => LocalMutation(
            addMailboxes: add.difference(GmailLabels.keywordLabels),
            removeMailboxes: remove.difference(GmailLabels.keywordLabels),
            setRead: add.contains(GmailLabels.unread) ? false : (remove.contains(GmailLabels.unread) ? true : null),
            setFlagged:
                add.contains(GmailLabels.starred) ? true : (remove.contains(GmailLabels.starred) ? false : null),
          ),
      };

  /// Gmail message ids never change.
  @override
  List<String> currentMessageIds(List<String> messageIds) => messageIds;

  @override
  Future<void> execute(SyncStore store, MailOperation operation) async {
    final ids = operation.ids;
    if (ids.isEmpty) return;
    final threads = operation.scope == OperationScope.thread;
    switch (operation) {
      case ActionOperation(action: MailAction.trash):
        await (threads ? api.trashThreads(ids) : api.trashMessages(ids));
      case ActionOperation(action: MailAction.restore):
        await (threads ? api.untrashThreads(ids) : api.untrashMessages(ids));
      case ActionOperation(action: MailAction.deleteForever):
        await (threads ? api.deleteThreads(ids) : api.batchDeleteMessages(ids));
      case ActionOperation(:final action):
        final labels = labelChangesFor(action);
        await _modify(threads, ids, labels.add, labels.remove);
      case LabelOperation(:final add, :final remove):
        await _modify(threads, ids, add, remove);
    }
  }

  /// The label changes Gmail applies for label-based actions.
  static ({Set<String> add, Set<String> remove}) labelChangesFor(MailAction action) => switch (action) {
        MailAction.archive => (add: const <String>{}, remove: const {GmailLabels.inbox}),
        MailAction.moveToInbox => (add: const {GmailLabels.inbox}, remove: const <String>{}),
        MailAction.markSpam => (add: const {GmailLabels.spam}, remove: const {GmailLabels.inbox}),
        MailAction.markNotSpam => (add: const {GmailLabels.inbox}, remove: const {GmailLabels.spam}),
        MailAction.markRead => (add: const <String>{}, remove: const {GmailLabels.unread}),
        MailAction.markUnread => (add: const {GmailLabels.unread}, remove: const <String>{}),
        MailAction.flag => (add: const {GmailLabels.starred}, remove: const <String>{}),
        MailAction.unflag => (add: const <String>{}, remove: const {GmailLabels.starred}),
        MailAction.trash => (add: const {GmailLabels.trash}, remove: const {GmailLabels.inbox}),
        MailAction.restore => (add: const <String>{}, remove: const {GmailLabels.trash}),
        MailAction.deleteForever => (add: const <String>{}, remove: const <String>{}),
      };

  Future<void> _modify(bool threads, List<String> ids, Set<String> add, Set<String> remove) async {
    if (add.isEmpty && remove.isEmpty) return;
    if (threads) {
      await api.modifyThreads(ids, add: add, remove: remove);
    } else {
      await api.batchModifyMessages(ids, add: add, remove: remove);
    }
  }

  // Sending and drafts -----------------------------------------------------

  @override
  Future<String> send(OutgoingMessage message) async {
    final built = _mime.build(message);
    try {
      final draftId = message.draftId;
      if (draftId != null) {
        try {
          final sent = await api.sendDraft(draftId, built.bytes, threadId: message.threadId);
          _draftIds.removeWhere((_, id) => id == draftId);
          return sent.id;
        } on NotFoundException {
          _log.info('Draft no longer exists; sending as a new message');
        }
      }
      try {
        return (await api.sendMessage(built.bytes, threadId: message.threadId)).id;
      } on NotFoundException {
        if (message.threadId == null) rethrow;
        // The thread was deleted meanwhile; send it as a new conversation.
        return (await api.sendMessage(built.bytes)).id;
      }
    } on TransientException {
      // The request may have reached Gmail before failing. Look for the
      // message by its Message-ID before letting the outbox retry.
      final sentId = await _findByMessageId(built.messageId);
      if (sentId != null) return sentId;
      rethrow;
    }
  }

  Future<String?> _findByMessageId(String messageId) async {
    try {
      await _sleep(const Duration(seconds: 2)); // Search indexing lag.
      final bare = messageId.replaceAll(RegExp('[<>]'), '');
      final ids = await api.listMessageIds(query: 'rfc822msgid:$bare', maxResults: 1, includeSpamTrash: true);
      return ids.isEmpty ? null : ids.first;
    } on MailException {
      return null;
    }
  }

  @override
  Future<String> saveDraft(OutgoingMessage message) async {
    final built = _mime.build(message);
    final draftId = message.draftId;
    if (draftId != null) {
      try {
        return _remember(await api.updateDraft(draftId, built.bytes, threadId: message.threadId));
      } on NotFoundException {
        _log.info('Draft no longer exists; creating a new one');
      }
    }
    return _remember(await api.createDraft(built.bytes, threadId: message.threadId));
  }

  /// Draft ids by the id of the message holding the draft's current
  /// version. Every update stores the draft as a new message.
  final _draftIds = <String, String>{};

  String _remember(GmailDraft draft) {
    _draftIds.removeWhere((_, id) => id == draft.id);
    final messageId = draft.message?.id;
    if (messageId != null && messageId.isNotEmpty) _draftIds[messageId] = draft.id;
    return draft.id;
  }

  @override
  Future<String?> draftIdOf(String messageId) async {
    final known = _draftIds[messageId];
    if (known != null) return known;
    String? pageToken;
    do {
      final page = await api.listDrafts(pageToken: pageToken, maxResults: 500);
      for (final d in page.drafts) {
        _remember(d);
      }
      if (_draftIds[messageId] case final id?) return id;
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return null;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    try {
      await api.deleteDraft(draftId);
    } on NotFoundException {
      // Already gone.
    }
    _draftIds.removeWhere((_, id) => id == draftId);
  }

  // Search -----------------------------------------------------------------

  @override
  Future<SearchPage> search(SyncStore store, String query, {String? pageToken}) async {
    final page = await api.listThreads(query: query, pageToken: pageToken, maxResults: syncConfig.searchPageSize);
    final ids = [for (final t in page.threads) t.id];
    final stored = await _storedThreadIds(store, ids);
    final result = await _fetchThreadsInto(store, [for (final id in ids) if (!stored.contains(id)) id]);
    return SearchPage(
      threadIds: [for (final id in ids) if (!result.gone.contains(id)) id],
      nextPageToken: page.nextPageToken,
    );
  }

  // Push -------------------------------------------------------------------

  @override
  Stream<void> watchChanges() => GmailImapDoorbell(
        email: account.email,
        tokens: _tokens,
        connect: _imapConnector,
        config: _imapConfig,
      ).watch();

  @override
  Future<void> dispose() async {
    _client.close();
  }

  static void _throwIfSystemic(MailException error) {
    if (error is AuthException || error is TransientException) throw error;
  }
}

/// The net effect of a run of history records.
final class _NetHistory {
  final added = <String, GmailMessage>{};
  final deleted = <String>{};
  final labelsAdded = <String, Set<String>>{};
  final labelsRemoved = <String, Set<String>>{};

  /// Messages that gained a label (or left trash/spam) and may be unknown.
  final discoveries = <String, GmailMessage>{};
  final touchedLabels = <String>{};
  String? maxRecordId;

  static _NetHistory of(List<GmailHistoryRecord> records) {
    final net = _NetHistory();
    for (final record in records) {
      net._noteRecordId(record.id);
      for (final m in record.messagesAdded) {
        net.added[m.id] = m;
        net.deleted.remove(m.id);
        net.touchedLabels.addAll(m.labelIds);
      }
      for (final m in record.messagesDeleted) {
        net.deleted.add(m.id);
        net.added.remove(m.id);
        net.discoveries.remove(m.id);
        net.labelsAdded.remove(m.id);
        net.labelsRemoved.remove(m.id);
        net.touchedLabels.addAll(m.labelIds);
      }
      for (final c in record.labelsAdded) {
        final id = c.message.id;
        if (net.deleted.contains(id)) continue;
        net.labelsAdded.putIfAbsent(id, () => {}).addAll(c.labelIds);
        net.labelsRemoved[id]?.removeAll(c.labelIds);
        net.discoveries[id] = c.message;
        net.touchedLabels
          ..addAll(c.labelIds)
          ..addAll(c.message.labelIds);
      }
      for (final c in record.labelsRemoved) {
        final id = c.message.id;
        if (net.deleted.contains(id)) continue;
        net.labelsRemoved.putIfAbsent(id, () => {}).addAll(c.labelIds);
        net.labelsAdded[id]?.removeAll(c.labelIds);
        if (c.labelIds.contains(GmailLabels.trash) || c.labelIds.contains(GmailLabels.spam)) {
          net.discoveries[id] = c.message;
        }
        net.touchedLabels
          ..addAll(c.labelIds)
          ..addAll(c.message.labelIds);
      }
    }
    return net;
  }

  void _noteRecordId(String id) {
    final current = maxRecordId;
    if (current == null || _compareIds(id, current) > 0) maxRecordId = id;
  }

  static int _compareIds(String a, String b) {
    final x = BigInt.tryParse(a);
    final y = BigInt.tryParse(b);
    if (x == null || y == null) return a.compareTo(b);
    return x.compareTo(y);
  }
}
