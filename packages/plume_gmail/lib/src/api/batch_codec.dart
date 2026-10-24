import 'dart:convert';

import 'package:plume_mime/plume_mime.dart' show HeaderValue;

import 'gmail_request.dart';

/// One sub-response of a Gmail batch response.
final class BatchPart {
  const BatchPart({required this.index, required this.status, required this.headers, required this.body});

  /// Index of the sub-request this answers, from its `Content-ID`, or null
  /// when the server did not echo one.
  final int? index;
  final int status;

  /// Lower-cased header names.
  final Map<String, String> headers;
  final String body;
}

/// Encodes and decodes Google's `multipart/mixed` batch format
/// (https://developers.google.com/gmail/api/guides/batch).
abstract final class BatchCodec {
  /// Encodes [requests] as a batch body. Each part gets the header
  /// `Content-ID: <item-N>`, where N is the matching entry of [ids]
  /// (defaults to the position); the response echoes `<response-item-N>`.
  static String encode(List<GmailRequest> requests, String boundary, {List<int>? ids}) {
    final sb = StringBuffer();
    for (var i = 0; i < requests.length; i++) {
      final r = requests[i];
      final id = ids == null ? i : ids[i];
      sb
        ..write('--$boundary\r\n')
        ..write('Content-Type: application/http\r\n')
        ..write('Content-ID: <item-$id>\r\n')
        ..write('\r\n')
        ..write('${r.method} ${r.relativeUrl} HTTP/1.1\r\n');
      if (r.body != null) {
        final json = jsonEncode(r.body);
        sb
          ..write('Content-Type: application/json; charset=UTF-8\r\n')
          ..write('Content-Length: ${utf8.encode(json).length}\r\n')
          ..write('\r\n')
          ..write(json)
          ..write('\r\n');
      } else {
        sb.write('\r\n');
      }
    }
    sb.write('--$boundary--\r\n');
    return sb.toString();
  }

  /// Parses a batch response. Throws [FormatException] when the body is
  /// not a multipart response at all.
  static List<BatchPart> decode(String? contentType, List<int> bodyBytes) {
    final boundary = HeaderValue.parse(contentType)['boundary'];
    if (boundary == null || boundary.isEmpty) {
      throw const FormatException('Batch response has no multipart boundary');
    }
    final text = utf8.decode(bodyBytes, allowMalformed: true);
    final delimiter = '--$boundary';
    final segments = text.split(delimiter);
    final parts = <BatchPart>[];
    // segments[0] is the preamble; a segment starting with "--" is the
    // epilogue after the close delimiter.
    for (final segment in segments.skip(1)) {
      if (segment.startsWith('--')) break;
      final part = _parsePart(_trimNewlines(segment));
      if (part != null) parts.add(part);
    }
    return parts;
  }

  static BatchPart? _parsePart(String part) {
    final split = part.startsWith('HTTP/') ? (headers: '', rest: part) : _splitHeaders(part);
    if (split == null) return null;
    final outer = _parseHeaders(split.headers);
    final http = split.rest;
    // The embedded HTTP response: status line, headers, blank line, body.
    final firstLineEnd = http.indexOf('\n');
    final statusLine = (firstLineEnd < 0 ? http : http.substring(0, firstLineEnd)).trim();
    final statusMatch = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(statusLine);
    if (statusMatch == null) return null;
    final status = int.parse(statusMatch.group(1)!);
    final afterStatus = firstLineEnd < 0 ? '' : http.substring(firstLineEnd + 1);
    final inner = _splitHeaders(afterStatus);
    final headers = inner == null ? <String, String>{} : _parseHeaders(inner.headers);
    final body = inner == null ? afterStatus : _trimNewlines(inner.rest);
    final contentId = outer['content-id'];
    int? index;
    if (contentId != null) {
      final m = RegExp(r'item-(\d+)').firstMatch(contentId);
      if (m != null) index = int.parse(m.group(1)!);
    }
    return BatchPart(index: index, status: status, headers: headers, body: body);
  }

  static ({String headers, String rest})? _splitHeaders(String text) {
    // Headers may be empty: the part can start directly with a blank line.
    if (text.startsWith('\r\n')) return (headers: '', rest: text.substring(2));
    if (text.startsWith('\n')) return (headers: '', rest: text.substring(1));
    final m = RegExp(r'\r?\n\r?\n').firstMatch(text);
    if (m == null) return (headers: text, rest: '');
    return (headers: text.substring(0, m.start), rest: text.substring(m.end));
  }

  static Map<String, String> _parseHeaders(String block) {
    final out = <String, String>{};
    for (final line in block.split(RegExp(r'\r?\n'))) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      out[line.substring(0, colon).trim().toLowerCase()] = line.substring(colon + 1).trim();
    }
    return out;
  }

  static String _trimNewlines(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && (s.codeUnitAt(start) == 0x0D || s.codeUnitAt(start) == 0x0A)) {
      start++;
    }
    while (end > start && (s.codeUnitAt(end - 1) == 0x0D || s.codeUnitAt(end - 1) == 0x0A)) {
      end--;
    }
    return s.substring(start, end);
  }
}
