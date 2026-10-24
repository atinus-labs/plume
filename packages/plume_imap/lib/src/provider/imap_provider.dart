import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';

import '../imap/imap_client.dart';
import '../imap/imap_exception.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import '../mail_sender.dart';
import '../settings.dart';
import 'content.dart';
import 'context.dart';
import 'errors.dart';
import 'folder_state.dart';
import 'folders.dart';
import 'ids.dart';
import 'message_mapping.dart';
import 'operations.dart';
import 'push.dart';
import 'session_pool.dart';
import 'sync.dart';

/// [MailProvider] for any IMAP server, sending through a [MailSender]
/// (SMTP). Uses Gmail's IMAP extensions when the server has them.
///
/// See [ImapIds] for message and thread identity, [ImapSyncer] for the
/// sync algorithm and [ImapOperations] for how actions map onto IMAP.
///
/// Connections (at most three per account): one for sync and operations,
/// one for opening messages, one for IDLE. All are closed by [dispose].
final class ImapProvider implements MailProvider {
  ImapProvider({
    required this.account,
    required TokenSource tokens,
    required this._sender,
    this.config = const ImapSyncConfig(),
    MimeMessageBuilder? mimeBuilder,
    ImapOpener? opener,
    DateTime Function()? clock,
  })  : _tokens = tokens,
        _mime = mimeBuilder ?? MimeMessageBuilder(),
        _clock = clock ?? DateTime.now {
    MailServerSettings? settings;
    try {
      settings = MailServerSettings.fromJson(account.providerConfig);
    } on Object catch (e) {
      _invalid = 'The mail server settings of ${account.email} are incomplete or invalid ($e)';
    }
    if (settings != null) {
      final pool = ImapSessionPool(
        endpoint: settings.imap,
        username: settings.username,
        password: tokens.accessToken,
        config: config.client,
        idleTimeout: config.connectionIdleTimeout,
        opener: opener,
      );
      _ctx = ImapContext(account: account, settings: settings, pool: pool, config: config);
      _syncer = ImapSyncer(_ctx!);
      _content = ImapContent(_ctx!);
      _operations = ImapOperations(_ctx!);
      _push = ImapPush(_ctx!);
    }
  }

  static const kind = 'imap';

  @override
  final Account account;
  final ImapSyncConfig config;
  final TokenSource _tokens;
  final MailSender _sender;
  final MimeMessageBuilder _mime;
  final DateTime Function() _clock;
  String? _invalid;
  ImapContext? _ctx;
  late final ImapSyncer _syncer;
  late final ImapContent _content;
  late final ImapOperations _operations;
  late final ImapPush _push;

  /// Sent copies that could not be filed (IMAP unreachable right after
  /// sending); retried at the next syncs, at most [_sentCopyAttempts]
  /// times each.
  final _pendingSentCopies = <({Uint8List bytes, DateTime date, int attempts})>[];
  static const _sentCopyAttempts = 5;

  ImapContext get _context {
    final c = _ctx;
    if (c == null) throw PermanentException(_invalid ?? 'Invalid mail server settings');
    return c;
  }

  /// Whether the account is using Gmail's extensions (null until the first
  /// connection, then exact).
  bool? get isGmail => _ctx?.isGmail;

  @override
  ProviderCapabilities get capabilities {
    final gmail = _ctx?.looksLikeGmail ?? false;
    return ProviderCapabilities(
      labels: gmail,
      categories: gmail,
      serverSearch: true,
      serverDrafts: true,
      // IDLE, or NOOP polling on servers without it.
      push: _ctx != null,
    );
  }

  // Sync ------------------------------------------------------------------------

  @override
  Future<SyncResult> sync(SyncStore store) => _ready(() async {
        await _fileSentCopies();
        final result = await _syncer.sync(store);
        imapLog.fine('IMAP sync of ${account.id} done (${result.newMessages.length} new)');
        return result;
      });

  /// Runs [action] once the settings are known to be valid, mapping
  /// failures onto [MailException]s.
  Future<T> _ready<T>(Future<T> Function() action) => guarded(() {
        _context; // Throws PermanentException for invalid settings.
        return action();
      });

  @override
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, int pageSize = 50}) =>
      _ready(() => _syncer.loadMore(store, mailboxId: mailboxId, pageSize: pageSize));

  // Content -----------------------------------------------------------------------

  @override
  Future<void> fetchBodies(SyncStore store, List<String> messageIds) =>
      _ready(() => _content.fetchBodies(store, messageIds));

  @override
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment) =>
      _ready(() => _content.fetchAttachment(messageId, attachment));

  // Operations --------------------------------------------------------------------

  @override
  LocalMutation localEffect(MailOperation operation, List<Mailbox> mailboxes) {
    if (_ctx == null) return const LocalMutation();
    return _operations.localEffect(operation, mailboxes);
  }

  @override
  List<String> currentMessageIds(List<String> messageIds) {
    final ctx = _ctx;
    return ctx == null ? messageIds : [for (final id in messageIds) ctx.resolve(id)];
  }

  @override
  Future<void> execute(SyncStore store, MailOperation operation) =>
      _ready(() => _operations.execute(store, operation));

  // Sending -------------------------------------------------------------------------

  /// Sends through SMTP, then files a copy in Sent (unless the server does
  /// that itself, as Gmail does) and deletes the draft.
  ///
  /// Once the SMTP server accepted the message this never throws: an error
  /// would make the outbox send it again. Filing problems are logged, and a
  /// copy that could not be filed is retried at the next sync.
  @override
  Future<String> send(OutgoingMessage message) async {
    final ctx = _context;
    final recipients = <String>{
      for (final a in [...message.to, ...message.cc, ...message.bcc])
        if (a.email.trim().isNotEmpty) a.email.trim(),
    }.toList();
    if (recipients.isEmpty) throw const PermanentException('The message has no recipients');
    final password = await _tokens.accessToken();
    final date = _clock();
    // The filed copy keeps Bcc (the sender should see whom they Bcc'd);
    // what goes over SMTP must not reveal it.
    final copy = _mime.build(message, date: date);
    final wire = _mime.build(message, messageId: copy.messageId, date: date, includeBcc: false);
    await _sender.send(
      endpoint: ctx.settings.smtp,
      username: ctx.settings.smtpUsername,
      password: password,
      from: account.email,
      recipients: recipients,
      data: wire.bytes,
    );

    var id = copy.messageId;
    try {
      if (ctx.settings.saveSentCopy && !await _isGmailForSend(ctx)) {
        id = await _fileSentCopy(copy.bytes, date) ?? id;
      }
    } on Object catch (e) {
      final error = toMailException(e);
      if (error is TransientException) {
        // Offline right after sending: file it with the next sync.
        imapLog.warning('Sent, but could not file a copy in Sent yet: ${error.message}');
        if (_pendingSentCopies.length < 20) _pendingSentCopies.add((bytes: copy.bytes, date: date, attempts: 1));
      } else {
        imapLog.warning('Sent, but the server refused the copy for Sent: ${error.message}');
      }
    }
    final draftId = message.draftId;
    if (draftId != null) {
      try {
        await deleteDraft(draftId);
      } on Object catch (e) {
        imapLog.warning('Sent, but could not delete the draft: $e');
      }
    }
    return id;
  }

  /// Gmail files sent mail itself; appending would make a second copy.
  Future<bool> _isGmailForSend(ImapContext ctx) async {
    final known = ctx.isGmail;
    if (known != null) return known;
    try {
      return await ctx.pool.run(ImapSlot.primary, (c) async => c.isGmail);
    } on Object {
      return ctx.looksLikeGmail;
    }
  }

  /// APPENDs [bytes] to Sent as read. Returns the new message id.
  Future<String?> _fileSentCopy(Uint8List bytes, DateTime date) => _context.pool.run(ImapSlot.primary, (c) async {
        final ctx = _context;
        final layout = await ctx.ensureLayout(c);
        if (layout.gmail) return null;
        final sent = layout.byRole(MailboxRole.sent)?.path ?? await _createFolder(c, ctx, 'Sent');
        final appended = await c.append(sent, bytes, flags: const [r'\Seen'], date: date);
        return appended == null ? null : ImapIds.message(sent, appended.uidValidity, appended.uid);
      });

  /// Files queued Sent copies. Never fails the sync: a copy that keeps
  /// failing is dropped (logged) after [_sentCopyAttempts] attempts.
  Future<void> _fileSentCopies() async {
    while (_pendingSentCopies.isNotEmpty) {
      final next = _pendingSentCopies.first;
      try {
        await _fileSentCopy(next.bytes, next.date);
        _pendingSentCopies.removeAt(0);
      } on Object catch (e) {
        final error = toMailException(e);
        _pendingSentCopies.removeAt(0);
        if (error is TransientException && next.attempts + 1 < _sentCopyAttempts) {
          // Try again with the next sync; the sync itself goes ahead.
          _pendingSentCopies.insert(0, (bytes: next.bytes, date: next.date, attempts: next.attempts + 1));
          imapLog.fine('Filing a sent copy failed again (${error.message}); will retry');
          return;
        }
        imapLog.warning('Giving up filing a sent copy after ${next.attempts + 1} attempts: ${error.message}');
      }
    }
  }

  Future<String> _createFolder(ImapClient c, ImapContext ctx, String name) async {
    final path = ctx.newFolderPath(name);
    await c.create(path);
    try {
      await c.subscribe(path);
    } on ImapCommandException {
      // Optional.
    }
    ctx.layout = null;
    return path;
  }

  // Drafts --------------------------------------------------------------------------

  /// Appends the draft to Drafts (`\Draft \Seen`) and removes the previous
  /// version. The draft id is the appended message's id.
  @override
  Future<String> saveDraft(OutgoingMessage message) => guarded(() async {
        final ctx = _context;
        final built = _mime.build(message, date: _clock());
        final id = await ctx.pool.run(ImapSlot.primary, (c) async {
          final layout = await ctx.ensureLayout(c);
          final drafts = layout.byRole(MailboxRole.drafts)?.path ?? await _createFolder(c, ctx, 'Drafts');
          final appended = await c.append(drafts, built.bytes, flags: const [r'\Draft', r'\Seen'], date: _clock());
          final sel = await c.select(drafts);
          var uid = appended?.uid;
          if (uid == null) {
            final hits = await c.search(['HEADER Message-ID ', ...c.searchString(built.messageId)]);
            uid = hits.ids.isEmpty ? null : hits.ids.max;
          }
          if (uid == null) return built.messageId;
          if (layout.gmail) {
            final f = await c.fetch('$uid', ['UID', 'X-GM-MSGID']);
            return f.messages.firstOrNull?.gmailMessageId ?? built.messageId;
          }
          return ImapIds.message(drafts, appended?.uidValidity ?? sel.uidValidity ?? 0, uid);
        });
        final previous = message.draftId;
        if (previous != null && previous != id) {
          try {
            await deleteDraft(previous);
          } on MailException catch (e) {
            imapLog.warning('Saved the draft, but the previous version could not be deleted: ${e.message}');
          }
        }
        return id;
      });

  @override
  Future<void> deleteDraft(String draftId) => guarded(() async {
        final ctx = _context;
        await ctx.pool.run(ImapSlot.primary, (c) async {
          final layout = await ctx.ensureLayout(c);
          final drafts = layout.byRole(MailboxRole.drafts)?.path;
          final loc = layout.gmail ? null : ctx.locate(draftId);
          final path = loc?.path ?? drafts;
          if (path == null) return;
          final sel = await c.select(path);
          UidSet uids;
          if (loc != null) {
            if (sel.uidValidity != loc.uidValidity) return; // Gone already.
            uids = UidSet.of([loc.uid]);
          } else if (layout.gmail && !draftId.startsWith('<')) {
            uids = UidSet.of((await ImapContext.searchGmailIds(c, [draftId])).values);
          } else {
            uids = (await c.search(['HEADER Message-ID ', ...c.searchString(draftId)])).ids;
          }
          if (uids.isEmpty) return;
          if (layout.gmail) {
            // Expunging from Drafts only removes a label on Gmail; deleting
            // for good means through Trash.
            final trash = layout.byRole(MailboxRole.trash)?.path;
            if (trash == null) return;
            final moved = await c.move(uids, trash);
            if (moved == null || moved.mapping.isEmpty) return;
            await c.select(trash);
            final inTrash = UidSet.of(moved.mapping.values);
            await c.store(inTrash, '+FLAGS.SILENT', const [r'\Deleted']);
            await c.expunge(inTrash);
          } else {
            await c.store(uids, '+FLAGS.SILENT', const [r'\Deleted']);
            await c.expunge(uids);
          }
        });
      });

  // Search --------------------------------------------------------------------------

  /// Server-side search: Gmail search syntax (X-GM-RAW) over All Mail on
  /// Gmail; elsewhere a TEXT search (headers and body) of INBOX, Archive,
  /// Sent and the user's folders. Results are paged newest first across
  /// folders; the page token holds, per folder, the UID below which the
  /// next page continues.
  @override
  Future<SearchPage> search(SyncStore store, String query, {String? pageToken}) => guarded(() async {
        final ctx = _context;
        final trimmed = query.trim();
        if (trimmed.isEmpty) return const SearchPage(threadIds: []);
        final cursors = _decodeCursors(pageToken);
        final pageSize = config.searchPageSize;
        return ctx.pool.run(ImapSlot.primary, (c) async {
          final layout = await ctx.ensureLayout(c);
          final folders = _searchFolders(layout);
          final criteria = layout.gmail
              ? <Object>['X-GM-RAW ', ...c.searchString(trimmed)]
              : <Object>['TEXT ', ...c.searchString(trimmed)];
          final candidates = <({ImapFolder folder, ImapFetch fetch, int uidValidity, FolderState? state})>[];
          final remaining = <String, UidSet>{};
          for (final folder in folders) {
            final sel = await ctx.selectRw(c, folder.path);
            final hits = await c.search(criteria, needsCharset: ImapClient.isNonAscii(trimmed));
            final below = cursors[folder.path];
            final open = below == null ? hits.ids : hits.ids.difference(UidSet.range(below, 1 << 62));
            remaining[folder.path] = open;
            final top = open.newest(pageSize);
            if (top.isEmpty) continue;
            final f = await c.fetch(top.toString(), headerItems(gmail: layout.gmail));
            final st = await ctx.readFolder(store, folder.path);
            for (final m in f.messages) {
              if (m.envelope == null || !top.contains(m.uid!)) continue; // unsolicited
              candidates.add((folder: folder, fetch: m, uidValidity: sel.uidValidity ?? 0, state: st));
            }
          }
          candidates.sort((a, b) => messageDate(b.fetch).compareTo(messageDate(a.fetch)));
          final page = candidates.take(pageSize).toList();

          // Store what was not stored yet; remember it like synced mail so
          // deletions and flag changes reach it.
          final messages = <Message>[];
          final byFolder = <ImapFolder, List<ImapFetch>>{};
          for (final p in page) {
            byFolder.putIfAbsent(p.folder, () => []).add(p.fetch);
          }
          for (final MapEntry(key: folder, value: fetches) in byFolder.entries) {
            await ctx.selectRw(c, folder.path);
            final previews = await fetchPreviews(c, fetches);
            final st = await ctx.readFolder(store, folder.path);
            final uv = c.selected?.uidValidity ?? 0;
            for (final f in fetches) {
              final id = messageIdOf(f, folder, uv, gmail: layout.gmail);
              if (id == null) continue;
              messages.add(_syncer.buildMessage(f, folder, layout, id: id, snippet: previews[f.uid!] ?? ''));
            }
            if (st != null && st.uidValidity == uv) {
              st.noteAll([
                for (final f in fetches)
                  (
                    uid: f.uid!,
                    seen: f.flags?.contains(r'\Seen') ?? true,
                    flagged: f.flags?.contains(r'\Flagged') ?? false,
                    gmailId: f.gmailMessageId,
                  ),
              ]);
              await ctx.writeFolder(store, folder.path, st);
            }
          }
          final known = await store.knownMessageIds(_context.accountId, messages.map((m) => m.id));
          await store.upsertMessages(_context.accountId, [for (final m in messages) if (!known.contains(m.id)) m]);

          // Next page: each folder continues below the oldest UID taken.
          final next = Map<String, int>.of(cursors);
          var more = false;
          for (final folder in folders) {
            final taken = [for (final p in page) if (p.folder == folder) p.fetch.uid!];
            if (taken.isNotEmpty) next[folder.path] = taken.reduce((a, b) => a < b ? a : b);
            final open = remaining[folder.path] ?? UidSet.empty;
            final cursor = next[folder.path];
            if ((cursor == null ? open : open.difference(UidSet.range(cursor, 1 << 62))).isNotEmpty) more = true;
          }
          final threads = <String>[];
          final seen = <String>{};
          final byId = {for (final m in messages) m.id: m};
          for (final p in page) {
            final id = messageIdOf(p.fetch, p.folder, p.uidValidity, gmail: layout.gmail);
            final m = id == null ? null : byId[id];
            if (m != null && seen.add(m.threadId)) threads.add(m.threadId);
          }
          return SearchPage(threadIds: threads, nextPageToken: more ? jsonEncode(next) : null);
        });
      });

  List<ImapFolder> _searchFolders(FolderLayout layout) {
    if (layout.gmail) return [?layout.gmailAllMail];
    final main = [
      for (final role in [MailboxRole.inbox, MailboxRole.archive, MailboxRole.sent]) ?layout.byRole(role),
    ];
    final users = [for (final f in layout.synced) if (f.role == null) f];
    return [...main, ...users].take(config.searchFolderLimit).toList();
  }

  static Map<String, int> _decodeCursors(String? token) {
    if (token == null || token.isEmpty) return {};
    try {
      return {
        for (final e in (jsonDecode(token) as Map).cast<String, Object?>().entries)
          if (e.value is num) e.key: (e.value! as num).toInt(),
      };
    } on Object {
      return {};
    }
  }

  // Push and lifecycle --------------------------------------------------------------

  @override
  Stream<void> watchChanges() {
    if (_ctx == null) return Stream.error(PermanentException(_invalid ?? 'Invalid mail server settings'));
    return _push.watch();
  }

  @override
  Future<void> dispose() async {
    if (_ctx == null) return;
    _push.close();
    await _ctx!.pool.close();
  }
}
