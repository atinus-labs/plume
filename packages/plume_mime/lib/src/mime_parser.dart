import 'dart:convert';

import 'codecs.dart';
import 'header_value.dart';
import 'mime_part.dart';

/// Parses a raw RFC 5322 message into a [MimePart] tree.
///
/// Headers are kept raw (unfolded), leaf bodies are transfer-decoded and
/// kept in their original charset, and part ids follow IMAP's section
/// numbering (RFC 3501 section 6.4.5): the children of a multipart root
/// are `1`, `2`..., nested parts `2.1`, and a single-part message's body is
/// `1`. An attachment's id can therefore be fetched from an IMAP server
/// with `BODY.PEEK[<partId>]`. Embedded `message/rfc822` parts are leaves.
///
/// Never throws: malformed input yields a best-effort tree.
MimePart parseMimeMessage(List<int> bytes) => _parseEntity(latin1.decode(bytes, allowInvalid: true), '', 0);

/// [section] is the IMAP section of this entity's *content*; '' for the
/// top-level message.
MimePart _parseEntity(String raw, String section, int depth) {
  final split = _splitHeaderBody(raw);
  final headers = parseHeaderBlock(split.headers);
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final h in headers) {
      if (h.name.toLowerCase() == lower) return h.value;
    }
    return null;
  }

  final contentType = HeaderValue.parse(header('Content-Type'));
  final mimeType = contentType.value.isEmpty || !contentType.value.contains('/') ? 'text/plain' : contentType.value;
  final disposition = HeaderValue.parse(header('Content-Disposition'));
  final filename = disposition['filename'] ?? contentType['name'] ?? '';
  final boundary = contentType['boundary'];

  if (mimeType.startsWith('multipart/') && boundary != null && boundary.isNotEmpty && depth < 32) {
    final children = <MimePart>[];
    final bodies = _splitMultipart(split.body, boundary);
    for (var i = 0; i < bodies.length; i++) {
      final childSection = section.isEmpty ? '${i + 1}' : '$section.${i + 1}';
      children.add(_parseEntity(bodies[i], childSection, depth + 1));
    }
    return MimePart(partId: section, mimeType: mimeType, filename: filename, headers: headers, parts: children);
  }

  // A non-multipart top-level message has its body at section 1.
  final partId = section.isEmpty ? '1' : section;
  final data = decodeTransferEncoding(latin1.encode(split.body), header('Content-Transfer-Encoding'));
  return MimePart(
    partId: partId,
    mimeType: mimeType,
    filename: filename,
    headers: headers,
    data: data,
    size: data.length,
  );
}

({String headers, String body}) _splitHeaderBody(String raw) {
  if (raw.startsWith('\r\n')) return (headers: '', body: raw.substring(2));
  if (raw.startsWith('\n')) return (headers: '', body: raw.substring(1));
  final m = RegExp(r'\r?\n\r?\n').firstMatch(raw);
  if (m == null) return (headers: raw, body: '');
  return (headers: raw.substring(0, m.start), body: raw.substring(m.end));
}

/// Parses a header block (text decoded as Latin-1, so that 8-bit bytes
/// survive) into fields. Folded lines are unfolded; raw 8-bit values that
/// are valid UTF-8 (RFC 6532) are decoded.
List<MimeHeader> parseHeaderBlock(String block) {
  final headers = <MimeHeader>[];
  String? name;
  StringBuffer? value;
  void flush() {
    if (name != null) headers.add(MimeHeader(name!, _maybeUtf8(value.toString().trim())));
    name = null;
  }

  for (final line in block.split(RegExp(r'\r?\n'))) {
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) && name != null) {
      value!.write(line);
      continue;
    }
    flush();
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    name = line.substring(0, colon).trim();
    value = StringBuffer(line.substring(colon + 1));
  }
  flush();
  return headers;
}

/// Parses raw header bytes (e.g. an IMAP `BODY[HEADER.FIELDS (...)]`).
List<MimeHeader> parseHeaderBytes(List<int> bytes) => parseHeaderBlock(latin1.decode(bytes, allowInvalid: true));

/// Raw 8-bit headers (RFC 6532) are UTF-8; the text was read as Latin-1.
String _maybeUtf8(String latin) {
  if (latin.codeUnits.every((c) => c < 0x80)) return latin;
  try {
    return utf8.decode(latin1.encode(latin));
  } on FormatException {
    return latin;
  }
}

List<String> _splitMultipart(String body, String boundary) {
  final delimiter = RegExp('(?:^|\\r?\\n)--${RegExp.escape(boundary)}(--)?[ \\t]*(?:\\r?\\n|\$)');
  final parts = <String>[];
  int? start;
  for (final m in delimiter.allMatches(body)) {
    if (start != null) parts.add(body.substring(start, m.start));
    if (m.group(1) != null) return parts; // close delimiter
    start = m.end;
  }
  // Missing close delimiter: keep the last part anyway.
  if (start != null && start < body.length) parts.add(body.substring(start));
  return parts;
}
