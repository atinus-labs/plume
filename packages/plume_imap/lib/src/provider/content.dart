import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';

import '../imap/imap_client.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import 'context.dart';
import 'message_mapping.dart';
import 'session_pool.dart';

/// Downloads message bodies and attachments on the fetch connection.
final class ImapContent {
  ImapContent(this.ctx);

  final ImapContext ctx;

  String get _accountId => ctx.accountId;

  /// Resolves message ids to folder locations. Unresolvable ids (folder
  /// gone, Gmail id not found) are returned separately.
  Future<({Map<String, Map<int, String>> byFolder, List<String> unknown})> _locate(
    ImapClient c,
    List<String> ids, {
    bool useIndex = true,
  }) async {
    final byFolder = <String, Map<int, String>>{};
    final unknown = <String>[];
    final layout = await ctx.ensureLayout(c);
    if (!layout.gmail) {
      for (final id in ids) {
        final current = ctx.resolve(id);
        final loc = ctx.locate(current);
        if (loc == null) {
          unknown.add(id);
        } else {
          byFolder.putIfAbsent(loc.path, () => {})[loc.uid] = current;
        }
      }
      return (byFolder: byFolder, unknown: unknown);
    }
    final missing = <String>[];
    for (final id in ids) {
      final loc = useIndex ? ctx.gmailLocation(id) : null;
      if (loc == null) {
        missing.add(id);
      } else {
        byFolder.putIfAbsent(loc.path, () => {})[loc.uid] = id;
      }
    }
    // Not indexed (search results, or before the first sync): look the ids
    // up in All Mail, then Trash and Spam.
    for (final f in layout.synced) {
      if (missing.isEmpty) break;
      await c.select(f.path, readOnly: true);
      final found = await ImapContext.searchGmailIds(c, missing);
      found.forEach((id, uid) => byFolder.putIfAbsent(f.path, () => {})[uid] = id);
      missing.removeWhere(found.containsKey);
    }
    unknown.addAll(missing);
    return (byFolder: byFolder, unknown: unknown);
  }

  /// Downloads, decodes and stores the bodies of [messageIds]. Small
  /// messages are fetched whole (inline images included); for large ones
  /// only the text parts are downloaded, so a 20 MB attachment is not
  /// fetched just to show three lines of text. Messages that no longer
  /// exist are removed from the store.
  Future<void> fetchBodies(SyncStore store, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await ctx.loadRenames(store);
    if (ctx.gmailMode ?? ctx.looksLikeGmail) await ctx.loadGmailIndex(store);
    final results = await ctx.pool.run(ImapSlot.fetch, (c) async {
      final contents = <String, (ExtractedContent, ImapFetch, String path)>{};
      final gone = <String>[];
      var located = await _locate(c, messageIds);
      gone.addAll(located.unknown);
      await _fetchLocated(c, located.byFolder, contents, gone);
      if (gone.isNotEmpty && (ctx.layout?.gmail ?? false)) {
        // The index may be stale (moved to Trash on the web): look again
        // before calling anything gone.
        final retry = [...gone];
        gone.clear();
        located = await _locate(c, retry, useIndex: false);
        gone.addAll(located.unknown);
        await _fetchLocated(c, located.byFolder, contents, gone);
      }
      return (contents: contents, gone: gone);
    });

    final gmail = ctx.layout?.gmail ?? false;
    // Attachments are known from BODYSTRUCTURE already; with the HTML in
    // hand, inline images are told apart exactly, so refresh them.
    final threadOf = <String, String>{
      for (final MapEntry(key: id, value: (_, f, _)) in results.contents.entries)
        id: toMessage(accountId: _accountId, id: id, f: f, mailboxIds: const {}, gmail: gmail).threadId,
    };
    final stored = {
      for (final m in await store.messagesInThreads(_accountId, threadOf.values.toSet())) m.id: m,
    };
    final updates = <Message>[];
    for (final MapEntry(key: id, value: (content, _, _)) in results.contents.entries) {
      final m = stored[id];
      if (m == null) continue;
      if (!_sameAttachments(m.attachments, content.attachments)) updates.add(m.copyWith(attachments: content.attachments));
    }
    await store.transaction(() async {
      if (results.gone.isNotEmpty) await store.deleteMessages(_accountId, results.gone);
      if (updates.isNotEmpty) await store.upsertMessages(_accountId, updates);
      for (final MapEntry(key: id, value: (content, _, _)) in results.contents.entries) {
        await store.saveBody(_accountId, id, content.toBody());
      }
    });
  }

  /// Fetches bodies of [byFolder] (path → UID → id) into [contents];
  /// messages not found are added to [gone].
  Future<void> _fetchLocated(
    ImapClient c,
    Map<String, Map<int, String>> byFolder,
    Map<String, (ExtractedContent, ImapFetch, String)> contents,
    List<String> gone,
  ) async {
    for (final MapEntry(key: path, value: uids) in byFolder.entries) {
      final sel = await c.select(path, readOnly: true);
      final wanted = <int, String>{};
      uids.forEach((uid, id) {
        final loc = ctx.locate(id);
        // A changed UIDVALIDITY means the id no longer names anything.
        if (loc != null && loc.uidValidity != sel.uidValidity) {
          gone.add(id);
        } else {
          wanted[uid] = id;
        }
      });
      if (wanted.isEmpty) continue;
      final got = await _fetchFolder(c, UidSet.of(wanted.keys));
      for (final MapEntry(key: uid, value: id) in wanted.entries) {
        final r = got[uid];
        if (r == null) {
          gone.add(id);
        } else {
          contents[id] = (r.$1, r.$2, path);
        }
      }
    }
  }

  static bool _sameAttachments(List<AttachmentInfo> a, List<AttachmentInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i] || a[i].isInline != b[i].isInline || a[i].contentId != b[i].contentId) return false;
    }
    return true;
  }

  /// Bodies of [uids] in the selected folder, keyed by UID.
  Future<Map<int, (ExtractedContent, ImapFetch)>> _fetchFolder(ImapClient c, UidSet uids) async {
    final fetched = await c.fetch(uids.toString(), [
      'UID',
      'RFC822.SIZE',
      'BODYSTRUCTURE',
      'ENVELOPE',
      'INTERNALDATE',
      'BODY.PEEK[$headerFieldsSection]',
      if (ctx.gmailMode ?? false) 'X-GM-THRID',
    ]);
    // Only what was asked for (not unsolicited flag updates).
    final requested = [for (final f in fetched.messages) if (uids.contains(f.uid!) && f.size != null) f];
    final out = <int, (ExtractedContent, ImapFetch)>{};
    final small = <ImapFetch>[];
    final large = <ImapFetch>[];
    for (final f in requested) {
      ((f.size ?? 0) <= ctx.config.fullBodyLimit || f.structure == null ? small : large).add(f);
    }
    // Whole messages, in groups of at most ~8 MB per command.
    var group = <ImapFetch>[];
    var groupSize = 0;
    Future<void> flush() async {
      if (group.isEmpty) return;
      final r = await c.fetch(UidSet.of([for (final f in group) f.uid!]).toString(), ['UID', 'BODY.PEEK[]']);
      final byUid = {for (final g in group) g.uid!: g};
      for (final f in r.messages) {
        final raw = f.sections[''];
        final m = byUid[f.uid];
        if (raw == null || m == null) continue;
        out[f.uid!] = (extractContent(parseMimeMessage(raw)), m);
      }
      group = [];
      groupSize = 0;
    }

    for (final f in small) {
      group.add(f);
      groupSize += f.size ?? 0;
      if (groupSize > 8 << 20 || group.length >= 50) await flush();
    }
    await flush();

    // Large messages: text parts only.
    for (final f in large) {
      final structure = f.structure!;
      final first = extractContent(structure);
      final parts = first.unresolvedBodyParts;
      if (parts.isEmpty) {
        out[f.uid!] = (first, f);
        continue;
      }
      final r = await c.fetch('${f.uid}', ['UID', for (final p in parts) 'BODY.PEEK[${p.partId}]']);
      final resolved = <String, List<int>>{};
      for (final got in r.messages) {
        for (final p in parts) {
          final raw = got.sections[p.partId.toUpperCase()];
          if (raw != null) resolved[p.partId] = decodeTransferEncoding(raw, p.header('Content-Transfer-Encoding'));
        }
      }
      out[f.uid!] = (extractContent(structure, resolved: resolved), f);
    }
    return out;
  }

  /// Downloads one attachment by its IMAP part number.
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment) =>
      ctx.pool.run(ImapSlot.fetch, (c) async {
        final located = await _locate(c, [messageId]);
        if (located.byFolder.isEmpty) throw NotFoundException('Message $messageId no longer exists');
        final path = located.byFolder.keys.first;
        final uid = located.byFolder[path]!.keys.first;
        final sel = await c.select(path, readOnly: true);
        final loc = ctx.locate(messageId);
        if (loc != null && loc.uidValidity != sel.uidValidity) {
          throw NotFoundException('Message $messageId no longer exists');
        }
        final section = attachment.partId;
        final r = await c.fetch('$uid', ['UID', 'BODYSTRUCTURE', 'BODY.PEEK[$section]']);
        final f = r.messages.where((m) => m.uid == uid).firstOrNull;
        final raw = f?.sections[section.toUpperCase()];
        if (f == null || raw == null) throw NotFoundException('Attachment ${attachment.partId} of $messageId not found');
        final part = f.structure?.allParts.where((p) => p.partId == section).firstOrNull;
        return decodeTransferEncoding(raw, part?.header('Content-Transfer-Encoding'));
      });
}
