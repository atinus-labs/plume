import 'dart:typed_data';

import 'address.dart';

/// Attachment metadata. The bytes are fetched lazily through the provider.
final class AttachmentInfo {
  const AttachmentInfo({
    required this.partId,
    this.providerId,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.contentId,
    this.isInline = false,
  });

  /// MIME part path within the message (e.g. `1.2`).
  final String partId;

  /// Provider handle used to download the bytes (Gmail attachmentId).
  final String? providerId;
  final String filename;
  final String mimeType;
  final int size;

  /// `Content-ID` without angle brackets, for `cid:` references in HTML.
  final String? contentId;
  final bool isInline;

  Map<String, Object?> toJson() => {
        'p': partId,
        if (providerId != null) 'i': providerId,
        'f': filename,
        'm': mimeType,
        's': size,
        if (contentId != null) 'c': contentId,
        if (isInline) 'in': true,
      };

  static AttachmentInfo fromJson(Map<String, Object?> j) => AttachmentInfo(
        partId: j['p']! as String,
        providerId: j['i'] as String?,
        filename: j['f']! as String,
        mimeType: j['m']! as String,
        size: (j['s']! as num).toInt(),
        contentId: j['c'] as String?,
        isInline: j['in'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is AttachmentInfo &&
      other.partId == partId &&
      other.providerId == providerId &&
      other.filename == filename &&
      other.size == size;

  @override
  int get hashCode => Object.hash(partId, providerId, filename, size);
}

/// Everything about a message except its body. This is what lists, threads
/// and notifications are built from, so it is synced eagerly.
final class Message {
  const Message({
    required this.accountId,
    required this.id,
    required this.threadId,
    required this.subject,
    this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.replyTo = const [],
    required this.date,
    this.snippet = '',
    this.isRead = true,
    this.isFlagged = false,
    this.isDraft = false,
    this.mailboxIds = const {},
    this.attachments = const [],
    this.messageIdHeader,
    this.inReplyTo,
    this.references = const [],
    this.listUnsubscribe,
    this.size = 0,
  });

  final String accountId;
  final String id;
  final String threadId;
  final String subject;
  final Address? from;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final List<Address> replyTo;
  final DateTime date;

  /// Plain-text preview, already decoded and whitespace-collapsed.
  final String snippet;
  final bool isRead;
  final bool isFlagged;
  final bool isDraft;

  /// Provider mailbox ids this message belongs to (labels or one folder).
  final Set<String> mailboxIds;
  final List<AttachmentInfo> attachments;

  /// The RFC 5322 `Message-ID` header, used for threading replies.
  final String? messageIdHeader;
  final String? inReplyTo;
  final List<String> references;

  /// Raw `List-Unsubscribe` header, when the sender provides one.
  final String? listUnsubscribe;
  final int size;

  bool get hasAttachments => attachments.any((a) => !a.isInline);

  Message copyWith({
    bool? isRead,
    bool? isFlagged,
    Set<String>? mailboxIds,
    List<AttachmentInfo>? attachments,
    String? snippet,
  }) =>
      Message(
        accountId: accountId,
        id: id,
        threadId: threadId,
        subject: subject,
        from: from,
        to: to,
        cc: cc,
        bcc: bcc,
        replyTo: replyTo,
        date: date,
        snippet: snippet ?? this.snippet,
        isRead: isRead ?? this.isRead,
        isFlagged: isFlagged ?? this.isFlagged,
        isDraft: isDraft,
        mailboxIds: mailboxIds ?? this.mailboxIds,
        attachments: attachments ?? this.attachments,
        messageIdHeader: messageIdHeader,
        inReplyTo: inReplyTo,
        references: references,
        listUnsubscribe: listUnsubscribe,
        size: size,
      );

  @override
  bool operator ==(Object other) =>
      other is Message &&
      other.accountId == accountId &&
      other.id == id &&
      other.isRead == isRead &&
      other.isFlagged == isFlagged &&
      other.date == date &&
      other.snippet == snippet &&
      _setEquals(other.mailboxIds, mailboxIds);

  @override
  int get hashCode => Object.hash(accountId, id, isRead, isFlagged, date, snippet, mailboxIds.length);

  @override
  String toString() => 'Message($accountId/$id thread=$threadId "$subject")';
}

/// A decoded message body.
final class MessageBody {
  const MessageBody({this.html, this.text, this.inlineParts = const {}});

  /// Sanitisation happens at render time, not here; this is the decoded
  /// original so that it can be re-rendered as rendering improves.
  final String? html;
  final String? text;

  /// Inline resources keyed by Content-ID, when the provider returned them
  /// with the body. Others are fetched on demand.
  final Map<String, Uint8List> inlineParts;

  bool get isEmpty => (html == null || html!.isEmpty) && (text == null || text!.isEmpty);
}

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
