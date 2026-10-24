import 'dart:convert';

/// Modified UTF-7 for IMAP mailbox names (RFC 3501 section 5.1.3).
///
/// Printable ASCII except `&` stands for itself, `&` is `&-`, and other
/// characters are UTF-16BE in base64 (with `,` for `/`, no padding)
/// between `&` and `-`.
abstract final class ModifiedUtf7 {
  static String encode(String name) {
    final out = StringBuffer();
    final pending = <int>[];
    void flush() {
      if (pending.isEmpty) return;
      final bytes = <int>[];
      for (final unit in pending) {
        bytes
          ..add(unit >> 8)
          ..add(unit & 0xFF);
      }
      out
        ..write('&')
        ..write(base64.encode(bytes).replaceAll('=', '').replaceAll('/', ','))
        ..write('-');
      pending.clear();
    }

    for (final unit in name.codeUnits) {
      if (unit >= 0x20 && unit <= 0x7E) {
        flush();
        out.write(unit == 0x26 ? '&-' : String.fromCharCode(unit));
      } else {
        pending.add(unit);
      }
    }
    flush();
    return out.toString();
  }

  /// Decodes [name]. Malformed shift sequences are kept literally, so a
  /// server that sends raw UTF-8 or a stray `&` does not break listing.
  static String decode(String name) {
    if (!name.contains('&')) return name;
    final out = StringBuffer();
    var i = 0;
    while (i < name.length) {
      final c = name[i];
      if (c != '&') {
        out.write(c);
        i++;
        continue;
      }
      final end = name.indexOf('-', i + 1);
      if (end < 0) {
        out.write(name.substring(i));
        break;
      }
      if (end == i + 1) {
        out.write('&');
        i = end + 1;
        continue;
      }
      final decoded = _decodeShift(name.substring(i + 1, end));
      if (decoded == null) {
        out.write(name.substring(i, end + 1));
      } else {
        out.write(decoded);
      }
      i = end + 1;
    }
    return out.toString();
  }

  static String? _decodeShift(String b64) {
    if (!RegExp(r'^[A-Za-z0-9+,]+$').hasMatch(b64)) return null;
    var s = b64.replaceAll(',', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    try {
      final bytes = base64.decode(s);
      if (bytes.length.isOdd) return null;
      final units = <int>[for (var j = 0; j + 1 < bytes.length; j += 2) (bytes[j] << 8) | bytes[j + 1]];
      return String.fromCharCodes(units);
    } on FormatException {
      return null;
    }
  }
}
