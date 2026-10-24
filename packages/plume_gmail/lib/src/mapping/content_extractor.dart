import 'dart:typed_data';

import 'package:plume_mime/plume_mime.dart' as mime;
import 'package:plume_mime/plume_mime.dart' show ExtractedContent, MimeHeader, MimePart;

import '../api/gmail_types.dart';
import '../util/gmail_data.dart';

export 'package:plume_mime/plume_mime.dart' show ExtractedContent;

/// Converts a Gmail API payload into a provider-neutral MIME tree.
///
/// Gmail has already undone the transfer encoding; inline `data` becomes
/// [MimePart.data]. Parts Gmail only returns by `attachmentId` keep it as
/// [MimePart.handle] and have no data, unless [resolved] (keyed by
/// attachment id) supplies their bytes. Parts with neither are empty.
MimePart gmailPartToMime(GmailMessagePart part, {Map<String, List<int>> resolved = const {}}) {
  final inline = part.body.data;
  final handle = part.body.attachmentId;
  final Uint8List? data;
  if (inline != null) {
    data = decodeGmailData(inline);
  } else if (handle != null) {
    final fetched = resolved[handle];
    data = fetched == null ? null : Uint8List.fromList(fetched);
  } else {
    data = Uint8List(0);
  }
  return MimePart(
    partId: part.partId,
    mimeType: part.mimeType,
    filename: part.filename,
    headers: [for (final h in part.headers) MimeHeader(h.name, h.value)],
    data: part.isMultipart ? null : data,
    size: part.body.size,
    handle: handle,
    parts: [for (final c in part.parts) gmailPartToMime(c, resolved: resolved)],
  );
}

/// Extracts body and attachments from a Gmail payload (see
/// [mime.extractContent]). Text parts Gmail returned by attachment id are
/// listed in [ExtractedContent.unresolvedBodyParts] (their
/// [MimePart.handle] is the attachment id); fetch them and extract again
/// with [resolved] keyed by attachment id.
ExtractedContent extractContent(GmailMessagePart payload, {Map<String, List<int>> resolved = const {}}) =>
    mime.extractContent(gmailPartToMime(payload, resolved: resolved));
