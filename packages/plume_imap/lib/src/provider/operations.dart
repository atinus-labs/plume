import 'dart:math' as math;

import 'package:plume_core/plume_core.dart';

import '../imap/imap_client.dart';
import '../imap/imap_exception.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import 'context.dart';
import 'errors.dart';
import 'folders.dart';
import 'ids.dart';
import 'message_mapping.dart';
import 'session_pool.dart';

/// A message an operation acts on, at its current server location.
typedef _Target = ({String id, ImapLocation loc});

/// Maps [MailOperation]s onto IMAP: optimistic local effects and the
/// server commands.
///
/// Generic servers are folder-based: archiving moves INBOX messages to the
/// Archive folder (created on first use), spam and trash are moves, and a
/// "label" change is a move between folders. Moves re-key the stored
/// messages using COPYUID so bodies survive and nothing flickers.
///
/// Gmail is label-based: archive removes `\Inbox` with X-GM-LABELS, labels
/// are added and removed in place, and only Trash and Spam are folder
/// moves. Messages keep their ids (X-GM-MSGID) through all of it.
final class ImapOperations {
  ImapOperations(this.ctx);

  final ImapContext ctx;

  String get _accountId => ctx.accountId;

  bool _gmailFor(List<Mailbox> mailboxes) =>
      ctx.gmailMode ?? mailboxes.any((m) => m.id == GmailBoxes.trash);

  // Local effects ---------------------------------------------------------------

  LocalMutation localEffect(MailOperation op, List<Mailbox> mailboxes) =>
      _gmailFor(mailboxes) ? _gmailEffect(op) : _genericEffect(op, mailboxes);

  static LocalMutation _flags(MailAction action) => switch (action) {
        MailAction.markRead => const LocalMutation(setRead: true),
        MailAction.markUnread => const LocalMutation(setRead: false),
        MailAction.flag => const LocalMutation(setFlagged: true),
        MailAction.unflag => const LocalMutation(setFlagged: false),
        _ => const LocalMutation(),
      };

  LocalMutation _gmailEffect(MailOperation op) => switch (op) {
        ActionOperation(:final action) => switch (action) {
            MailAction.archive => const LocalMutation(removeMailboxes: {GmailBoxes.inbox}),
            // From Trash or Spam this is a move back out, as on the web.
            MailAction.moveToInbox =>
              const LocalMutation(addMailboxes: {GmailBoxes.inbox}, removeMailboxes: {GmailBoxes.trash, GmailBoxes.junk}),
            MailAction.trash =>
              const LocalMutation(addMailboxes: {GmailBoxes.trash}, removeMailboxes: {GmailBoxes.inbox}),
            MailAction.restore =>
              const LocalMutation(addMailboxes: {GmailBoxes.inbox}, removeMailboxes: {GmailBoxes.trash}),
            MailAction.deleteForever => const LocalMutation(delete: true, onlyIn: {GmailBoxes.trash, GmailBoxes.junk}),
            MailAction.markSpam =>
              const LocalMutation(addMailboxes: {GmailBoxes.junk}, removeMailboxes: {GmailBoxes.inbox}),
            MailAction.markNotSpam =>
              const LocalMutation(addMailboxes: {GmailBoxes.inbox}, removeMailboxes: {GmailBoxes.junk}),
            _ => _flags(action),
          },
        LabelOperation(:final add, :final remove) => LocalMutation(
            addMailboxes: add.difference({GmailBoxes.starred}),
            removeMailboxes: remove.difference({GmailBoxes.starred}),
            setFlagged: add.contains(GmailBoxes.starred) ? true : (remove.contains(GmailBoxes.starred) ? false : null),
          ),
      };

  /// Mailbox ids by role for a generic account; folders Plume would create
  /// are predicted so the optimistic move has somewhere to go.
  ({String inbox, String archive, String trash, String junk, Set<String> users, Set<String> all}) _roles(
    List<Mailbox> mailboxes,
  ) {
    String role(MailboxRole r, String name) =>
        mailboxes.where((m) => m.role == r).firstOrNull?.id ?? ctx.newFolderPath(name);
    return (
      inbox: 'INBOX',
      archive: role(MailboxRole.archive, 'Archive'),
      trash: role(MailboxRole.trash, 'Trash'),
      junk: role(MailboxRole.junk, 'Junk'),
      users: {for (final m in mailboxes) if (m.role == null && !m.hidden) m.id},
      all: {for (final m in mailboxes) m.id},
    );
  }

  LocalMutation _move(Set<String> from, String to) {
    final sources = from.difference({to});
    if (sources.isEmpty) return const LocalMutation();
    return LocalMutation(addMailboxes: {to}, removeMailboxes: sources, onlyIn: sources);
  }

  LocalMutation _genericEffect(MailOperation op, List<Mailbox> mailboxes) {
    final r = _roles(mailboxes);
    return switch (op) {
      ActionOperation(:final action) => switch (action) {
          MailAction.archive => _move({r.inbox}, r.archive),
          MailAction.moveToInbox => _move({r.archive, ...r.users}, r.inbox),
          MailAction.trash => _move({...r.all, r.archive}, r.trash),
          MailAction.restore => _move({r.trash}, r.inbox),
          MailAction.deleteForever => LocalMutation(delete: true, onlyIn: {r.trash, r.junk}),
          MailAction.markSpam => _move({r.inbox, r.archive, ...r.users}, r.junk),
          MailAction.markNotSpam => _move({r.junk}, r.inbox),
          _ => _flags(action),
        },
      LabelOperation(:final add, :final remove) => () {
          final to = add.isNotEmpty ? add.first : r.archive;
          return _move(remove.isNotEmpty ? remove : {r.inbox, r.archive, ...r.users}, to);
        }(),
    };
  }

  // Server ------------------------------------------------------------------------

  Future<void> execute(SyncStore store, MailOperation op) async {
    if (op.ids.isEmpty) return;
    await ctx.loadRenames(store);
    try {
      await ctx.pool.run(ImapSlot.primary, (c) async {
        final layout = await ctx.ensureLayout(c);
        if (layout.gmail) {
          await _executeGmail(c, store, op, layout);
        } else {
          await _executeGeneric(c, store, op, layout);
        }
      });
    } on Object catch (e) {
      final error = toMailException(e);
      if (error is! TransientException && error is! AuthException) {
        // The engine drops the operation, but its optimistic effect is in
        // the store: have the next sync put the server's state back.
        await _queueRepair(store, op);
      }
      rethrow;
    }
  }

  /// Queues the messages [op] touched locally for repair.
  Future<void> _queueRepair(SyncStore store, MailOperation op) async {
    final ids = op.scope == OperationScope.thread
        ? [for (final m in await store.messagesInThreads(_accountId, op.ids)) m.id]
        : [for (final id in op.ids) ctx.resolve(id)];
    await ctx.addIds(store, ImapContext.repairKey, ids);
  }

  /// The messages [op] targets, at their current server location.
  Future<List<_Target>> _targets(ImapClient c, SyncStore store, MailOperation op, FolderLayout layout) async {
    final out = <_Target>[];
    void add(String id) {
      final loc = ImapIds.parse(id);
      if (loc != null) out.add((id: id, loc: loc));
    }

    if (op.scope == OperationScope.message) {
      for (final id in op.ids) {
        add(ctx.resolve(id));
      }
    } else {
      final stored = await store.messagesInThreads(_accountId, op.ids);
      stored.map((m) => m.id).forEach(add);
      // Deleting forever removed the Trash and Spam rows already (the
      // optimistic effect), while other rows of the conversation remain:
      // find its copies there on the server, by its root Message-ID.
      if (op is ActionOperation && op.action == MailAction.deleteForever) {
        final known = {for (final t in out) t.id};
        for (final role in [MailboxRole.trash, MailboxRole.junk]) {
          final folder = layout.byRole(role);
          if (folder == null) continue;
          for (final t in await _findThreads(c, folder, op.ids.toSet())) {
            if (known.add(t.id)) out.add(t);
          }
        }
      }
    }
    if (out.isEmpty) throw NotFoundException('Nothing left to apply ${op.toJson()['type']} to');
    return out;
  }

  /// Messages of [threadIds] in [folder], by searching for their root
  /// Message-ID and checking each hit's thread.
  Future<List<_Target>> _findThreads(ImapClient c, ImapFolder folder, Set<String> threadIds) async {
    final sel = await ctx.selectRw(c, folder.path);
    final uv = sel.uidValidity;
    if (sel.exists == 0 || uv == null) return const [];
    final out = <_Target>[];
    for (final thread in threadIds) {
      final root = ImapIds.threadRoot(thread);
      if (root == null) continue;
      final q = c.searchString(root);
      final hits = await c.search(['OR OR HEADER Message-ID ', ...q, ' HEADER References ', ...q, ' HEADER In-Reply-To ', ...q]);
      if (hits.ids.isEmpty) continue;
      final r = await c.fetch(hits.ids.toString(), ['UID', 'ENVELOPE', 'BODY.PEEK[$headerFieldsSection]']);
      for (final f in r.messages) {
        final id = ImapIds.message(folder.path, uv, f.uid!);
        if (toMessage(accountId: _accountId, id: id, f: f, mailboxIds: const {}, gmail: false).threadId != thread) continue;
        out.add((id: id, loc: (path: folder.path, uidValidity: uv, uid: f.uid!)));
      }
    }
    return out;
  }

  Future<void> _executeGeneric(ImapClient c, SyncStore store, MailOperation op, FolderLayout layout) async {
    final targets = await _targets(c, store, op, layout);
    final byFolder = <ImapFolder, List<_Target>>{};
    final stale = <String>[];
    for (final t in targets) {
      final folder = layout.byPath(t.loc.path);
      if (folder == null) {
        stale.add(t.id); // Folder gone: the server cannot have applied it.
      } else {
        byFolder.putIfAbsent(folder, () => []).add(t);
      }
    }
    await ctx.addIds(store, ImapContext.repairKey, stale);
    bool isUser(ImapFolder f) => f.role == null && f.sync == FolderSync.always;
    Iterable<MapEntry<ImapFolder, List<_Target>>> from(bool Function(ImapFolder f) test) =>
        byFolder.entries.where((e) => test(e.key));

    switch (op) {
      case ActionOperation(:final action):
        switch (action) {
          case MailAction.archive:
            await _moveAll(c, store, from((f) => f.isInbox), () => _ensureRole(c, layout, MailboxRole.archive, 'Archive'));
          case MailAction.moveToInbox:
            await _moveAll(c, store, from((f) => f.role == MailboxRole.archive || isUser(f)), () async => 'INBOX');
          case MailAction.trash:
            await _moveAll(c, store, from((f) => f.role != MailboxRole.trash),
                () => _ensureRole(c, layout, MailboxRole.trash, 'Trash'));
          case MailAction.restore:
            await _moveAll(c, store, from((f) => f.role == MailboxRole.trash), () async => 'INBOX');
          case MailAction.markSpam:
            await _moveAll(c, store, from((f) => f.isInbox || f.role == MailboxRole.archive || isUser(f)),
                () => _ensureRole(c, layout, MailboxRole.junk, 'Junk'));
          case MailAction.markNotSpam:
            await _moveAll(c, store, from((f) => f.role == MailboxRole.junk), () async => 'INBOX');
          case MailAction.deleteForever:
            for (final e in from((f) => f.role == MailboxRole.trash || f.role == MailboxRole.junk)) {
              await _expunge(c, store, e.key, e.value);
            }
          case MailAction.markRead || MailAction.markUnread || MailAction.flag || MailAction.unflag:
            for (final e in byFolder.entries) {
              await _setFlag(c, store, e.key, e.value, action);
            }
        }
      case LabelOperation(:final add, :final remove):
        final dest = add.isEmpty ? null : layout.byMailboxId(add.first);
        if (add.isNotEmpty && dest == null) throw PermanentException('Folder ${add.first} does not exist');
        final destPath = dest?.path;
        final sources = remove.isNotEmpty
            ? from((f) => remove.contains(f.mailboxId))
            : from((f) => f.path != destPath && (f.isInbox || f.role == MailboxRole.archive || isUser(f)));
        await _moveAll(c, store, sources,
            () async => destPath ?? await _ensureRole(c, layout, MailboxRole.archive, 'Archive'));
    }
  }

  /// Path of the folder with [role], creating `name` when the server has
  /// none (an account that never archived has no Archive folder).
  Future<String> _ensureRole(ImapClient c, FolderLayout layout, MailboxRole role, String name) async {
    final existing = layout.byRole(role);
    if (existing != null) return existing.path;
    final path = ctx.newFolderPath(name);
    await _create(c, path);
    return path;
  }

  Future<void> _create(ImapClient c, String path) async {
    imapLog.info('Creating folder for ${path.split(RegExp(r'[./]')).last}');
    await c.create(path);
    try {
      await c.subscribe(path);
    } on ImapCommandException {
      // Not all servers want subscriptions; the folder exists either way.
    }
    ctx.layout = null; // LIST again before relying on roles.
  }

  Future<void> _moveAll(
    ImapClient c,
    SyncStore store,
    Iterable<MapEntry<ImapFolder, List<_Target>>> groups,
    Future<String> Function() destination,
  ) async {
    final list = groups.toList();
    if (list.isEmpty) return;
    final dest = await destination();
    for (final e in list) {
      if (e.key.path == dest) continue;
      await _moveFolder(c, store, e.key, e.value, dest);
    }
  }

  /// The targets still valid in the selected folder. Ids from before a
  /// UIDVALIDITY change name nothing any more; they are queued for repair
  /// (which removes them) since the server cannot have applied anything.
  Future<List<_Target>> _validTargets(SyncStore store, List<_Target> targets, ImapSelected sel) async {
    final valid = [for (final t in targets) if (t.loc.uidValidity == sel.uidValidity) t];
    if (valid.length != targets.length) {
      await ctx.addIds(store, ImapContext.repairKey, [for (final t in targets) if (t.loc.uidValidity != sel.uidValidity) t.id]);
    }
    return valid;
  }

  /// Moves [targets] out of [folder] and re-keys them in the store.
  Future<void> _moveFolder(ImapClient c, SyncStore store, ImapFolder folder, List<_Target> targets, String dest) async {
    final sel = await ctx.selectRw(c, folder.path);
    final valid = await _validTargets(store, targets, sel);
    if (valid.isEmpty) return;
    final uids = UidSet.of([for (final t in valid) t.loc.uid]);
    // Without UIDPLUS there is no COPYUID; remember Message-IDs to find the
    // moved copies afterwards.
    final headerIds = <int, String>{};
    if (!c.supports('UIDPLUS')) {
      final r = await c.fetch(uids.toString(), ['UID', 'ENVELOPE']);
      for (final f in r.messages) {
        final mid = f.envelope?.messageId;
        if (mid != null) headerIds[f.uid!] = mid;
      }
    }
    ImapCopyUid? copied;
    try {
      copied = await c.move(uids, dest);
    } on ImapCommandException catch (e) {
      if (e.code != 'TRYCREATE') rethrow;
      await _create(c, dest);
      await ctx.selectRw(c, folder.path);
      copied = await c.move(uids, dest);
    }

    final renames = <String, String>{};
    if (copied != null) {
      for (final t in valid) {
        final newUid = copied.mapping[t.loc.uid];
        if (newUid != null) renames[t.id] = ImapIds.message(dest, copied.uidValidity, newUid);
      }
    } else if (headerIds.isNotEmpty) {
      final destSel = await c.select(dest);
      for (final t in valid) {
        final mid = headerIds[t.loc.uid];
        if (mid == null) continue;
        final hits = await c.search(['HEADER Message-ID ', ...c.searchString(mid)]);
        if (hits.ids.isNotEmpty && destSel.uidValidity != null) {
          renames[t.id] = ImapIds.message(dest, destSel.uidValidity!, hits.ids.max);
        }
      }
    }

    final st = await ctx.readFolder(store, folder.path);
    if (st != null && st.uidValidity == sel.uidValidity) {
      st
        ..forget(uids)
        ..messages = math.max(0, st.messages - valid.length);
      await ctx.writeFolder(store, folder.path, st);
    }
    final unresolved = [for (final t in valid) if (!renames.containsKey(t.id)) t.id];
    await store.transaction(() async {
      await store.renameMessages(_accountId, renames);
      // Server truth, in case the optimistic effect did not reach these
      // rows (an undo carrying ids from before an earlier move).
      await store.applyDeltas(_accountId, [
        for (final id in renames.values) MessageDelta(id, addMailboxes: {dest}, removeMailboxes: {folder.mailboxId}),
      ]);
      // Moved copies we cannot name come back with the next sync.
      if (unresolved.isNotEmpty) await store.deleteMessages(_accountId, unresolved);
    });
    await ctx.recordRenames(store, renames);
  }

  Future<void> _expunge(ImapClient c, SyncStore store, ImapFolder folder, List<_Target> targets) async {
    final sel = await ctx.selectRw(c, folder.path);
    final valid = await _validTargets(store, targets, sel);
    if (valid.isEmpty) return;
    final uids = UidSet.of([for (final t in valid) t.loc.uid]);
    await c.store(uids, '+FLAGS.SILENT', const [r'\Deleted']);
    await c.expunge(uids);
    final st = await ctx.readFolder(store, folder.path);
    if (st != null && st.uidValidity == sel.uidValidity) {
      st
        ..forget(uids)
        ..messages = math.max(0, st.messages - valid.length);
      await ctx.writeFolder(store, folder.path, st);
    }
    await store.deleteMessages(_accountId, [for (final t in valid) t.id]);
  }

  static (String, String) _flagChange(MailAction action) => switch (action) {
        MailAction.markRead => ('+FLAGS.SILENT', r'\Seen'),
        MailAction.markUnread => ('-FLAGS.SILENT', r'\Seen'),
        MailAction.flag => ('+FLAGS.SILENT', r'\Flagged'),
        _ => ('-FLAGS.SILENT', r'\Flagged'),
      };

  Future<void> _setFlag(ImapClient c, SyncStore store, ImapFolder folder, List<_Target> targets, MailAction action) async {
    final sel = await ctx.selectRw(c, folder.path);
    final valid = await _validTargets(store, targets, sel);
    if (valid.isEmpty) return;
    final uids = UidSet.of([for (final t in valid) t.loc.uid]);
    final (verb, flag) = _flagChange(action);
    await c.store(uids, verb, [flag]);
    final st = await ctx.readFolder(store, folder.path);
    if (st != null && st.uidValidity == sel.uidValidity) {
      // Keep the flag snapshot in line so the next comparison sees no change.
      if (flag == r'\Seen') {
        st.unseen = verb.startsWith('+') ? st.unseen.difference(uids) : st.unseen.union(uids.intersection(st.known));
      } else {
        st.flagged = verb.startsWith('+') ? st.flagged.union(uids.intersection(st.known)) : st.flagged.difference(uids);
      }
      await ctx.writeFolder(store, folder.path, st);
    }
  }

  // Gmail -------------------------------------------------------------------------

  /// Gmail keeps every message in exactly one of All Mail (with labels),
  /// Trash and Spam. Operations look for their messages in All Mail, where
  /// the last sync saw them, and where the action applies, and act from
  /// wherever they are. Only the folder an action really needs must be
  /// visible over IMAP (users can hide Trash or Spam in Gmail's settings).
  Future<void> _executeGmail(ImapClient c, SyncStore store, MailOperation op, FolderLayout layout) async {
    final paths = {
      _Place.all: layout.gmailAllMail?.path,
      _Place.trash: layout.byRole(MailboxRole.trash)?.path,
      _Place.junk: layout.byRole(MailboxRole.junk)?.path,
    };
    _Place? placeOf(String path) => paths.entries.where((e) => e.value == path).firstOrNull?.key;

    // The messages the optimistic effect touched, for locating and repair.
    final local = op.scope == OperationScope.thread
        ? [for (final m in await store.messagesInThreads(_accountId, op.ids)) m.id]
        : [for (final id in op.ids) ctx.resolve(id)];
    final look = <_Place>{_Place.all};
    for (final id in local) {
      final loc = ctx.gmailLocation(id);
      final place = loc == null ? null : placeOf(loc.path);
      if (place != null) look.add(place);
    }
    look.addAll(switch (op) {
      ActionOperation(action: MailAction.restore) => const [_Place.trash],
      ActionOperation(action: MailAction.markNotSpam) => const [_Place.junk],
      ActionOperation(action: MailAction.deleteForever) => const [_Place.trash, _Place.junk],
      LabelOperation(:final remove) => [
          if (remove.contains(GmailBoxes.trash)) _Place.trash,
          if (remove.contains(GmailBoxes.junk)) _Place.junk,
        ],
      _ => const <_Place>[],
    });

    final found = <_Place, Map<int, _GmailHit>>{};
    Future<void> search(_Place place) async {
      final path = paths[place];
      if (path == null || found.containsKey(place)) return;
      final sel = await ctx.selectRw(c, path);
      if (sel.exists == 0) return;
      final uids = await _gmailUids(c, op);
      if (uids.isEmpty) return;
      final r = await c.fetch(uids.toString(), ['UID', 'X-GM-MSGID', 'X-GM-LABELS', 'ENVELOPE']);
      final me = ctx.account.email.toLowerCase();
      final hits = <int, _GmailHit>{
        for (final f in r.messages)
          if (uids.contains(f.uid!) && f.gmailMessageId != null)
            f.uid!: (
              id: f.gmailMessageId!,
              labels: f.gmailLabels ?? const [],
              fromMe: f.envelope?.from.any((a) => a.email.toLowerCase() == me) ?? false,
            ),
      };
      if (hits.isNotEmpty) found[place] = hits;
    }

    for (final place in _Place.values) {
      if (look.contains(place)) await search(place);
    }
    // Moved elsewhere since the last sync: look everywhere.
    if (found.isEmpty) {
      for (final place in _Place.values) {
        await search(place);
      }
    }
    if (found.isEmpty) throw NotFoundException('No messages found for ${op.toJson()['type']}');

    final repair = <String>{
      ...local.toSet().difference({for (final hits in found.values) for (final h in hits.values) h.id}),
    };
    for (final MapEntry(key: place, value: hits) in found.entries) {
      repair.addAll(await _applyGmail(c, store, op, layout, paths, place, hits));
    }
    // Messages the server did not have, or that the action could not
    // reach: the next sync puts back what the server says.
    await ctx.addIds(store, ImapContext.repairKey, repair);
  }

  /// UIDs in the selected folder of the operation's threads or messages.
  Future<UidSet> _gmailUids(ImapClient c, MailOperation op) async {
    final key = op.scope == OperationScope.thread ? 'X-GM-THRID' : 'X-GM-MSGID';
    final values = [for (final id in op.ids) ?gmailIdToDecimal(ctx.resolve(id))];
    var out = UidSet.empty;
    for (var i = 0; i < values.length; i += 20) {
      final chunk = values.sublist(i, math.min(values.length, i + 20));
      out = out.union((await c.search([ImapContext.orKeys(key, chunk)])).ids);
    }
    return out;
  }

  /// Applies [op] to [hits] in [place] (selected). Returns ids it could not
  /// apply, for repair.
  Future<Set<String>> _applyGmail(
    ImapClient c,
    SyncStore store,
    MailOperation op,
    FolderLayout layout,
    Map<_Place, String?> paths,
    _Place place,
    Map<int, _GmailHit> hits,
  ) async {
    final path = paths[place]!;
    final uids = UidSet.of(hits.keys);
    final ids = {for (final h in hits.values) h.id};
    await ctx.selectRw(c, path); // Searching may have selected another folder.

    String need(_Place p) =>
        paths[p] ??
        (throw PermanentException('Gmail\'s ${p == _Place.trash ? 'Trash' : 'Spam'} is hidden from IMAP; '
            'show it in Gmail settings (Labels, "Show in IMAP") to use this action'));

    Future<void> forget() async {
      final st = await ctx.readFolder(store, path);
      if (st == null) return;
      st
        ..forget(uids.intersection(st.known))
        ..messages = math.max(0, st.messages - uids.length);
      await ctx.writeFolder(store, path, st);
    }

    Future<void> move(String dest) async {
      await c.move(uids, dest);
      await forget();
    }

    Future<void> toTrash() async {
      final trash = need(_Place.trash);
      if (place == _Place.trash) return;
      if (place == _Place.all) {
        // Moving to Trash strips Gmail labels; remember them for restore.
        final saved = await ctx.readTrashedLabels(store);
        for (final h in hits.values) {
          saved[h.id] = h.labels;
        }
        await ctx.writeTrashedLabels(store, saved);
      }
      await move(trash);
    }

    Future<void> toSpam() async {
      final junk = need(_Place.junk);
      if (place != _Place.junk) await move(junk);
    }

    Future<void> outOfSpam() async {
      if (place == _Place.junk) await move('INBOX'); // Gmail's "Not spam"
    }

    Future<void> restore() async {
      if (place == _Place.trash) await _restoreFromTrash(c, store, layout, paths, hits, forget);
    }

    switch (op) {
      case ActionOperation(:final action):
        switch (action) {
          case MailAction.archive:
            if (place == _Place.all) await c.store(uids, '-X-GM-LABELS', const [r'\Inbox']);
          case MailAction.moveToInbox:
            if (place == _Place.all) {
              await c.store(uids, '+X-GM-LABELS', const [r'\Inbox']);
            } else {
              await move('INBOX');
            }
          case MailAction.trash:
            await toTrash();
          case MailAction.markSpam:
            await toSpam();
          case MailAction.restore:
            await restore();
          case MailAction.markNotSpam:
            await outOfSpam();
          case MailAction.deleteForever:
            // Expunging from Trash or Spam deletes for good on Gmail.
            if (place == _Place.all) return const {};
            await c.store(uids, '+FLAGS.SILENT', const [r'\Deleted']);
            await c.expunge(uids);
            await forget();
          case MailAction.markRead || MailAction.markUnread || MailAction.flag || MailAction.unflag:
            final (verb, flag) = _flagChange(action);
            await c.store(uids, verb, [flag]);
        }
      case LabelOperation(:final add, :final remove):
        if (add.contains(GmailBoxes.trash)) {
          await toTrash();
        } else if (add.contains(GmailBoxes.junk)) {
          await toSpam();
        } else if (remove.contains(GmailBoxes.trash) && place == _Place.trash) {
          await restore();
        } else if (remove.contains(GmailBoxes.junk) && place == _Place.junk) {
          await outOfSpam();
        } else if (place == _Place.all) {
          final adds = [for (final id in add) ?gmailLabelFor(id)];
          final removes = [for (final id in remove) ?gmailLabelFor(id)];
          if (adds.isNotEmpty) await c.store(uids, '+X-GM-LABELS', adds);
          if (removes.isNotEmpty) await c.store(uids, '-X-GM-LABELS', removes);
        } else {
          return ids; // Labels on mail in Trash or Spam are not supported here.
        }
    }
    return const {};
  }

  /// Gmail restores a message to the labels it had before it was trashed
  /// only in its web interface; over IMAP, moving to Trash strips labels.
  /// So: move back out of Trash (into INBOX, the one move known to restore
  /// a message to All Mail), then remove `\Inbox` again from messages that
  /// were not in the inbox and put back the labels remembered at trash
  /// time. Without a record (trashed elsewhere), mail from others goes to
  /// the inbox and the user's own mail is archived.
  Future<void> _restoreFromTrash(
    ImapClient c,
    SyncStore store,
    FolderLayout layout,
    Map<_Place, String?> paths,
    Map<int, _GmailHit> hits,
    Future<void> Function() forgetMoved,
  ) async {
    final saved = await ctx.readTrashedLabels(store);
    final target = <String, List<String>>{
      for (final h in hits.values)
        h.id: saved[h.id] ?? (h.labels.isNotEmpty ? h.labels : [if (!h.fromMe) r'\Inbox']),
    };
    await c.move(UidSet.of(hits.keys), 'INBOX');
    await forgetMoved();
    final all = paths[_Place.all];
    if (all != null) {
      await ctx.selectRw(c, all);
      final uids = await ImapContext.searchGmailIds(c, target.keys);
      bool hasInbox(List<String> labels) => labels.any((l) => l.toLowerCase() == r'\inbox');
      final archived = UidSet.of([for (final e in uids.entries) if (!hasInbox(target[e.key]!)) e.value]);
      if (archived.isNotEmpty) await c.store(archived, '-X-GM-LABELS', const [r'\Inbox']);
      // System labels Gmail sets itself are not restored by STORE.
      const fixed = {r'\inbox', r'\sent', r'\draft', r'\drafts', r'\trash', r'\spam', r'\junk', r'\all'};
      final groups = <String, List<int>>{};
      final labelsOf = <String, List<String>>{};
      for (final e in uids.entries) {
        final labels = [for (final l in target[e.key]!) if (!fixed.contains(l.toLowerCase())) l]..sort();
        if (labels.isEmpty) continue;
        final key = labels.join('\u0000');
        groups.putIfAbsent(key, () => []).add(e.value);
        labelsOf[key] = labels;
      }
      for (final MapEntry(key: key, value: group) in groups.entries) {
        await c.store(UidSet.of(group), '+X-GM-LABELS', labelsOf[key]!);
      }
    }
    // The optimistic effect put everything in the inbox; correct it now.
    await store.applyDeltas(_accountId, [
      for (final MapEntry(key: id, value: labels) in target.entries)
        () {
          final mapped = mapGmailLabels(labels, layout);
          return MessageDelta(
            id,
            addMailboxes: mapped.mailboxes,
            removeMailboxes: {GmailBoxes.trash, GmailBoxes.inbox}.difference(mapped.mailboxes),
          );
        }(),
    ]);
    for (final id in target.keys) {
      saved.remove(id);
    }
    await ctx.writeTrashedLabels(store, saved);
  }
}

/// Where a Gmail message is.
enum _Place { all, trash, junk }

/// A Gmail message found for an operation.
typedef _GmailHit = ({String id, List<String> labels, bool fromMe});
