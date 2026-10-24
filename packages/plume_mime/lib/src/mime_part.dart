import 'dart:typed_data';

/// A raw header field. [value] is unfolded but otherwise undecoded
/// (RFC 2047 words are kept), except that 8-bit UTF-8 (RFC 6532) has been
/// decoded to text.
final class MimeHeader {
  const MimeHeader(this.name, this.value);

  final String name;
  final String value;

  @override
  String toString() => '$name: $value';
}

/// One node of a MIME tree, provider-neutral.
///
/// Trees come from [parseMimeMessage] (a raw message), from an IMAP
/// BODYSTRUCTURE, or from the Gmail API's payload. [data] holds the
/// transfer-decoded content in the part's original charset, or null when
/// the content has not been downloaded (a structure-only tree, or a large
/// Gmail part that must be fetched by [handle]).
final class MimePart {
  const MimePart({
    this.partId = '',
    required this.mimeType,
    this.filename = '',
    this.headers = const [],
    this.data,
    this.size = 0,
    this.handle,
    this.parts = const [],
  });

  /// Section of this part within the message. [parseMimeMessage] and IMAP
  /// use RFC 3501 numbering (`1`, `1.2`; a multipart root is `''`), so the
  /// id can be fetched with `BODY[partId]`. Gmail API trees keep Gmail's
  /// ids.
  final String partId;

  /// Lower-cased `type/subtype`.
  final String mimeType;

  /// Declared file name, if the source reports one separately.
  final String filename;
  final List<MimeHeader> headers;

  /// Decoded content of a leaf part; null when not downloaded.
  final Uint8List? data;

  /// Decoded size in bytes when known, else an estimate (0 = unknown).
  final int size;

  /// Provider handle to download the content later (Gmail attachmentId).
  final String? handle;
  final List<MimePart> parts;

  /// The first header named [name], case-insensitively.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final h in headers) {
      if (h.name.toLowerCase() == lower) return h.value;
    }
    return null;
  }

  bool get isMultipart => mimeType.toLowerCase().startsWith('multipart/');

  /// This part and all descendants, depth first.
  Iterable<MimePart> get allParts sync* {
    yield this;
    for (final p in parts) {
      yield* p.allParts;
    }
  }

  @override
  String toString() => 'MimePart($partId $mimeType${parts.isEmpty ? '' : ' ${parts.length} parts'})';
}
