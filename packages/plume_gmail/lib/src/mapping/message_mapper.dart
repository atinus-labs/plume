import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';

import '../api/gmail_types.dart';
import 'label_mapper.dart';

/// Maps Gmail messages onto Plume [Message]s.
abstract final class GmailMessageMapper {
  /// Maps a `format=metadata` or `format=full` message.
  ///
  /// [content] supplies attachments when the message was fetched in full;
  /// metadata responses carry no MIME structure, so attachments are then
  /// empty until the body is fetched. UNREAD and STARRED become [Message.isRead]
  /// and [Message.isFlagged] and are not mailbox ids.
  static Message toMessage(String accountId, GmailMessage gm, {ExtractedContent? content}) {
    final p = gm.payload;
    String? header(String name) => p?.header(name);
    final labels = gm.labelIds.toSet();
    return Message(
      accountId: accountId,
      id: gm.id,
      threadId: gm.threadId,
      subject: decodeHeaderValue(header('Subject') ?? '').trim(),
      from: parseAddressHeader(header('From')).firstOrNull,
      to: parseAddressHeader(header('To')),
      cc: parseAddressHeader(header('Cc')),
      bcc: parseAddressHeader(header('Bcc')),
      replyTo: parseAddressHeader(header('Reply-To')),
      date: messageDate(gm),
      snippet: cleanSnippet(gm.snippet),
      isRead: !labels.contains(GmailLabels.unread),
      isFlagged: labels.contains(GmailLabels.starred),
      isDraft: labels.contains(GmailLabels.draft),
      mailboxIds: labels.difference(GmailLabels.keywordLabels),
      attachments: content?.attachments ?? const [],
      messageIdHeader: parseMessageIdHeader(header('Message-ID')),
      inReplyTo: parseMessageIdHeader(header('In-Reply-To')),
      references: parseMessageIdList(header('References')),
      listUnsubscribe: _trimmedOrNull(header('List-Unsubscribe')),
      size: gm.sizeEstimate,
    );
  }

  /// Gmail's receive time (`internalDate`), falling back to the `Date`
  /// header, which senders control and which is often wrong.
  static DateTime messageDate(GmailMessage gm) {
    final internal = gm.internalDate;
    if (internal != null && internal > 0) return DateTime.fromMillisecondsSinceEpoch(internal, isUtc: true);
    return parseRfc5322Date(gm.payload?.header('Date')) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static String? _trimmedOrNull(String? v) {
    if (v == null) return null;
    final t = unfoldHeader(v).trim();
    return t.isEmpty ? null : t;
  }
}
