import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:plume_core/plume_core.dart';

// Addresses ------------------------------------------------------------------

String? encodeAddress(Address? a) => a == null ? null : jsonEncode(a.toJson());

String? encodeAddresses(List<Address> list) => list.isEmpty ? null : jsonEncode([for (final a in list) a.toJson()]);

Address? decodeAddress(String? json) {
  if (json == null || json.isEmpty) return null;
  final decoded = jsonDecode(json);
  return decoded is Map ? _addressFrom(decoded) : null;
}

List<Address> decodeAddresses(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final a in decoded)
      if (a is Map && a['e'] is String) _addressFrom(a),
  ];
}

Address _addressFrom(Map<dynamic, dynamic> m) => Address(m['e'] as String? ?? '', m['n'] as String?);

List<String> decodeStringList(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  return decoded is List
      ? [
          for (final v in decoded)
            if (v is String) v,
        ]
      : const [];
}

Set<String> decodeStringSet(String? json) {
  if (json == null || json.isEmpty || json == '[]') return const {};
  final decoded = jsonDecode(json);
  return decoded is List
      ? {
          for (final v in decoded)
            if (v is String) v,
        }
      : const {};
}

T? enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

DateTime fromEpochMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

// Messages -------------------------------------------------------------------

/// Columns of `messages` (aliased `m`) needed to build a [Message], plus its
/// mailbox ids as a JSON array.
const messageColumns =
    'm.account_id, m.id, m.thread_id, m.subject, m.from_addr, m.to_addrs, m.cc_addrs, '
    'm.bcc_addrs, m.reply_to_addrs, m.date, m.snippet, m.is_read, m.is_flagged, m.is_draft, '
    'm.attachments, m.message_id_header, m.in_reply_to, m.refs, m.list_unsubscribe, m.size, '
    '(SELECT json_group_array(mm.mailbox_id) FROM message_mailboxes mm '
    'WHERE mm.account_id = m.account_id AND mm.message_id = m.id) AS mailbox_ids';

Message messageFromRow(QueryRow r) => Message(
  accountId: r.read<String>('account_id'),
  id: r.read<String>('id'),
  threadId: r.read<String>('thread_id'),
  subject: r.read<String>('subject'),
  from: decodeAddress(r.readNullable<String>('from_addr')),
  to: decodeAddresses(r.readNullable<String>('to_addrs')),
  cc: decodeAddresses(r.readNullable<String>('cc_addrs')),
  bcc: decodeAddresses(r.readNullable<String>('bcc_addrs')),
  replyTo: decodeAddresses(r.readNullable<String>('reply_to_addrs')),
  date: fromEpochMs(r.read<int>('date')),
  snippet: r.read<String>('snippet'),
  isRead: r.read<bool>('is_read'),
  isFlagged: r.read<bool>('is_flagged'),
  isDraft: r.read<bool>('is_draft'),
  mailboxIds: decodeStringSet(r.readNullable<String>('mailbox_ids')),
  attachments: _decodeAttachments(r.readNullable<String>('attachments')),
  messageIdHeader: r.readNullable<String>('message_id_header'),
  inReplyTo: r.readNullable<String>('in_reply_to'),
  references: decodeStringList(r.readNullable<String>('refs')),
  listUnsubscribe: r.readNullable<String>('list_unsubscribe'),
  size: r.read<int>('size'),
);

List<AttachmentInfo> _decodeAttachments(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final a in decoded)
      if (a is Map) AttachmentInfo.fromJson(a.cast<String, Object?>()),
  ];
}

/// A [Message] encoded into the column values of `messages`.
final class EncodedMessage {
  EncodedMessage(this.message)
    : from = encodeAddress(message.from),
      to = encodeAddresses(message.to),
      cc = encodeAddresses(message.cc),
      bcc = encodeAddresses(message.bcc);

  final Message message;
  final String? from;
  final String? to;
  final String? cc;
  final String? bcc;

  /// Values for [upsertMessageSql], in order.
  List<Object?> args(String accountId) {
    final m = message;
    return [
      accountId,
      m.id,
      m.threadId,
      m.subject,
      from,
      to,
      cc,
      bcc,
      encodeAddresses(m.replyTo),
      m.date.millisecondsSinceEpoch,
      m.snippet,
      m.isRead ? 1 : 0,
      m.isFlagged ? 1 : 0,
      m.isDraft ? 1 : 0,
      m.hasAttachments ? 1 : 0,
      m.attachments.isEmpty ? null : jsonEncode([for (final a in m.attachments) a.toJson()]),
      m.messageIdHeader,
      m.inReplyTo,
      m.references.isEmpty ? null : jsonEncode(m.references),
      m.listUnsubscribe,
      m.size,
    ];
  }

  /// Whether the full-text indexed fields differ from a stored row.
  bool indexedTextDiffers(QueryRow old) =>
      old.read<String>('subject') != message.subject ||
      old.read<String>('snippet') != message.snippet ||
      old.readNullable<String>('from_addr') != from ||
      old.readNullable<String>('to_addrs') != to ||
      old.readNullable<String>('cc_addrs') != cc ||
      old.readNullable<String>('bcc_addrs') != bcc;
}

const upsertMessageSql = '''
INSERT INTO messages (account_id, id, thread_id, subject, from_addr, to_addrs, cc_addrs, bcc_addrs,
  reply_to_addrs, date, snippet, is_read, is_flagged, is_draft, has_attachments, attachments,
  message_id_header, in_reply_to, refs, list_unsubscribe, size)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)
ON CONFLICT (account_id, id) DO UPDATE SET
  thread_id = excluded.thread_id, subject = excluded.subject, from_addr = excluded.from_addr,
  to_addrs = excluded.to_addrs, cc_addrs = excluded.cc_addrs, bcc_addrs = excluded.bcc_addrs,
  reply_to_addrs = excluded.reply_to_addrs, date = excluded.date, snippet = excluded.snippet,
  is_read = excluded.is_read, is_flagged = excluded.is_flagged, is_draft = excluded.is_draft,
  has_attachments = excluded.has_attachments, attachments = excluded.attachments,
  message_id_header = excluded.message_id_header, in_reply_to = excluded.in_reply_to,
  refs = excluded.refs, list_unsubscribe = excluded.list_unsubscribe, size = excluded.size''';

// Threads --------------------------------------------------------------------

/// Columns of `threads` (aliased `t`) needed to build a [ThreadSummary].
const threadColumns =
    't.account_id, t.id, t.subject, t.snippet, t.last_date, t.message_count, '
    't.unread_count, t.flagged, t.has_attachments, t.draft_count, t.participants, t.mailbox_ids';

ThreadSummary threadFromRow(QueryRow r, {String prefix = ''}) => ThreadSummary(
  accountId: r.read<String>('${prefix}account_id'),
  id: r.read<String>(prefix.isEmpty ? 'id' : '${prefix}id'),
  subject: r.read<String>('${prefix}subject'),
  snippet: r.read<String>('${prefix}snippet'),
  lastDate: fromEpochMs(r.read<int>('${prefix}last_date')),
  messageCount: r.read<int>('${prefix}message_count'),
  unreadCount: r.read<int>('${prefix}unread_count'),
  isFlagged: r.read<bool>('${prefix}flagged'),
  hasAttachments: r.read<bool>('${prefix}has_attachments'),
  draftCount: r.read<int>('${prefix}draft_count'),
  participants: decodeAddresses(r.read<String>('${prefix}participants')),
  mailboxIds: decodeStringSet(r.read<String>('${prefix}mailbox_ids')),
);

// Accounts and mailboxes -----------------------------------------------------

Account accountFromRow(QueryRow r) => Account(
  id: r.read<String>('id'),
  provider: r.read<String>('provider'),
  email: r.read<String>('email'),
  displayName: r.read<String>('display_name'),
  avatarUrl: r.readNullable<String>('avatar_url'),
  color: r.read<int>('color'),
  sortOrder: r.read<int>('sort_order'),
  status: enumByName(AccountStatus.values, r.read<String>('status')) ?? AccountStatus.ok,
  signature: r.readNullable<String>('signature'),
  providerConfig: _decodeConfig(r.readNullable<String>('provider_config')),
);

Map<String, Object?> _decodeConfig(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  } on FormatException {
    return const {};
  }
}

Mailbox mailboxFromRow(QueryRow r) => Mailbox(
  accountId: r.read<String>('account_id'),
  id: r.read<String>('id'),
  name: r.read<String>('name'),
  role: enumByName(MailboxRole.values, r.readNullable<String>('role')),
  category: enumByName(MailCategory.values, r.readNullable<String>('category')),
  kind: enumByName(MailboxKind.values, r.read<String>('kind')) ?? MailboxKind.user,
  parentId: r.readNullable<String>('parent_id'),
  color: r.readNullable<int>('color'),
  unreadThreads: r.read<int>('unread_threads'),
  totalThreads: r.read<int>('total_threads'),
  sortOrder: r.read<int>('sort_order'),
  hidden: r.read<bool>('hidden'),
);

// Outgoing messages ----------------------------------------------------------

/// JSON codec for [OutgoingMessage], used to persist the outbox. Attachment
/// bytes are base64 encoded.
abstract final class OutgoingMessageCodec {
  static const _version = 1;

  static String encode(OutgoingMessage m) => jsonEncode(toJson(m));

  static OutgoingMessage decode(String json) => fromJson((jsonDecode(json) as Map).cast<String, Object?>());

  static Map<String, Object?> toJson(OutgoingMessage m) => {
    'v': _version,
    'account': m.accountId,
    'from': m.from.toJson(),
    if (m.to.isNotEmpty) 'to': [for (final a in m.to) a.toJson()],
    if (m.cc.isNotEmpty) 'cc': [for (final a in m.cc) a.toJson()],
    if (m.bcc.isNotEmpty) 'bcc': [for (final a in m.bcc) a.toJson()],
    'subject': m.subject,
    'text': m.textBody,
    if (m.htmlBody != null) 'html': m.htmlBody,
    if (m.attachments.isNotEmpty)
      'attachments': [
        for (final a in m.attachments)
          {'f': a.filename, 'm': a.mimeType, 'b': base64Encode(a.bytes), if (a.contentId != null) 'c': a.contentId},
      ],
    if (m.threadId != null) 'thread': m.threadId,
    if (m.inReplyTo != null) 'inReplyTo': m.inReplyTo,
    if (m.references.isNotEmpty) 'refs': m.references,
    if (m.draftId != null) 'draft': m.draftId,
  };

  static OutgoingMessage fromJson(Map<String, Object?> j) {
    List<Address> addresses(String key) => [
      for (final a in (j[key] as List?) ?? const <Object?>[]) _addressFrom(a! as Map),
    ];
    return OutgoingMessage(
      accountId: j['account']! as String,
      from: _addressFrom(j['from']! as Map),
      to: addresses('to'),
      cc: addresses('cc'),
      bcc: addresses('bcc'),
      subject: j['subject'] as String? ?? '',
      textBody: j['text'] as String? ?? '',
      htmlBody: j['html'] as String?,
      attachments: [
        for (final a in (j['attachments'] as List?) ?? const <Object?>[])
          if (a is Map)
            OutgoingAttachment(
              filename: a['f']! as String,
              mimeType: a['m']! as String,
              bytes: base64Decode(a['b']! as String),
              contentId: a['c'] as String?,
            ),
      ],
      threadId: j['thread'] as String?,
      inReplyTo: j['inReplyTo'] as String?,
      references: [for (final r in (j['refs'] as List?) ?? const <Object?>[]) r! as String],
      draftId: j['draft'] as String?,
    );
  }
}
