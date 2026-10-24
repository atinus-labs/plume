import 'dart:convert';

/// Decodes [bytes] in the given MIME [charset].
///
/// Supports UTF-8, US-ASCII, ISO-8859-1, Windows-1252, ISO-8859-15 and
/// UTF-16 (BOM-detected, LE/BE). Unknown charsets fall back to lenient UTF-8.
/// Never throws.
///
/// Following the WHATWG Encoding Standard, `iso-8859-1` is decoded as
/// Windows-1252 because real-world mail labelled Latin-1 routinely contains
/// Windows "smart quotes" in the 0x80-0x9F range. Mail labelled `us-ascii`
/// that contains 8-bit bytes is tried as UTF-8 first, then as Windows-1252.
String decodeCharset(List<int> bytes, String? charset) {
  switch (normalizeCharset(charset)) {
    case 'utf-8':
      return _utf8Lenient(bytes);
    case 'us-ascii':
      if (bytes.every((b) => b < 0x80)) return String.fromCharCodes(bytes);
      try {
        return _stripBom(utf8.decode(bytes));
      } on FormatException {
        return _decodeSingleByte(bytes, _cp1252High);
      }
    case 'windows-1252':
      return _decodeSingleByte(bytes, _cp1252High);
    case 'iso-8859-15':
      return _decodeLatin9(bytes);
    case 'utf-16':
      return _decodeUtf16(bytes, bigEndianDefault: true, detectBom: true);
    case 'utf-16le':
      return _decodeUtf16(bytes, bigEndianDefault: false, detectBom: true);
    case 'utf-16be':
      return _decodeUtf16(bytes, bigEndianDefault: true, detectBom: true);
    default:
      return _utf8Lenient(bytes);
  }
}

/// Maps charset labels and aliases onto a canonical name. Returns the
/// lower-cased input for charsets this library does not know.
String normalizeCharset(String? charset) {
  if (charset == null) return 'us-ascii';
  var c = charset.trim().toLowerCase();
  if (c.length >= 2 && c.startsWith('"') && c.endsWith('"')) c = c.substring(1, c.length - 1);
  // RFC 2231 language suffix: utf-8*en.
  final star = c.indexOf('*');
  if (star >= 0) c = c.substring(0, star);
  c = c.trim();
  return switch (c) {
    'utf-8' || 'utf8' || 'unicode-1-1-utf-8' || 'x-unicode20utf8' => 'utf-8',
    '' || 'us-ascii' || 'ascii' || 'ansi_x3.4-1968' || 'iso646-us' || 'us' || 'iso-ir-6' => 'us-ascii',
    'iso-8859-1' ||
    'iso8859-1' ||
    'iso_8859-1' ||
    'iso_8859-1:1987' ||
    'latin1' ||
    'latin-1' ||
    'l1' ||
    'cp819' ||
    'ibm819' ||
    'iso-ir-100' ||
    'windows-1252' ||
    'cp1252' ||
    'x-cp1252' =>
      'windows-1252',
    'iso-8859-15' || 'iso8859-15' || 'iso_8859-15' || 'latin-9' || 'latin9' || 'l9' || 'csisolatin9' => 'iso-8859-15',
    'utf-16' || 'utf16' || 'ucs-2' || 'iso-10646-ucs-2' => 'utf-16',
    'utf-16le' || 'utf16le' => 'utf-16le',
    'utf-16be' || 'utf16be' => 'utf-16be',
    _ => c,
  };
}

String _utf8Lenient(List<int> bytes) => _stripBom(utf8.decode(bytes, allowMalformed: true));

String _stripBom(String s) => s.startsWith('﻿') ? s.substring(1) : s;

String _decodeSingleByte(List<int> bytes, List<int> high) {
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i] & 0xFF;
    out[i] = (b >= 0x80 && b < 0xA0) ? high[b - 0x80] : b;
  }
  return String.fromCharCodes(out);
}

String _decodeLatin9(List<int> bytes) {
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i] & 0xFF;
    out[i] = _latin9Overrides[b] ?? b;
  }
  return String.fromCharCodes(out);
}

String _decodeUtf16(List<int> bytes, {required bool bigEndianDefault, required bool detectBom}) {
  var start = 0;
  var bigEndian = bigEndianDefault;
  if (detectBom && bytes.length >= 2) {
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      bigEndian = true;
      start = 2;
    } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      bigEndian = false;
      start = 2;
    }
  }
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(bigEndian ? (bytes[i] << 8) | bytes[i + 1] : (bytes[i + 1] << 8) | bytes[i]);
  }
  return String.fromCharCodes(units);
}

/// Windows-1252 code points for bytes 0x80-0x9F. Undefined bytes map to the
/// corresponding C1 control, as in the WHATWG index.
const List<int> _cp1252High = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
];

/// ISO-8859-15 differs from ISO-8859-1 in eight positions.
const Map<int, int> _latin9Overrides = {
  0xA4: 0x20AC,
  0xA6: 0x0160,
  0xA8: 0x0161,
  0xB4: 0x017D,
  0xB8: 0x017E,
  0xBC: 0x0152,
  0xBD: 0x0153,
  0xBE: 0x0178,
};
