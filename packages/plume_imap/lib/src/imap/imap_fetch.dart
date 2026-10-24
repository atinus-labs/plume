import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';

import 'imap_response.dart';
import 'mutf7.dart';

/// The ENVELOPE of a message (RFC 3501 section 7.4.2), decoded.
final class ImapEnvelope {
  const ImapEnvelope({
    this.date,
    this.subject = '',
    this.from = const [],
    this.sender = const [],
    this.replyTo = const [],
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.inReplyTo,
    this.messageId,
  });

  /// The `Date` header, parsed; null when missing or unparseable.
  final DateTime? date;

  /// Decoded subject (RFC 2047 words resolved).
  final String subject;
  final List<Address> from;
  final List<Address> sender;
  final List<Address> replyTo;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;

  /// `<id>` with angle brackets.
  final String? inReplyTo;
  final String? messageId;

  static ImapEnvelope parse(ImapValue value) {
    final f = value.items;
    ImapValue at(int i) => i < f.length ? f[i] : const ImapNil();
    String? str(int i) => at(i).isNil ? null : at(i).text;
    return ImapEnvelope(
      date: parseRfc5322Date(str(0)),
      subject: decodeHeaderValue(str(1) ?? '').trim(),
      from: _addresses(at(2)),
      sender: _addresses(at(3)),
      replyTo: _addresses(at(4)),
      to: _addresses(at(5)),
      cc: _addresses(at(6)),
      bcc: _addresses(at(7)),
      inReplyTo: parseMessageIdHeader(str(8)),
      messageId: parseMessageIdHeader(str(9)),
    );
  }

  /// Address structures: `(name adl mailbox host)`. Group markers (host
  /// NIL) are skipped, which flattens groups.
  static List<Address> _addresses(ImapValue value) {
    final out = <Address>[];
    for (final a in value.items) {
      final parts = a.items;
      if (parts.length < 4) continue;
      final mailbox = parts[2].isNil ? null : parts[2].text;
      final host = parts[3].isNil ? null : parts[3].text;
      if (mailbox == null || host == null) continue; // group start/end
      final rawName = parts[0].isNil ? null : parts[0].text;
      final name = rawName == null ? null : decodeHeaderValue(rawName).trim();
      out.add(Address(host.isEmpty ? mailbox : '$mailbox@$host', name == null || name.isEmpty ? null : name));
    }
    return out;
  }
}

/// One `* n FETCH (...)` response.
final class ImapFetch {
  ImapFetch(this.sequence);

  final int sequence;
  int? uid;
  Set<String>? flags;
  DateTime? internalDate;
  int? size;
  ImapEnvelope? envelope;

  /// BODYSTRUCTURE as a MIME tree without content, numbered like IMAP
  /// sections.
  MimePart? structure;
  int? modseq;

  /// Gmail's X-GM-MSGID / X-GM-THRID as lower-case hex, like Gmail API ids.
  String? gmailMessageId;
  String? gmailThreadId;

  /// Gmail's X-GM-LABELS, decoded (`\Inbox`, `\Important`, `Work/Q3`...).
  List<String>? gmailLabels;

  /// `BODY[section]` contents keyed by the upper-cased section (`''` for
  /// the whole message, `1.2`, `HEADER.FIELDS (REFERENCES)`...).
  final sections = <String, Uint8List>{};

  /// Parses the item list of a FETCH response. [utf8Names] tells whether
  /// X-GM-LABELS are UTF-8 (UTF8=ACCEPT) rather than modified UTF-7.
  static ImapFetch parse(int sequence, List<ImapValue> data, {bool utf8Names = false}) {
    final fetch = ImapFetch(sequence);
    final items = data.isNotEmpty && data.first is ImapList ? data.first.items : data;
    for (var i = 0; i + 1 < items.length; i += 2) {
      final key = items[i].text ?? '';
      final value = items[i + 1];
      final upper = key.toUpperCase();
      switch (upper) {
        case 'UID':
          fetch.uid = value.asInt;
        case 'FLAGS':
          fetch.flags = {for (final f in value.items) ?f.text};
        case 'INTERNALDATE':
          fetch.internalDate = parseInternalDate(value.text);
        case 'RFC822.SIZE':
          fetch.size = value.asInt;
        case 'ENVELOPE':
          fetch.envelope = ImapEnvelope.parse(value);
        case 'BODYSTRUCTURE' || 'BODY' when value is ImapList:
          fetch.structure = parseBodyStructure(value);
        case 'MODSEQ':
          fetch.modseq = value.items.isEmpty ? value.asInt : value.items.first.asInt;
        case 'X-GM-MSGID':
          fetch.gmailMessageId = gmailIdToHex(value.text);
        case 'X-GM-THRID':
          fetch.gmailThreadId = gmailIdToHex(value.text);
        case 'X-GM-LABELS':
          fetch.gmailLabels = [
            for (final l in value.items)
              if (l.text case final t?) l is ImapAtom || utf8Names ? t : ModifiedUtf7.decode(t),
          ];
        default:
          if (upper.startsWith('BODY[') || upper.startsWith('BINARY[') || upper.startsWith('RFC822')) {
            final bytes = value is ImapString ? value.bytes : Uint8List(0);
            fetch.sections[sectionKey(upper)] = bytes;
          }
      }
    }
    return fetch;
  }

  /// `BODY[HEADER.FIELDS (A B)]<0>` → `HEADER.FIELDS (A B)`; `RFC822` →
  /// ``; `RFC822.HEADER` → `HEADER`.
  static String sectionKey(String upperKey) {
    if (upperKey == 'RFC822') return '';
    if (upperKey == 'RFC822.HEADER') return 'HEADER';
    if (upperKey == 'RFC822.TEXT') return 'TEXT';
    final open = upperKey.indexOf('[');
    final close = upperKey.lastIndexOf(']');
    if (open < 0 || close < open) return upperKey;
    return upperKey.substring(open + 1, close).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// X-GM-MSGID / X-GM-THRID are unsigned 64-bit decimals; the Gmail API uses
/// the same numbers in hex.
String? gmailIdToHex(String? decimal) {
  if (decimal == null) return null;
  final n = BigInt.tryParse(decimal.trim());
  return n?.toRadixString(16);
}

/// Hex Gmail id → decimal for X-GM-MSGID / X-GM-THRID search keys.
String? gmailIdToDecimal(String hex) => BigInt.tryParse(hex, radix: 16)?.toString();

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// Parses an INTERNALDATE (`17-Jul-1996 02:44:25 -0700`) to UTC.
DateTime? parseInternalDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^\s*(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})').firstMatch(value);
  if (m == null) return parseRfc5322Date(value);
  final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
  if (month == 0) return null;
  final offset = (int.parse(m.group(8)!) * 60 + int.parse(m.group(9)!)) * (m.group(7) == '-' ? -1 : 1);
  return DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!),
          int.parse(m.group(5)!), int.parse(m.group(6)!))
      .subtract(Duration(minutes: offset));
}

/// Formats a date for APPEND (`"24-Oct-2026 18:30:05 +0200"`).
String formatInternalDate(DateTime date) {
  final offset = date.isUtc ? Duration.zero : date.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${two(date.day)}-${names[date.month - 1]}-${date.year} '
      '${two(date.hour)}:${two(date.minute)}:${two(date.second)} $sign${two(abs.inHours)}${two(abs.inMinutes % 60)}';
}

/// Converts a BODYSTRUCTURE into a content-less [MimePart] tree with IMAP
/// section ids and synthesized MIME headers, so the provider-neutral
/// extractor in plume_mime can work on it. Sizes are decoded estimates.
MimePart parseBodyStructure(ImapValue value) => _part(value, '', 0);

MimePart _part(ImapValue value, String section, int depth) {
  final f = value.items;
  if (f.isNotEmpty && f.first is ImapList && depth < 32) {
    // multipart: (child)(child)... "subtype" [params disposition language location]
    final children = <MimePart>[];
    var i = 0;
    while (i < f.length && f[i] is ImapList) {
      final childSection = section.isEmpty ? '${i + 1}' : '$section.${i + 1}';
      children.add(_part(f[i], childSection, depth + 1));
      i++;
    }
    final subtype = (i < f.length ? f[i].text : null)?.toLowerCase() ?? 'mixed';
    final params = i + 1 < f.length ? _params(f[i + 1]) : const <(String, String)>[];
    final disposition = i + 2 < f.length ? f[i + 2] : const ImapNil();
    return MimePart(
      partId: section,
      mimeType: 'multipart/$subtype',
      headers: [
        MimeHeader('Content-Type', _headerValue('multipart/$subtype', params)),
        ?_dispositionHeader(disposition),
      ],
      parts: children,
    );
  }

  // Leaf: type subtype params id description encoding size [...]
  ImapValue at(int i) => i < f.length ? f[i] : const ImapNil();
  final type = (at(0).text ?? 'application').toLowerCase();
  final subtype = (at(1).text ?? 'octet-stream').toLowerCase();
  final mimeType = '$type/$subtype';
  final params = _params(at(2));
  final id = at(3).isNil ? null : at(3).text;
  final description = at(4).isNil ? null : at(4).text;
  final encoding = at(5).isNil ? null : at(5).text;
  final encodedSize = at(6).asInt ?? 0;
  // Extension data follows the type-specific fields.
  var ext = 7;
  if (type == 'text') {
    ext = 8; // lines
  } else if (mimeType == 'message/rfc822' || mimeType == 'message/global') {
    ext = 10; // envelope, body, lines
  }
  final disposition = at(ext + 1); // after md5
  final leafSection = section.isEmpty ? '1' : section;
  return MimePart(
    partId: leafSection,
    mimeType: mimeType,
    headers: [
      MimeHeader('Content-Type', _headerValue(mimeType, params)),
      if (encoding != null) MimeHeader('Content-Transfer-Encoding', encoding),
      if (id != null) MimeHeader('Content-ID', id),
      if (description != null) MimeHeader('Content-Description', description),
      ?_dispositionHeader(disposition),
    ],
    size: estimateDecodedSize(encodedSize, encoding),
  );
}

/// Decoded size from an encoded size: base64 carries 3 bytes per 4
/// characters plus a CRLF every 76.
int estimateDecodedSize(int encodedSize, String? encoding) {
  if (encoding?.toLowerCase() == 'base64') return (encodedSize * 57) ~/ 78;
  return encodedSize;
}

List<(String, String)> _params(ImapValue value) {
  final f = value.items;
  return [
    for (var i = 0; i + 1 < f.length; i += 2)
      if (f[i].text case final k?) (k.toLowerCase(), f[i + 1].text ?? ''),
  ];
}

MimeHeader? _dispositionHeader(ImapValue value) {
  final f = value.items;
  if (f.isEmpty) return null;
  final kind = f.first.text?.toLowerCase();
  if (kind == null) return null;
  return MimeHeader('Content-Disposition', _headerValue(kind, f.length > 1 ? _params(f[1]) : const []));
}

String _headerValue(String main, List<(String, String)> params) {
  final sb = StringBuffer(main);
  for (final (k, v) in params) {
    sb.write('; $k="${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"');
  }
  return sb.toString();
}

/// Decodes a `BODY[HEADER.FIELDS (...)]` section into header fields.
List<MimeHeader> headersOf(Uint8List? bytes) => bytes == null ? const [] : parseHeaderBytes(bytes);

/// The text of a single header in [headers], case-insensitively.
String? headerValue(List<MimeHeader> headers, String name) {
  final lower = name.toLowerCase();
  for (final h in headers) {
    if (h.name.toLowerCase() == lower) return h.value;
  }
  return null;
}
