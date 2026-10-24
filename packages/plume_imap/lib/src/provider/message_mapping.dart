import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';

import '../imap/imap_client.dart';
import '../imap/imap_fetch.dart';
import '../imap/uid_set.dart';
import 'folders.dart';
import 'ids.dart';

/// Header fields fetched for every message besides the ENVELOPE.
const headerFieldsSection = 'HEADER.FIELDS (REFERENCES LIST-UNSUBSCRIBE)';

/// FETCH items for message metadata.
List<String> headerItems({required bool gmail}) => [
      'UID',
      'FLAGS',
      'INTERNALDATE',
      'RFC822.SIZE',
      'ENVELOPE',
      'BODYSTRUCTURE',
      'BODY.PEEK[$headerFieldsSection]',
      if (gmail) ...['X-GM-MSGID', 'X-GM-THRID', 'X-GM-LABELS'],
    ];

/// Message id of a fetched message, or null if it cannot be named (no UID,
/// or a Gmail message without X-GM-MSGID).
String? messageIdOf(ImapFetch f, ImapFolder folder, int uidValidity, {required bool gmail}) {
  final uid = f.uid;
  if (uid == null) return null;
  return gmail ? f.gmailMessageId : ImapIds.message(folder.path, uidValidity, uid);
}

/// Builds a [Message] from FETCH data.
///
/// [mailboxIds] are the folder's mailbox (generic) or the mapped labels
/// plus categories (Gmail). The date is the Date header unless it is
/// missing or implausibly later than the arrival time (INTERNALDATE), which
/// keeps backdated imports in order and future-dated spam from sticking to
/// the top.
Message toMessage({
  required String accountId,
  required String id,
  required ImapFetch f,
  required Set<String> mailboxIds,
  required bool gmail,
  bool starred = false,
  bool draftLabel = false,
  String snippet = '',
}) {
  final e = f.envelope ?? const ImapEnvelope();
  final headers = headersOf(f.sections[headerFieldsSection]);
  final references = parseMessageIdList(headerValue(headers, 'References'));
  final flags = f.flags ?? const <String>{};
  final date = messageDate(f);
  final structure = f.structure;
  final threadId = gmail && f.gmailThreadId != null
      ? f.gmailThreadId!
      : ImapIds.thread(
          messageId: e.messageId,
          references: references,
          inReplyTo: e.inReplyTo,
          fallback: '${e.from.firstOrNull?.email.toLowerCase()}|${date.millisecondsSinceEpoch ~/ 1000}|${e.subject}',
        );
  final unsubscribe = headerValue(headers, 'List-Unsubscribe');
  return Message(
    accountId: accountId,
    id: id,
    threadId: threadId,
    subject: e.subject,
    from: e.from.firstOrNull ?? e.sender.firstOrNull,
    to: e.to,
    cc: e.cc,
    bcc: e.bcc,
    replyTo: e.replyTo,
    date: date,
    snippet: snippet,
    isRead: flags.contains(r'\Seen'),
    isFlagged: flags.contains(r'\Flagged') || starred,
    isDraft: flags.contains(r'\Draft') || draftLabel,
    mailboxIds: mailboxIds,
    attachments: structure == null ? const [] : attachmentsOfStructure(structure),
    messageIdHeader: e.messageId,
    inReplyTo: e.inReplyTo,
    references: references,
    listUnsubscribe: unsubscribe == null || unsubscribe.trim().isEmpty ? null : unfoldHeader(unsubscribe).trim(),
    size: f.size ?? 0,
  );
}

/// The date shown for a message: the Date header unless it is missing or
/// later than the arrival time (INTERNALDATE) by more than a day.
DateTime messageDate(ImapFetch f) {
  final internal = f.internalDate;
  final sent = f.envelope?.date;
  if (sent != null && (internal == null || !sent.isAfter(internal.add(const Duration(days: 1))))) return sent;
  return internal ?? sent ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Previews for [messages] from a partial fetch of each message's first
/// text part (2 KB of plain text, 8 KB of HTML, which carries more markup).
/// Messages are grouped by part so it takes one command per distinct part
/// id (usually two or three), pipelined. Keyed by UID.
Future<Map<int, String>> fetchPreviews(ImapClient client, List<ImapFetch> messages) async {
  final groups = <String, List<int>>{};
  final parts = <int, MimePart>{};
  for (final f in messages) {
    final uid = f.uid;
    final structure = f.structure;
    if (uid == null || structure == null) continue;
    final part = previewPartOf(structure);
    if (part == null) continue;
    final html = part.mimeType == 'text/html';
    groups.putIfAbsent('${part.partId}|${html ? 8192 : 2048}', () => []).add(uid);
    parts[uid] = part;
  }
  final results = await Future.wait([
    for (final MapEntry(key: key, value: uids) in groups.entries)
      () {
        final bar = key.indexOf('|');
        final section = key.substring(0, bar);
        final bytes = key.substring(bar + 1);
        return client.fetch(UidSet.of(uids).toString(), ['BODY.PEEK[$section]<0.$bytes>']);
      }(),
  ]);
  final out = <int, String>{};
  for (final r in results) {
    for (final f in r.messages) {
      final uid = f.uid;
      final part = uid == null ? null : parts[uid];
      if (part == null) continue;
      final raw = f.sections[part.partId.toUpperCase()];
      if (raw == null) continue;
      out[uid!] = previewOf(part, raw);
    }
  }
  return out;
}

/// Decodes a (possibly truncated) text part into a preview.
String previewOf(MimePart part, List<int> raw) {
  final decoded = decodeTransferEncoding(raw, part.header('Content-Transfer-Encoding'));
  final charset = HeaderValue.parse(part.header('Content-Type'))['charset'];
  final text = decodeCharset(decoded, charset);
  return part.mimeType == 'text/html' ? _cap(htmlToPreviewText(text)) : previewSnippet(text);
}

String _cap(String s, [int max = 200]) {
  if (s.length <= max) return s;
  final cut = s.lastIndexOf(' ', max);
  return s.substring(0, cut > max ~/ 2 ? cut : max).trimRight();
}

/// Gmail mailbox ids for a fetched All Mail message.
({Set<String> mailboxes, bool starred, bool draft}) gmailMembership(
  ImapFetch f,
  FolderLayout layout, {
  Set<String> categories = const {},
}) {
  final mapped = mapGmailLabels(f.gmailLabels ?? const [], layout);
  return (mailboxes: {...mapped.mailboxes, ...categories}, starred: mapped.starred, draft: mapped.draft);
}
