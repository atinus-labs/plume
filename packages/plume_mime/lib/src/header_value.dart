import 'dart:convert';

import 'charset.dart';
import 'rfc2047.dart';

/// A parsed structured header such as `Content-Type` or
/// `Content-Disposition`: a main value plus parameters.
///
/// Parameter names are lower-cased. Values are fully decoded, including
/// RFC 2231 extended parameters (`filename*=UTF-8''%E2%82%AC.pdf`),
/// RFC 2231 continuations (`name*0=`, `name*1*=`) and, defensively, RFC 2047
/// encoded-words inside quoted values, which many mailers emit.
final class HeaderValue {
  const HeaderValue(this.value, this.params);

  /// The lower-cased main value, e.g. `text/html` or `attachment`.
  final String value;
  final Map<String, String> params;

  String? operator [](String name) => params[name.toLowerCase()];

  static HeaderValue parse(String? raw) {
    if (raw == null) return const HeaderValue('', {});
    final pieces = _splitParams(unfoldHeader(raw));
    final main = pieces.isEmpty ? '' : pieces.first.trim().toLowerCase();
    final simple = <String, String>{};
    final extended = <String, Map<int, ({String value, bool encoded})>>{};
    final keyPattern = RegExp(r'^(.+?)(?:\*(\d+))?(\*)?$');

    for (final piece in pieces.skip(1)) {
      final eq = piece.indexOf('=');
      if (eq <= 0) continue;
      final key = piece.substring(0, eq).trim().toLowerCase();
      final rawValue = piece.substring(eq + 1).trim();
      final quoted = rawValue.length >= 2 && rawValue.startsWith('"') && rawValue.endsWith('"');
      final value = quoted ? _unquote(rawValue) : rawValue;
      final m = keyPattern.firstMatch(key);
      if (m == null) continue;
      final name = m.group(1)!;
      final index = m.group(2);
      final encoded = m.group(3) != null;
      if (index == null && !encoded) {
        simple[name] = quoted || value.contains('=?') ? decodeHeaderValue(value) : value;
      } else {
        extended.putIfAbsent(name, () => {})[index == null ? 0 : int.parse(index)] = (value: value, encoded: encoded);
      }
    }

    final params = Map<String, String>.of(simple);
    for (final entry in extended.entries) {
      final segments = entry.value.keys.toList()..sort();
      String? charset;
      final bytes = <int>[];
      for (final i in segments) {
        final seg = entry.value[i]!;
        var text = seg.value;
        if (seg.encoded) {
          if (i == segments.first) {
            // charset'language'data
            final first = text.indexOf("'");
            final second = first < 0 ? -1 : text.indexOf("'", first + 1);
            if (first >= 0 && second > first) {
              charset = text.substring(0, first);
              text = text.substring(second + 1);
            }
          }
          bytes.addAll(_percentDecode(text));
        } else {
          bytes.addAll(utf8.encode(text));
        }
      }
      params[entry.key] = decodeCharset(bytes, charset == null || charset.isEmpty ? 'utf-8' : charset);
    }
    return HeaderValue(main, params);
  }
}

/// Splits on `;` outside quoted strings.
List<String> _splitParams(String input) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var escaped = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (escaped) {
      buf.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\' && inQuotes) {
      buf.write(ch);
      escaped = true;
      continue;
    }
    if (ch == '"') inQuotes = !inQuotes;
    if (ch == ';' && !inQuotes) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

String _unquote(String quoted) {
  final inner = quoted.substring(1, quoted.length - 1);
  final sb = StringBuffer();
  for (var i = 0; i < inner.length; i++) {
    final ch = inner[i];
    if (ch == r'\' && i + 1 < inner.length) {
      sb.write(inner[++i]);
    } else {
      sb.write(ch);
    }
  }
  return sb.toString();
}

List<int> _percentDecode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x25 && i + 2 < s.length) {
      final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
      if (v != null) {
        out.add(v);
        i += 2;
        continue;
      }
    }
    if (c < 0x80) {
      out.add(c);
    } else {
      out.addAll(utf8.encode(String.fromCharCode(c)));
    }
  }
  return out;
}

/// Encodes a parameter value for an outgoing header. ASCII values become a
/// quoted string; others use RFC 2231 (`name*=UTF-8''...`) plus a quoted
/// RFC 2047 fallback for old clients, which is what Gmail itself emits.
String encodeHeaderParam(String name, String value) {
  if (!headerNeedsEncoding(value)) {
    return '$name="${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  final pct = StringBuffer();
  for (final b in utf8.encode(value)) {
    final isAttrChar = (b >= 0x30 && b <= 0x39) ||
        (b >= 0x41 && b <= 0x5A) ||
        (b >= 0x61 && b <= 0x7A) ||
        '!#\$&+-.^_`|~'.codeUnits.contains(b);
    if (isAttrChar) {
      pct.writeCharCode(b);
    } else {
      pct.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return '$name="${encodeWords(value).join(' ')}";\r\n $name*=UTF-8\'\'$pct';
}
