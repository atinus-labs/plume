import 'dart:typed_data';

import 'address.dart';

/// A file attached to an outgoing message.
final class OutgoingAttachment {
  const OutgoingAttachment({
    required this.filename,
    required this.mimeType,
    required this.bytes,
    this.contentId,
  });

  final String filename;
  final String mimeType;
  final Uint8List bytes;

  /// Set for inline images referenced from the HTML body as `cid:`.
  final String? contentId;
}

/// A message being composed. Used for both drafts and sending.
final class OutgoingMessage {
  const OutgoingMessage({
    required this.accountId,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.textBody = '',
    this.htmlBody,
    this.attachments = const [],
    this.threadId,
    this.inReplyTo,
    this.references = const [],
    this.draftId,
  });

  final String accountId;
  final Address from;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;
  final String textBody;
  final String? htmlBody;
  final List<OutgoingAttachment> attachments;

  /// Provider thread to file the message into when replying.
  final String? threadId;
  final String? inReplyTo;
  final List<String> references;

  /// Provider draft id when this message was saved as a server draft.
  final String? draftId;

  bool get hasRecipients => to.isNotEmpty || cc.isNotEmpty || bcc.isNotEmpty;

  OutgoingMessage copyWith({String? draftId}) => OutgoingMessage(
        accountId: accountId,
        from: from,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        textBody: textBody,
        htmlBody: htmlBody,
        attachments: attachments,
        threadId: threadId,
        inReplyTo: inReplyTo,
        references: references,
        draftId: draftId ?? this.draftId,
      );
}
