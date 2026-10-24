import 'dart:convert';

import 'charset.dart';
import 'codecs.dart';

/// Matches one RFC 2047 encoded-word. The encoded text is allowed to contain
/// spaces because some senders (incorrectly) emit them inside Q-words.
final RegExp _encodedWord = RegExp(r'=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?=');

/// Decodes RFC 2047 encoded-words in a header value and unfolds it.
///
/// Some sources (the Gmail API) usually return decoded headers but not
/// always, so this is safe to apply defensively: input without
/// encoded-words is returned unchanged (apart from unfolding). Adjacent
/// encoded-words in the same charset are decoded as one byte run, which
/// correctly handles multi-byte characters split across words. Malformed
/// words are left as they are. Never throws.
String decodeHeaderValue(String input) {
  final unfolded = unfoldHeader(input);
  if (!unfolded.contains('=?')) return unfolded;
  final out = StringBuffer();
  var pos = 0;
  var lastWasWord = false;
  String? runCharset;
  final runBytes = <int>[];

  void flushRun() {
    if (runCharset != null) {
      out.write(decodeCharset(runBytes, runCharset));
      runBytes.clear();
      runCharset = null;
    }
  }

  for (final m in _encodedWord.allMatches(unfolded)) {
    final between = unfolded.substring(pos, m.start);
    final charset = m.group(1)!;
    final encoding = m.group(2)!.toUpperCase();
    final text = m.group(3)!;
    final bytes = encoding == 'B' ? decodeBase64Lenient(text) : decodeQEncoding(text);
    if (bytes == null) {
      flushRun();
      out
        ..write(between)
        ..write(m.group(0));
      pos = m.end;
      lastWasWord = false;
      continue;
    }
    // Linear whitespace between two encoded-words is not displayed.
    final adjacent = lastWasWord && between.trim().isEmpty;
    if (!adjacent) {
      flushRun();
      out.write(between);
    }
    if (runCharset != null && normalizeCharset(runCharset) != normalizeCharset(charset)) flushRun();
    runCharset ??= charset;
    runBytes.addAll(bytes);
    pos = m.end;
    lastWasWord = true;
  }
  flushRun();
  out.write(unfolded.substring(pos));
  return out.toString();
}

/// Removes header folding (CRLF followed by whitespace).
String unfoldHeader(String value) {
  if (!value.contains('\n')) return value;
  return value.replaceAll(RegExp(r'\r?\n(?=[ \t])'), '').replaceAll(RegExp(r'\r?\n'), ' ');
}

/// Whether [text] must be RFC 2047-encoded to appear in a header.
bool headerNeedsEncoding(String text) {
  for (final r in text.runes) {
    if (r > 0x7E || (r < 0x20 && r != 0x09)) return true;
  }
  // Text that looks like an encoded-word would be decoded by readers.
  return text.contains('=?');
}

/// Encodes [text] as a sequence of UTF-8 "B" encoded-words, never
/// splitting a character across words. Words are at most 64 characters so
/// that even the first one fits on a header line next to a long header
/// name (RFC 2047 limits such lines to 76 characters).
List<String> encodeWords(String text) {
  const maxBytes = 39; // 52 base64 chars + 12 chars of framing = 64.
  final words = <String>[];
  final chunk = <int>[];
  for (final rune in text.runes) {
    final bytes = utf8.encode(String.fromCharCode(rune));
    if (chunk.length + bytes.length > maxBytes && chunk.isNotEmpty) {
      words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
      chunk.clear();
    }
    chunk.addAll(bytes);
  }
  if (chunk.isNotEmpty) words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
  return words;
}
