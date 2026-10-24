import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';

import '../imap/imap_client.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import '../settings.dart';
import 'folder_state.dart';
import 'folders.dart';
import 'ids.dart';
import 'session_pool.dart';

final Logger imapLog = Logger('plume.imap');

/// Sync windows, limits and timings of the IMAP provider.
final class ImapSyncConfig {
  const ImapSyncConfig({
    this.primaryWindow = 300,
    this.otherWindow = 100,
    this.gmailAllMailWindow = 300,
    this.gmailInboxWindow = 300,
    this.gmailDraftWindow = 100,
    this.fetchBatch = 100,
    this.flagRefreshInterval = const Duration(minutes: 10),
    this.fullBodyLimit = 2 << 20,
    this.searchPageSize = 50,
    this.searchFolderLimit = 12,
    this.maxDiscoveries = 200,
    this.pollInterval = const Duration(minutes: 2),
    this.pushDebounce = const Duration(seconds: 1),
    this.connectionIdleTimeout = const Duration(minutes: 5),
    this.client = const ImapClientConfig(),
  });

  /// Initial window (newest messages) of INBOX, Sent, Drafts and Archive.
  final int primaryWindow;

  /// Initial window of other folders (user folders, Junk, Trash).
  final int otherWindow;

  /// Gmail: newest messages of All Mail, plus the newest inbox and draft
  /// messages even when they are older than that.
  final int gmailAllMailWindow;
  final int gmailInboxWindow;
  final int gmailDraftWindow;

  /// Messages per FETCH and per store write, so lists fill progressively.
  final int fetchBatch;

  /// Without CONDSTORE, flags of folders other than INBOX are compared
  /// with the server this often (INBOX every pass).
  final Duration flagRefreshInterval;

  /// Messages up to this size are downloaded whole when opened; larger ones
  /// only have their text parts downloaded.
  final int fullBodyLimit;
  final int searchPageSize;

  /// Server search looks at INBOX, Archive, Sent and at most this many
  /// folders in total.
  final int searchFolderLimit;

  /// Gmail: older messages discovered through label changes (moved back
  /// to the inbox elsewhere) fetched per pass at most.
  final int maxDiscoveries;

  /// Polling interval for servers without IDLE.
  final Duration pollInterval;
  final Duration pushDebounce;
  final Duration connectionIdleTimeout;
  final ImapClientConfig client;
}

/// State shared by the provider's parts: settings, connections, the folder
/// layout from the last LIST, folder sync state and recent renames.
final class ImapContext {
  ImapContext({
    required this.account,
    required this.settings,
    required this.pool,
    required this.config,
  });

  final Account account;
  final MailServerSettings settings;
  final ImapSessionPool pool;
  final ImapSyncConfig config;

  String get accountId => account.id;

  /// The folder layout from the last LIST, if any.
  FolderLayout? layout;

  /// The server is Gmail (X-GM-EXT-1), once connected. Gmail files sent
  /// mail itself whatever the sync mode.
  bool? get isGmail => pool.profile?.isGmail;

  /// Label-based Gmail sync is in use: Gmail with All Mail visible over
  /// IMAP. Null until the first LIST.
  bool? get gmailMode => layout?.gmail ?? (isGmail == false ? false : null);

  /// A best guess before the first connection, from the host name.
  bool get looksLikeGmail {
    final h = settings.imap.host.toLowerCase();
    return gmailMode ?? isGmail ?? (h == 'imap.gmail.com' || h == 'imap.googlemail.com');
  }

  // Layout --------------------------------------------------------------------

  /// LISTs the folders (with LIST-STATUS, or STATUS for each synced folder)
  /// and maps them.
  Future<FolderLayout> refreshLayout(ImapClient c) async {
    final items = ['MESSAGES', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN', if (c.supports('CONDSTORE')) 'HIGHESTMODSEQ'];
    // STATUS of the mailbox selected on this connection reflects this
    // session's (possibly stale) view, so leave it first (RFC 3501 6.3.10).
    String? selected = c.selected?.name;
    if (selected != null && c.supports('UNSELECT')) {
      await c.unselect();
      selected = null;
    }
    var infos = await c.list(statusItems: items);
    if (selected != null) {
      // Without UNSELECT: do not trust its status; it gets selected anyway.
      infos = [for (final i in infos) i.name == selected ? i.withStatus(null) : i];
    }
    if (!c.supports('LIST-STATUS')) {
      final wanted = [
        for (final i in infos)
          if (i.isSelectable && !i.has(r'\all') && !i.has(r'\flagged') && i.name != selected) i,
      ];
      // Pipelined: one round trip for all folders.
      final statuses = await Future.wait([
        for (final i in wanted) c.status(i.name, items).then<ImapMailboxStatus?>((s) => s, onError: (Object _) => null),
      ]);
      final byName = {for (var k = 0; k < wanted.length; k++) wanted[k].name: statuses[k]};
      infos = [for (final i in infos) byName.containsKey(i.name) ? i.withStatus(byName[i.name]) : i];
    }
    final profile = pool.profile;
    // Users can hide All Mail from IMAP in Gmail's settings; labels cannot
    // be synced without it, so fall back to plain folders.
    final gmail = c.isGmail && infos.any((i) => i.has(r'\all'));
    if (c.isGmail && !gmail) {
      imapLog.warning('Gmail account without All Mail over IMAP; syncing folders instead of labels. '
          'Show "All Mail" in IMAP in Gmail\'s label settings for the best results.');
    }
    final mapped = gmail
        ? mapGmailFolders(accountId, infos)
        : mapGenericFolders(accountId, infos, namespacePrefix: profile?.namespacePrefix ?? '');
    layout = mapped;
    return mapped;
  }

  Future<FolderLayout> ensureLayout(ImapClient c) async => layout ?? await refreshLayout(c);

  /// Path for a folder Plume creates (e.g. `Archive`), inside the personal
  /// namespace (`INBOX.Archive` on Courier-style servers).
  String newFolderPath(String name) {
    final prefix = pool.profile?.namespacePrefix ?? '';
    return '$prefix$name';
  }

  // Folder state --------------------------------------------------------------

  Future<FolderState?> readFolder(SyncStore store, String path) async =>
      FolderState.decode(await store.readState(accountId, FolderState.keyFor(path)));

  Future<void> writeFolder(SyncStore store, String path, FolderState? state) async {
    await store.writeState(accountId, FolderState.keyFor(path), state?.encode());
    if (state != null && gmailMode == true) _indexGmail(path, state);
  }

  /// Selects [path] read-write, reusing the current selection.
  Future<ImapSelected> selectRw(ImapClient c, String path) async {
    final s = c.selected;
    if (s != null && s.name == path && !s.readOnly) return s;
    return c.select(path);
  }

  // Gmail id index ------------------------------------------------------------

  /// X-GM-MSGID → (folder, UID) for the synced Gmail folders.
  final _gmailIndex = <String, ({String path, int uid})>{};

  void _indexGmail(String path, FolderState state) {
    _gmailIndex.removeWhere((_, loc) => loc.path == path);
    for (final e in state.gmailIds.entries) {
      _gmailIndex[e.value] = (path: path, uid: e.key);
    }
  }

  /// Loads the Gmail index from the stored folder states (after a restart).
  Future<void> loadGmailIndex(SyncStore store) async {
    final l = layout;
    if (l == null || !l.gmail || _gmailIndex.isNotEmpty) return;
    for (final f in l.synced) {
      final st = await readFolder(store, f.path);
      if (st != null) _indexGmail(f.path, st);
    }
  }

  ({String path, int uid})? gmailLocation(String messageId) => _gmailIndex[messageId];

  /// Finds Gmail messages by X-GM-MSGID in the selected folder.
  static Future<Map<String, int>> searchGmailIds(ImapClient c, Iterable<String> hexIds) async {
    final out = <String, int>{};
    final ids = hexIds.toList();
    for (var i = 0; i < ids.length; i += 20) {
      final chunk = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
      final keys = [for (final id in chunk) ?gmailIdToDecimal(id)];
      if (keys.isEmpty) continue;
      final result = await c.search([orKeys('X-GM-MSGID', keys)]);
      if (result.ids.isEmpty) continue;
      final f = await c.fetch(result.ids.toString(), ['UID', 'X-GM-MSGID']);
      for (final m in f.messages) {
        final id = m.gmailMessageId;
        if (id != null && m.uid != null) out[id] = m.uid!;
      }
    }
    return out;
  }

  /// `OR KEY a OR KEY b KEY c` for a search over several values.
  static String orKeys(String key, List<String> values) {
    if (values.length == 1) return '$key ${values.single}';
    return 'OR $key ${values.first} ${orKeys(key, values.sublist(1))}';
  }

  // Persistent id lists --------------------------------------------------------

  /// Messages whose local state may have diverged from the server: an
  /// operation the server refused, or that found only some of its
  /// messages. The next sync re-reads them from the server and overwrites
  /// the local state (see `ImapSyncer`).
  static const repairKey = 'imap.repair';

  /// Gmail: messages that left a synced folder; deleted locally at the end
  /// of a complete sync pass unless another synced folder has them. Kept in
  /// the store so a pass cut short does not forget them.
  static const pendingDeletesKey = 'imap.gmail.pendingDeletes';

  Future<Set<String>> readIds(SyncStore store, String key) async {
    final raw = await store.readState(accountId, key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } on Object {
      return {};
    }
  }

  Future<void> addIds(SyncStore store, String key, Iterable<String> ids, {int cap = 2000}) async {
    final add = ids.toSet();
    if (add.isEmpty) return;
    final all = {...await readIds(store, key), ...add};
    final list = all.toList();
    await store.writeState(accountId, key, jsonEncode(list.length > cap ? list.sublist(list.length - cap) : list));
  }

  Future<void> removeIds(SyncStore store, String key, Iterable<String> ids) async {
    final current = await readIds(store, key);
    final left = current.difference(ids.toSet());
    if (left.length == current.length) return;
    await store.writeState(accountId, key, left.isEmpty ? null : jsonEncode(left.toList()));
  }

  /// Gmail strips a message's labels when it is moved to Trash over IMAP,
  /// so the labels are remembered here (X-GM-MSGID → labels) to put them
  /// back on restore.
  static const trashedLabelsKey = 'imap.gmail.trashedLabels';

  Future<Map<String, List<String>>> readTrashedLabels(SyncStore store) async {
    final raw = await store.readState(accountId, trashedLabelsKey);
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

  Future<void> writeTrashedLabels(SyncStore store, Map<String, List<String>> labels) async {
    var entries = labels.entries.toList();
    if (entries.length > 2000) entries = entries.sublist(entries.length - 2000);
    await store.writeState(
        accountId, trashedLabelsKey, entries.isEmpty ? null : jsonEncode({for (final e in entries) e.key: e.value}));
  }

  // Renames -------------------------------------------------------------------

  static const _renamesKey = 'imap.renames';
  final _renames = <String, ({String to, int at})>{};
  bool _renamesLoaded = false;

  /// Follows recorded renames from [id] to the message's current id.
  /// Operations queued (or undone) with ids from before a move still reach
  /// the message.
  String resolve(String id) {
    var current = id;
    for (var hops = 0; hops < 20; hops++) {
      final next = _renames[current];
      if (next == null) return current;
      current = next.to;
    }
    return current;
  }

  Future<void> loadRenames(SyncStore store) async {
    if (_renamesLoaded) return;
    _renamesLoaded = true;
    final raw = await store.readState(accountId, _renamesKey);
    if (raw == null) return;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      for (final e in j.entries) {
        final v = e.value;
        if (v is List && v.length == 2 && v[0] is String && v[1] is num) {
          _renames[e.key] = (to: v[0] as String, at: (v[1] as num).toInt());
        }
      }
    } on Object {
      // Corrupt: start over; only undo of very recent moves is affected.
    }
  }

  /// Records renames and persists the recent ones (a week, at most 2000).
  Future<void> recordRenames(SyncStore store, Map<String, String> oldToNew) async {
    if (oldToNew.isEmpty) return;
    await loadRenames(store);
    final now = DateTime.now().millisecondsSinceEpoch;
    oldToNew.forEach((from, to) => _renames[from] = (to: to, at: now));
    final cutoff = now - const Duration(days: 7).inMilliseconds;
    _renames.removeWhere((_, v) => v.at < cutoff);
    if (_renames.length > 2000) {
      final oldest = _renames.entries.toList()..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in oldest.take(_renames.length - 2000)) {
        _renames.remove(e.key);
      }
    }
    await store.writeState(accountId, _renamesKey, jsonEncode({for (final e in _renames.entries) e.key: [e.value.to, e.value.at]}));
  }

  /// Where a generic message id points now (after renames).
  ImapLocation? locate(String id) => ImapIds.parse(resolve(id));

  /// Known UIDs of [state] as message ids (generic or Gmail).
  List<String> idsOf(String path, FolderState state, UidSet uids) => [
        for (final uid in uids.values)
          if (gmailMode == true) ?state.gmailIds[uid] else ImapIds.message(path, state.uidValidity, uid),
      ];
}
