import 'dart:convert';
import 'dart:math' as math;

import 'package:plume_core/plume_core.dart';

import '../imap/imap_client.dart';
import '../imap/imap_exception.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import 'context.dart';
import 'folder_state.dart';
import 'folders.dart';
import 'ids.dart';
import 'message_mapping.dart';
import 'session_pool.dart';

/// The result of syncing one folder.
final class _FolderResult {
  _FolderResult({this.newMessages = const []});

  final List<Message> newMessages;
}

/// What the start of a pass found out.
typedef _Prepared = ({FolderLayout layout, bool firstSync, Set<String>? staleLabels});

/// Brings the store up to date with the server. See [FolderState] for the
/// per-folder bookkeeping.
///
/// A pass LISTs the folders (with their STATUS), skips folders whose
/// status is unchanged, and for the others: fetches messages with UIDs
/// from UIDNEXT on, applies flag changes (CONDSTORE/QRESYNC when available,
/// otherwise by comparing flags), and detects deletions (QRESYNC, else by
/// comparing UIDs when the message count shows something went missing). A
/// changed UIDVALIDITY drops the folder's messages and starts over.
///
/// The primary connection's lock is taken per folder, so queued operations
/// can run between folders of a long sync.
final class ImapSyncer {
  ImapSyncer(this.ctx);

  final ImapContext ctx;

  static const _identityKey = 'imap.identity';
  static const _layoutKey = 'imap.layout';
  static const _foldersKey = 'imap.folders';
  static const _categoriesKey = 'imap.gmail.categories';
  static const _labelsKey = 'imap.gmail.labels';

  String get _accountId => ctx.accountId;
  ImapSyncConfig get _config => ctx.config;

  Future<SyncResult> sync(SyncStore store) async {
    await ctx.loadRenames(store);
    final prepared = await ctx.pool.run(ImapSlot.primary, (c) => _prepare(c, store));
    final layout = prepared.layout;
    final newMessages = <Message>[];
    var complete = true;
    for (final folder in layout.synced) {
      try {
        final r = await ctx.pool.run(
            ImapSlot.primary, (c) => _syncFolder(c, store, folder, layout, staleLabels: prepared.staleLabels));
        newMessages.addAll(r.newMessages);
      } on ImapCommandException catch (e) {
        // A folder that cannot be selected right now (deleted meanwhile,
        // or a server-side problem) must not block the others.
        complete = false;
        imapLog.warning('Skipping folder sync: ${e.command} ${e.status} ${e.code ?? ''}');
      }
    }
    // Both steps compare against every synced folder, so they only run
    // after a pass that saw all of them.
    if (complete) {
      if (layout.gmail) await _deleteVanishedGmail(store, layout);
      await ctx.pool.run(ImapSlot.primary, (c) => _repair(c, store, layout));
    }
    return SyncResult(newMessages: newMessages, fullResync: prepared.firstSync);
  }

  /// LIST, account identity check, removed folders, mailbox rows.
  Future<_Prepared> _prepare(ImapClient c, SyncStore store) async {
    final layout = await ctx.refreshLayout(c);
    final identity = '${layout.gmail ? 'gmail' : 'imap'}|${ctx.settings.imap.host.toLowerCase()}|'
        '${ctx.settings.username.toLowerCase()}';
    final stored = await store.readState(_accountId, _identityKey);
    var first = stored == null;
    if (stored != null && stored != identity) {
      // Another server or mode (Gmail extensions appeared/disappeared):
      // ids would not match any more. clearMail also wipes sync state.
      imapLog.info('IMAP account $_accountId changed server or mode; resyncing from scratch');
      await store.clearMail(_accountId);
      first = true;
    }
    if (first) await store.writeState(_accountId, _identityKey, identity);
    await _dropRemovedFolders(store, layout);
    final signature = layout.signature;
    if (signature != await store.readState(_accountId, _layoutKey)) {
      await store.transaction(() async {
        await store.replaceMailboxes(_accountId, layout.mailboxes);
        await store.writeState(_accountId, _layoutKey, signature);
      });
    } else {
      await store.updateMailboxCounts(_accountId, layout.counts);
    }
    if (layout.gmail) await ctx.loadGmailIndex(store);
    return (layout: layout, firstSync: first, staleLabels: layout.gmail ? await _labelSetChange(store, layout) : null);
  }

  /// Gmail: when labels were added, removed or renamed (on the web), the
  /// change counter of the affected messages need not move, so their
  /// labels are read again. Returns the label ids that existed before
  /// (to take off messages), or null when nothing changed.
  Future<Set<String>?> _labelSetChange(SyncStore store, FolderLayout layout) async {
    final labels = [for (final m in layout.mailboxes) if (m.kind == MailboxKind.user) m.id]..sort();
    final encoded = jsonEncode(labels);
    final raw = await store.readState(_accountId, _labelsKey);
    if (raw == encoded) return null;
    await store.writeState(_accountId, _labelsKey, encoded);
    if (raw == null) return null; // First pass: nothing to correct.
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } on Object {
      return const {};
    }
  }

  /// Folders that disappeared on the server (deleted or renamed) take
  /// their messages with them.
  Future<void> _dropRemovedFolders(SyncStore store, FolderLayout layout) async {
    final current = [for (final f in layout.synced) f.path];
    final raw = await store.readState(_accountId, _foldersKey);
    final previous = raw == null ? const <String>[] : (jsonDecode(raw) as List).cast<String>();
    for (final path in previous) {
      if (current.contains(path)) continue;
      final st = await ctx.readFolder(store, path);
      await store.transaction(() async {
        if (st != null && layout.gmail) {
          // Trash or Spam hidden from IMAP: their messages go unless All
          // Mail has them.
          await ctx.addIds(store, ImapContext.pendingDeletesKey, st.gmailIds.values);
        } else if (st != null) {
          final ids = ctx.idsOf(path, st, st.known);
          imapLog.info('Folder removed on the server; dropping ${ids.length} messages');
          await store.deleteMessages(_accountId, ids);
        }
        await store.writeState(_accountId, FolderState.keyFor(path), null);
      });
    }
    if (!_sameList(previous, current)) await store.writeState(_accountId, _foldersKey, jsonEncode(current));
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _windowFor(ImapFolder f, FolderLayout layout) {
    if (f.gmailAll) return _config.gmailAllMailWindow;
    return switch (f.role) {
      MailboxRole.inbox || MailboxRole.sent || MailboxRole.drafts || MailboxRole.archive => _config.primaryWindow,
      _ => _config.otherWindow,
    };
  }

  Future<_FolderResult> _syncFolder(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout, {
    Set<String>? staleLabels,
  }) async {
    final st = await ctx.readFolder(store, folder.path);
    final relabel = staleLabels != null && folder.gmailAll;
    final s = folder.status;
    final now = DateTime.now();
    final checked = st?.flagsCheckedAt;
    final flagsDue = folder.isInbox || checked == null || now.difference(checked) >= _config.flagRefreshInterval;
    if (st != null &&
        !relabel &&
        s != null &&
        s.uidValidity == st.uidValidity &&
        s.uidNext == st.uidNext &&
        s.messages == st.messages &&
        (s.unseen == null || s.unseen == st.unseenCount) &&
        (s.highestModSeq != null && c.condstoreEnabled ? s.highestModSeq == st.highestModSeq : !flagsDue)) {
      return _FolderResult();
    }

    final qresync = st != null && c.qresyncEnabled && (st.highestModSeq ?? 0) > 0
        ? (uidValidity: st.uidValidity, modseq: st.highestModSeq!, knownUids: st.known)
        : null;
    final sel = await c.select(folder.path, qresync: qresync);
    // Snapshot: later untagged EXISTS responses update `sel` in place.
    final exists = sel.exists;
    final uidValidity = sel.uidValidity ?? 0;
    final uidNext = sel.uidNext;
    final modseq = sel.noModSeq ? null : sel.highestModSeq;

    if (st == null || st.uidValidity != uidValidity) {
      if (st != null) {
        final ids = ctx.idsOf(folder.path, st, st.known);
        imapLog.info('UIDVALIDITY of a folder changed; replacing its ${ids.length} messages');
        if (layout.gmail) {
          await ctx.addIds(store, ImapContext.pendingDeletesKey, ids);
        } else {
          await store.deleteMessages(_accountId, ids);
        }
      }
      await _initial(c, store, folder, layout,
          exists: exists, uidValidity: uidValidity, uidNext: uidNext, modseq: modseq, unseenCount: s?.unseen);
      return _FolderResult();
    }
    return _incremental(c, store, folder, layout, st, sel,
        exists: exists,
        uidNext: uidNext,
        modseq: modseq,
        flagsDue: flagsDue,
        unseenCount: s?.unseen,
        qresyncUsed: qresync != null,
        staleLabels: relabel ? staleLabels : null);
  }

  // Initial window ------------------------------------------------------------

  Future<void> _initial(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout, {
    required int exists,
    required int uidValidity,
    required int? uidNext,
    required int? modseq,
    required int? unseenCount,
  }) async {
    final st = FolderState(
      uidValidity: uidValidity,
      uidNext: uidNext ?? 1,
      highestModSeq: modseq,
      messages: exists,
      unseenCount: unseenCount,
    );
    final window = _windowFor(folder, layout);
    final gmail = layout.gmail;
    if (exists > 0) {
      final from = math.max(1, exists - window + 1);
      // Newest first, in batches, so the list fills from the top.
      for (var end = exists; end >= from; end -= _config.fetchBatch) {
        final start = math.max(from, end - _config.fetchBatch + 1);
        final r = await c.fetch('$start:$end', headerItems(gmail: gmail), byUid: false);
        await _storeFetched(c, store, folder, layout, st, r.messages);
      }
      if (folder.gmailAll) {
        // Inbox and drafts matter more than recency: older inbox mail is
        // still in the inbox view.
        for (final (query, limit) in [('in:inbox', _config.gmailInboxWindow), ('in:drafts', _config.gmailDraftWindow)]) {
          final hits = await c.search(['X-GM-RAW ', ...c.searchString(query)]);
          final extra = hits.ids.difference(st.known).newest(limit);
          await _fetchByUid(c, store, folder, layout, st, extra);
        }
      }
    }
    final known = st.known;
    st
      ..uidNext = uidNext ?? (known.isEmpty ? 1 : known.max + 1)
      ..floor = known.isEmpty ? st.uidNext : _contiguousFloor(known, window)
      ..flagsCheckedAt = DateTime.now();
    await ctx.writeFolder(store, folder.path, st);
    if (folder.gmailAll) await _writeCategories(store, await _categorySets(c, st.known));
  }

  /// Bottom of the newest-messages window (Gmail extras below it do not
  /// count, so paging continues right under the window).
  static int _contiguousFloor(UidSet known, int window) {
    final top = known.newest(window);
    return top.isEmpty ? known.min : top.min;
  }

  Future<List<Message>> _fetchByUid(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout,
    FolderState st,
    UidSet uids,
  ) async {
    final out = <Message>[];
    final values = uids.values.toList().reversed.toList(); // newest first
    for (var i = 0; i < values.length; i += _config.fetchBatch) {
      final chunk = UidSet.of(values.sublist(i, math.min(values.length, i + _config.fetchBatch)));
      final r = await c.fetch(chunk.toString(), headerItems(gmail: layout.gmail));
      out.addAll(await _storeFetched(c, store, folder, layout, st, r.messages));
    }
    return out;
  }

  /// Fetches previews (and Gmail categories), maps and stores [fetched].
  Future<List<Message>> _storeFetched(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout,
    FolderState st,
    List<ImapFetch> fetched, {
    Set<String>? seenBefore,
  }) async {
    // Servers may slip unsolicited FETCH responses (another client's flag
    // change) between the ones requested; those carry no ENVELOPE.
    final usable = [for (final f in fetched) if (f.uid != null && f.envelope != null) f];
    if (usable.isEmpty) return const [];
    final previews = await fetchPreviews(c, usable);
    final categories = folder.gmailAll
        ? await _categoriesOf(c, UidSet.of([for (final f in usable) f.uid!]))
        : const <int, Set<String>>{};
    final messages = <Message>[];
    final noted = <({int uid, bool seen, bool flagged, String? gmailId})>[];
    for (final f in usable) {
      final id = messageIdOf(f, folder, st.uidValidity, gmail: layout.gmail);
      if (id == null) continue;
      final m = buildMessage(f, folder, layout, id: id, snippet: previews[f.uid!] ?? '', categories: categories[f.uid!]);
      messages.add(m);
      noted.add((uid: f.uid!, seen: m.isRead, flagged: m.isFlagged, gmailId: layout.gmail ? id : null));
    }
    if (seenBefore != null) await _noteSeenBefore(store, messages, seenBefore, gmail: layout.gmail);
    await store.upsertMessages(_accountId, messages);
    st.noteAll(noted);
    return messages;
  }

  /// Adds to [seen] those of [messages] that are not new mail although
  /// their UID is: already stored under the same id (Gmail ids survive
  /// moves; generic moves made here re-keyed the row), or, on generic
  /// servers, stored with the same Message-ID in another folder (moved by
  /// another client: restored, marked not spam).
  Future<void> _noteSeenBefore(SyncStore store, List<Message> messages, Set<String> seen, {required bool gmail}) async {
    if (messages.isEmpty) return;
    seen.addAll(await store.knownMessageIds(_accountId, messages.map((m) => m.id)));
    if (gmail) return;
    final candidates = [for (final m in messages) if (!seen.contains(m.id) && m.messageIdHeader != null) m];
    if (candidates.isEmpty) return;
    final stored = await store.messagesInThreads(_accountId, {for (final m in candidates) m.threadId});
    final headers = {for (final m in stored) ?m.messageIdHeader};
    seen.addAll([for (final m in candidates) if (headers.contains(m.messageIdHeader)) m.id]);
  }

  /// A [Message] for a fetched message of [folder].
  Message buildMessage(
    ImapFetch f,
    ImapFolder folder,
    FolderLayout layout, {
    required String id,
    String snippet = '',
    Set<String>? categories,
  }) {
    if (layout.gmail && folder.gmailAll) {
      final membership = gmailMembership(f, layout, categories: categories ?? const {});
      return toMessage(
        accountId: _accountId,
        id: id,
        f: f,
        mailboxIds: membership.mailboxes,
        gmail: true,
        starred: membership.starred,
        draftLabel: membership.draft,
        snippet: snippet,
      );
    }
    return toMessage(
      accountId: _accountId,
      id: id,
      f: f,
      mailboxIds: {folder.mailboxId},
      gmail: layout.gmail,
      draftLabel: folder.role == MailboxRole.drafts,
      snippet: snippet,
    );
  }

  // Incremental ---------------------------------------------------------------

  Future<_FolderResult> _incremental(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout,
    FolderState st,
    ImapSelected sel, {
    required int exists,
    required int? uidNext,
    required int? modseq,
    required bool flagsDue,
    required int? unseenCount,
    required bool qresyncUsed,
    Set<String>? staleLabels,
  }) async {
    final gmail = layout.gmail;
    final previousNext = st.uidNext;
    final changed = <ImapFetch>[...sel.changed];
    var vanished = sel.vanished.intersection(st.known);
    UidSet? present;

    // New mail: everything from the old UIDNEXT on.
    var fresh = <ImapFetch>[];
    if (uidNext == null || uidNext > previousNext) {
      final r = await c.fetch('$previousNext:*', headerItems(gmail: gmail));
      // `n:*` also returns the last message when n is past the end.
      fresh = [for (final f in r.messages) if (f.uid! >= previousNext) f];
    }

    // Flag (and Gmail label) changes.
    final oldModseq = st.highestModSeq;
    if (staleLabels != null && st.known.isNotEmpty) {
      // Labels were renamed or removed: read every known message's labels.
      var returned = UidSet.empty;
      for (final chunk in st.known.chunks()) {
        final r = await c.fetch(chunk.toString(), ['UID', 'FLAGS', 'X-GM-LABELS']);
        changed.addAll(r.messages);
        returned = returned.union(UidSet.of([for (final f in r.messages) f.uid!]));
      }
      present = returned;
    } else if (qresyncUsed) {
      // QRESYNC reported changes and expunges with SELECT.
    } else if (c.condstoreEnabled && oldModseq != null && modseq != null) {
      if (modseq > oldModseq) {
        final r = await c.fetch('1:*', ['UID', 'FLAGS', if (gmail) ...['X-GM-LABELS', 'X-GM-MSGID']],
            changedSince: oldModseq, vanished: c.qresyncEnabled);
        changed.addAll(r.messages);
        vanished = vanished.union(r.vanished.intersection(st.known));
      }
    } else if (flagsDue && st.known.isNotEmpty) {
      var returned = UidSet.empty;
      for (final chunk in st.known.chunks()) {
        final r = await c.fetch(chunk.toString(), ['UID', 'FLAGS', if (gmail) 'X-GM-LABELS']);
        changed.addAll(r.messages);
        returned = returned.union(UidSet.of([for (final f in r.messages) f.uid!]));
      }
      // UID FETCH skips UIDs that no longer exist.
      present = returned;
    }
    final flagsCompared = present != null;

    // Deletions. Without QRESYNC, the message count tells whether anything
    // went away: EXISTS = previous count + new mail, unless some was
    // expunged.
    final newBelowNext = fresh.where((f) => uidNext == null || f.uid! < uidNext).length;
    if (!qresyncUsed && st.known.isNotEmpty) {
      if (present == null && exists != st.messages + newBelowNext) {
        var found = UidSet.empty;
        for (final chunk in st.known.chunks()) {
          found = found.union((await c.search(['UID $chunk'])).ids);
        }
        present = found;
      }
      if (present != null) vanished = vanished.union(st.known.difference(present));
    }

    // Apply flag and label changes to known messages.
    final freshUids = {for (final f in fresh) f.uid!};
    final deltas = <MessageDelta>[];
    final discoveries = <int>[];
    // Everything a message in All Mail can lose (not categories, which
    // are kept separately), including labels that no longer exist.
    final allLabelBoxes = {
      for (final m in layout.mailboxes)
        if (m.role != MailboxRole.category) m.id,
      ...?staleLabels,
    };
    for (final f in changed) {
      final uid = f.uid;
      if (uid == null || freshUids.contains(uid) || vanished.contains(uid)) continue;
      if (!st.known.contains(uid)) {
        // Gmail: an older message gained a label we show (moved back to
        // the inbox elsewhere). Fetch it.
        if (gmail && folder.gmailAll) {
          final labels = (f.gmailLabels ?? const []).map((l) => l.toLowerCase());
          if (labels.contains(r'\inbox') || labels.contains(r'\draft')) discoveries.add(uid);
        }
        continue;
      }
      final flags = f.flags;
      if (flags == null && f.gmailLabels == null) continue;
      final id = layout.gmail ? st.gmailIds[uid] : messageIdOf(f, folder, st.uidValidity, gmail: false);
      if (id == null) continue;
      bool? seen;
      bool? flagged;
      if (flags != null) {
        seen = flags.contains(r'\Seen');
        flagged = flags.contains(r'\Flagged');
      }
      if (gmail && folder.gmailAll && f.gmailLabels != null) {
        final mapped = mapGmailLabels(f.gmailLabels!, layout);
        flagged = (flagged ?? false) || mapped.starred;
        deltas.add(MessageDelta(
          id,
          addMailboxes: mapped.mailboxes,
          removeMailboxes: allLabelBoxes.difference(mapped.mailboxes),
          isRead: seen,
          isFlagged: flagged,
        ));
      } else {
        final wasUnseen = st.unseen.contains(uid);
        final wasFlagged = st.flagged.contains(uid);
        if (seen == !wasUnseen && flagged == wasFlagged) continue;
        deltas.add(MessageDelta(id, isRead: seen, isFlagged: flagged));
      }
      st.note(uid, seen: seen ?? !st.unseen.contains(uid), isFlagged: flagged ?? st.flagged.contains(uid));
    }

    // Write: deletions, new messages, discoveries, deltas.
    final vanishedIds = ctx.idsOf(folder.path, st, vanished);
    st.forget(vanished);
    if (vanishedIds.isNotEmpty) {
      if (gmail) {
        // Persisted with the folder state below being written later: a pass
        // cut short still deletes them next time.
        await ctx.addIds(store, ImapContext.pendingDeletesKey, vanishedIds);
      } else {
        await store.deleteMessages(_accountId, vanishedIds);
      }
    }
    final seenBefore = <String>{};
    final stored = await _storeInBatches(c, store, folder, layout, st, fresh, seenBefore: seenBefore);
    if (discoveries.isNotEmpty) {
      await _fetchByUid(c, store, folder, layout, st, UidSet.of(discoveries.take(_config.maxDiscoveries)));
    }
    if (deltas.isNotEmpty) await store.applyDeltas(_accountId, deltas);
    if (folder.gmailAll && (fresh.isNotEmpty || flagsDue)) await _refreshCategories(c, store, st);

    // Mail that arrived between SELECT and the FETCH is stored already:
    // move UIDNEXT past it, and count it, so it is neither fetched (and
    // announced) again nor mistaken for a deletion.
    final maxFresh = freshUids.isEmpty ? 0 : freshUids.reduce(math.max);
    final late = uidNext == null ? 0 : freshUids.where((u) => u >= uidNext).length;
    st
      ..uidNext = math.max(uidNext ?? previousNext, math.max(maxFresh + 1, previousNext))
      ..highestModSeq = modseq
      ..messages = exists + late
      ..unseenCount = unseenCount;
    if (flagsCompared || (c.condstoreEnabled && modseq != null)) st.flagsCheckedAt = DateTime.now();
    await ctx.writeFolder(store, folder.path, st);

    final me = ctx.account.email.toLowerCase();
    final notify = [
      for (final m in stored)
        if (!seenBefore.contains(m.id) &&
            !m.isRead &&
            !m.isDraft &&
            m.from?.email.toLowerCase() != me &&
            (gmail ? m.mailboxIds.contains(GmailBoxes.inbox) : folder.isInbox))
          m,
    ];
    return _FolderResult(newMessages: notify);
  }

  Future<List<Message>> _storeInBatches(
    ImapClient c,
    SyncStore store,
    ImapFolder folder,
    FolderLayout layout,
    FolderState st,
    List<ImapFetch> fetched, {
    Set<String>? seenBefore,
  }) async {
    final out = <Message>[];
    for (var i = 0; i < fetched.length; i += _config.fetchBatch) {
      final batch = fetched.sublist(i, math.min(fetched.length, i + _config.fetchBatch));
      out.addAll(await _storeFetched(c, store, folder, layout, st, batch, seenBefore: seenBefore));
    }
    return out;
  }

  // Gmail ---------------------------------------------------------------------

  /// Category of each of [uids] (in the selected All Mail), by searching
  /// Gmail's category operators. Primary is left implicit: it is "in the
  /// inbox and in no other category", as the inbox tabs define it.
  Future<Map<int, Set<String>>> _categoriesOf(ImapClient c, UidSet uids) async {
    final sets = await _categorySets(c, uids);
    final out = <int, Set<String>>{};
    sets.forEach((category, members) {
      for (final uid in members.values) {
        out.putIfAbsent(uid, () => {}).add(category);
      }
    });
    return out;
  }

  Future<Map<String, UidSet>> _categorySets(ImapClient c, UidSet uids) async {
    if (uids.isEmpty) return const {};
    final categories = [for (final c in gmailCategories) if (c.$2 != MailCategory.primary) c];
    final results = await Future.wait([
      for (final (_, _, _, query, _) in categories)
        () async {
          var found = UidSet.empty;
          for (final chunk in uids.chunks()) {
            found = found.union((await c.search(['UID $chunk X-GM-RAW ', ...c.searchString(query)])).ids);
          }
          return found;
        }(),
    ]);
    return {for (var i = 0; i < categories.length; i++) categories[i].$1: results[i]};
  }

  /// Re-checks the categories of known All Mail messages (Gmail may sort
  /// mail after it arrived, and users move mail between tabs).
  Future<void> _refreshCategories(ImapClient c, SyncStore store, FolderState st) async {
    final now = await _categorySets(c, st.known);
    final before = await _readCategories(store);
    final deltas = <MessageDelta>[];
    for (final MapEntry(key: category, value: members) in now.entries) {
      final old = before[category] ?? UidSet.empty;
      for (final uid in members.difference(old).values) {
        final id = st.gmailIds[uid];
        if (id != null) deltas.add(MessageDelta(id, addMailboxes: {category}));
      }
      for (final uid in old.difference(members).intersection(st.known).values) {
        final id = st.gmailIds[uid];
        if (id != null) deltas.add(MessageDelta(id, removeMailboxes: {category}));
      }
    }
    if (deltas.isNotEmpty) await store.applyDeltas(_accountId, deltas);
    await _writeCategories(store, now);
  }

  Future<Map<String, UidSet>> _readCategories(SyncStore store) async {
    final raw = await store.readState(_accountId, _categoriesKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).cast<String, Object?>().entries) e.key: UidSet.parse(e.value as String? ?? ''),
      };
    } on Object {
      return {};
    }
  }

  Future<void> _writeCategories(SyncStore store, Map<String, UidSet> sets) => store.writeState(
      _accountId, _categoriesKey, jsonEncode({for (final e in sets.entries) e.key: e.value.toString()}));

  /// Deletes Gmail messages that left a folder (persisted by the folder
  /// steps) unless another synced folder has them now: a move between All
  /// Mail, Trash and Spam is not a deletion.
  Future<void> _deleteVanishedGmail(SyncStore store, FolderLayout layout) async {
    final pending = await ctx.readIds(store, ImapContext.pendingDeletesKey);
    if (pending.isEmpty) return;
    final present = <String>{};
    for (final f in layout.synced) {
      final st = await ctx.readFolder(store, f.path);
      if (st != null) present.addAll(st.gmailIds.values);
    }
    final gone = pending.difference(present);
    await store.transaction(() async {
      if (gone.isNotEmpty) await store.deleteMessages(_accountId, gone.toList());
      await store.writeState(_accountId, ImapContext.pendingDeletesKey, null);
    });
  }

  // Repair --------------------------------------------------------------------

  /// Re-reads the messages queued for repair (an operation the server
  /// refused or only partly applied, see [ImapContext.repairKey]) and
  /// overwrites their local mailboxes and flags with the server's. Without
  /// this, an optimistic change the server never saw would stay forever:
  /// incremental sync only carries changes made on the server. Messages
  /// that no longer exist where they were are removed (if they moved, the
  /// folder they are in now brings them back).
  Future<void> _repair(ImapClient c, SyncStore store, FolderLayout layout) async {
    final ids = await ctx.readIds(store, ImapContext.repairKey);
    if (ids.isEmpty) return;
    final byFolder = <ImapFolder, Map<int, String>>{};
    final gone = <String>{};
    if (layout.gmail) {
      final missing = <String>[];
      for (final id in ids) {
        final loc = ctx.gmailLocation(id);
        final folder = loc == null ? null : layout.byPath(loc.path);
        if (folder == null) {
          missing.add(id);
        } else {
          byFolder.putIfAbsent(folder, () => {})[loc!.uid] = id;
        }
      }
      for (final f in layout.synced) {
        if (missing.isEmpty) break;
        await ctx.selectRw(c, f.path);
        final found = await ImapContext.searchGmailIds(c, missing);
        found.forEach((id, uid) => byFolder.putIfAbsent(f, () => {})[uid] = id);
        missing.removeWhere(found.containsKey);
      }
      gone.addAll(missing);
    } else {
      for (final id in ids) {
        final loc = ImapIds.parse(id);
        final folder = loc == null ? null : layout.byPath(loc.path);
        if (folder == null || folder.sync != FolderSync.always) {
          gone.add(id);
        } else {
          byFolder.putIfAbsent(folder, () => {})[loc!.uid] = id;
        }
      }
    }

    final truth = <String, Message>{};
    for (final MapEntry(key: folder, value: uids) in byFolder.entries) {
      final sel = await ctx.selectRw(c, folder.path);
      final r = await c.fetch(UidSet.of(uids.keys).toString(), [
        'UID',
        'FLAGS',
        'ENVELOPE',
        'BODY.PEEK[$headerFieldsSection]',
        if (layout.gmail) ...['X-GM-LABELS', 'X-GM-THRID', 'X-GM-MSGID'],
      ]);
      final got = {for (final f in r.messages) if (f.envelope != null) f.uid!: f};
      uids.forEach((uid, id) {
        final f = got[uid];
        final loc = ImapIds.parse(id);
        if (f == null || (loc != null && loc.uidValidity != sel.uidValidity)) {
          gone.add(id);
        } else {
          truth[id] = buildMessage(f, folder, layout, id: id);
        }
      });
    }

    final current = {
      for (final m in await store.messagesInThreads(_accountId, {for (final m in truth.values) m.threadId})) m.id: m,
    };
    // Categories are maintained separately and are left as they are.
    final categories = {for (final m in layout.mailboxes) if (m.role == MailboxRole.category) m.id};
    final deltas = [
      for (final MapEntry(key: id, value: server) in truth.entries)
        if (current[id] case final local?)
          MessageDelta(
            id,
            addMailboxes: server.mailboxIds,
            removeMailboxes: local.mailboxIds.difference(server.mailboxIds).difference(categories),
            isRead: server.isRead,
            isFlagged: server.isFlagged,
          ),
    ];
    imapLog.fine('Repaired ${deltas.length} messages, ${gone.length} gone');
    await store.transaction(() async {
      if (gone.isNotEmpty) await store.deleteMessages(_accountId, gone.toList());
      if (deltas.isNotEmpty) await store.applyDeltas(_accountId, deltas);
      await ctx.removeIds(store, ImapContext.repairKey, ids);
    });
  }

  // Paging ----------------------------------------------------------------------

  /// Loads up to [pageSize] messages older than what is stored for
  /// [mailboxId] (INBOX when null; All Mail for Gmail).
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, required int pageSize}) =>
      ctx.pool.run(ImapSlot.primary, (c) async {
        final layout = await ctx.ensureLayout(c);
        final ImapFolder? folder;
        List<Object>? criteria;
        if (layout.gmail) {
          final target = mailboxId == null ? null : layout.byMailboxId(mailboxId);
          if (target != null && target.sync == FolderSync.always) {
            folder = target;
          } else {
            folder = layout.gmailAllMail;
            if (mailboxId != null) criteria = _gmailCriteria(c, mailboxId);
          }
        } else {
          folder = layout.byMailboxId(mailboxId ?? 'INBOX');
        }
        if (folder == null || folder.sync != FolderSync.always) return const LoadMoreResult(loaded: 0, hasMore: false);
        final st = await ctx.readFolder(store, folder.path);
        if (st == null) return const LoadMoreResult(loaded: 0, hasMore: true); // Not synced yet.
        final sel = await ctx.selectRw(c, folder.path);
        if (sel.uidValidity != st.uidValidity) return const LoadMoreResult(loaded: 0, hasMore: true);
        final byFloor = criteria == null;
        if (byFloor && st.floor <= 1) return const LoadMoreResult(loaded: 0, hasMore: false);
        final hits = await c.search(criteria ?? ['UID 1:${st.floor - 1}']);
        final candidates = hits.ids.difference(st.known);
        final page = candidates.newest(pageSize);
        final stored = await _fetchByUid(c, store, folder, layout, st, page);
        if (byFloor && page.isNotEmpty) st.floor = math.min(st.floor, page.min);
        await ctx.writeFolder(store, folder.path, st);
        return LoadMoreResult(loaded: stored.length, hasMore: candidates.length > page.length);
      });

  /// Gmail search criteria for a mailbox's messages within All Mail.
  static List<Object> _gmailCriteria(ImapClient c, String mailboxId) {
    final raw = switch (mailboxId) {
      GmailBoxes.inbox => 'in:inbox',
      GmailBoxes.sent => 'in:sent',
      GmailBoxes.drafts => 'in:drafts',
      GmailBoxes.important => 'is:important',
      GmailBoxes.starred => 'is:starred',
      _ => gmailCategories.where((g) => g.$1 == mailboxId).map((g) => 'in:inbox ${g.$4}').firstOrNull,
    };
    if (raw != null) return ['X-GM-RAW ', ...c.searchString(raw)];
    return ['X-GM-LABELS ', ...c.searchString(c.encodeMailboxName(mailboxId))];
  }
}
