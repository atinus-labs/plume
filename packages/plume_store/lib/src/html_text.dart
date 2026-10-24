/// Fast HTML to plain text conversion for the full-text index.
///
/// This is not a renderer: it drops tags, comments and the contents of
/// `<script>`, `<style>`, `<head>`, `<title>` and `<template>`, decodes common
/// character references and collapses whitespace. Block-level tags become
/// line breaks so that words on either side of them never merge.
library;

/// Converts [html] to whitespace-collapsed plain text. Output is capped at
/// [maxLength] characters (roughly; the cut happens between words).
String htmlToText(String html, {int maxLength = 1 << 20}) {
  final out = StringBuffer();
  final n = html.length;
  var i = 0;
  // Whether the last character written was whitespace (or nothing written).
  var lastSpace = true;
  var pendingBreak = false;

  void writeSpace(bool isBreak) {
    if (isBreak) pendingBreak = true;
    lastSpace = true;
  }

  void writeText(String s) {
    for (var k = 0; k < s.length; k++) {
      if (out.length >= maxLength) return;
      final c = s.codeUnitAt(k);
      if (_isInvisible(c)) continue;
      if (_isSpace(c)) {
        lastSpace = true;
        continue;
      }
      if (lastSpace && out.isNotEmpty) out.write(pendingBreak ? '\n' : ' ');
      pendingBreak = false;
      lastSpace = false;
      out.writeCharCode(c);
    }
  }

  var textStart = 0;
  void flushText(int end) {
    if (end > textStart) writeText(_decodeEntities(html, textStart, end));
  }

  while (i < n && out.length < maxLength) {
    final c = html.codeUnitAt(i);
    if (c != 0x3C /* < */ ) {
      i++;
      continue;
    }
    // Comment, doctype, CDATA.
    if (html.startsWith('<!--', i)) {
      flushText(i);
      final end = html.indexOf('-->', i + 4);
      i = end < 0 ? n : end + 3;
      textStart = i;
      continue;
    }
    if (i + 1 < n) {
      final next = html.codeUnitAt(i + 1);
      final isTagStart = _isAsciiLetter(next) || next == 0x2F /* / */ || next == 0x21 /* ! */ || next == 0x3F /* ? */;
      if (!isTagStart) {
        // A literal '<' in text.
        i++;
        continue;
      }
    } else {
      i++;
      continue;
    }
    flushText(i);
    final tagEnd = _findTagEnd(html, i + 1);
    final name = _tagName(html, i + 1, tagEnd);
    final closing = html.codeUnitAt(i + 1) == 0x2F;
    i = tagEnd < n ? tagEnd + 1 : n;
    if (!closing && _rawContentTags.contains(name)) {
      // Skip everything up to the matching close tag.
      final close = _indexOfIgnoreCase(html, '</$name', i);
      if (close < 0) {
        i = n;
      } else {
        final end = html.indexOf('>', close);
        i = end < 0 ? n : end + 1;
      }
      writeSpace(true);
    } else if (_blockTags.contains(name)) {
      writeSpace(true);
    } else if (name == 'img') {
      writeSpace(false);
    }
    textStart = i;
  }
  flushText(i < n ? i : n);
  return out.toString();
}

/// Decodes HTML character references in [s].
String decodeHtmlEntities(String s) => _decodeEntities(s, 0, s.length);

String _decodeEntities(String s, int start, int end) {
  final amp = s.indexOf('&', start);
  if (amp < 0 || amp >= end) return s.substring(start, end);
  final out = StringBuffer();
  var i = start;
  while (i < end) {
    final c = s.codeUnitAt(i);
    if (c != 0x26 /* & */ ) {
      final nextAmp = s.indexOf('&', i);
      final stop = nextAmp < 0 || nextAmp > end ? end : nextAmp;
      out.write(s.substring(i, stop));
      i = stop;
      continue;
    }
    // Find terminating ';' within a short window.
    var j = i + 1;
    final limit = end < i + 34 ? end : i + 34;
    while (j < limit && s.codeUnitAt(j) != 0x3B && _isEntityChar(s.codeUnitAt(j))) {
      j++;
    }
    final hasSemi = j < end && s.codeUnitAt(j) == 0x3B;
    final body = s.substring(i + 1, j);
    String? decoded;
    if (body.startsWith('#')) {
      int? code;
      if (body.length > 1 && (body.codeUnitAt(1) | 0x20) == 0x78 /* x */ ) {
        code = int.tryParse(body.substring(2), radix: 16);
      } else {
        code = int.tryParse(body.substring(1));
      }
      if (code != null) {
        if (code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) code = 0xFFFD;
        decoded = String.fromCharCode(_windows1252[code] ?? code);
      }
    } else {
      decoded = _namedEntities[body];
    }
    if (decoded != null && (hasSemi || !body.startsWith('#') || body.length > 1)) {
      out.write(decoded);
      i = hasSemi ? j + 1 : j;
    } else {
      out.write('&');
      i++;
    }
  }
  return out.toString();
}

bool _isEntityChar(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x23;

bool _isSpace(int c) =>
    c == 0x20 ||
    c == 0x0A ||
    c == 0x0D ||
    c == 0x09 ||
    c == 0x0C ||
    c == 0xA0 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x202F ||
    c == 0x3000;

/// Zero-width characters that marketing mail uses as preheader padding, and
/// soft hyphens. Dropped so that they never split or pad words.
bool _isInvisible(int c) => c == 0x00AD || c == 0x034F || (c >= 0x200B && c <= 0x200D) || c == 0x2060 || c == 0xFEFF;

bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// Index of the `>` closing the tag that starts before [from], honouring
/// quoted attribute values. Returns the string length when unterminated.
int _findTagEnd(String s, int from) {
  var quote = 0;
  for (var i = from; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == 0x22 || c == 0x27) {
      // Only treat quotes as delimiters inside attribute values (after '=').
      var k = i - 1;
      while (k >= from && _isSpace(s.codeUnitAt(k))) {
        k--;
      }
      if (k >= from && s.codeUnitAt(k) == 0x3D) quote = c;
    } else if (c == 0x3E) {
      return i;
    }
  }
  return s.length;
}

String _tagName(String s, int from, int end) {
  var i = from;
  if (i < end && s.codeUnitAt(i) == 0x2F) i++;
  final start = i;
  while (i < end) {
    final c = s.codeUnitAt(i);
    if (!(_isAsciiLetter(c) || (c >= 0x30 && c <= 0x39))) break;
    i++;
  }
  return s.substring(start, i).toLowerCase();
}

int _indexOfIgnoreCase(String s, String needle, int from) {
  final first = needle.codeUnitAt(0);
  final max = s.length - needle.length;
  outer:
  for (var i = from; i <= max; i++) {
    if (s.codeUnitAt(i) != first) continue;
    for (var k = 1; k < needle.length; k++) {
      if ((s.codeUnitAt(i + k) | 0x20) != (needle.codeUnitAt(k) | 0x20)) continue outer;
    }
    return i;
  }
  return -1;
}

const _rawContentTags = {'script', 'style', 'head', 'title', 'template', 'noscript', 'xml'};

const _blockTags = {
  'address', 'article', 'aside', 'blockquote', 'br', 'dd', 'div', 'dl', 'dt', 'fieldset', 'figcaption', //
  'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol',
  'p', 'pre', 'section', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul', 'center', 'body', 'html',
  'caption', 'option', 'button', 'details', 'summary',
};

/// Numeric references in the C1 range are interpreted as Windows-1252, as
/// browsers do.
const _windows1252 = <int, int>{
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, //
  0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
  0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
  0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
};

const _namedEntities = <String, String>{
  'amp': '&', 'AMP': '&', 'lt': '<', 'LT': '<', 'gt': '>', 'GT': '>', 'quot': '"', 'QUOT': '"', //
  'apos': "'", 'nbsp': ' ', 'ensp': ' ', 'emsp': ' ', 'thinsp': ' ', 'zwnj': '‌',
  'zwj': '‍', 'shy': '­', 'ndash': '–', 'mdash': '—', 'lsquo': '‘',
  'rsquo': '’', 'sbquo': '‚', 'ldquo': '“', 'rdquo': '”', 'bdquo': '„',
  'laquo': '«', 'raquo': '»', 'lsaquo': '‹', 'rsaquo': '›', 'hellip': '…',
  'bull': '•', 'middot': '·', 'copy': '©', 'COPY': '©', 'reg': '®', 'REG': '®',
  'trade': '™', 'euro': '€', 'pound': '£', 'yen': '¥', 'cent': '¢', 'curren': '¤',
  'sect': '§', 'para': '¶', 'deg': '°', 'plusmn': '±', 'times': '×',
  'divide': '÷', 'micro': 'µ', 'frac12': '½', 'frac14': '¼', 'frac34': '¾',
  'iexcl': '¡', 'iquest': '¿', 'dagger': '†', 'Dagger': '‡', 'permil': '‰',
  'prime': '′', 'larr': '←', 'rarr': '→', 'uarr': '↑', 'darr': '↓',
  'harr': '↔', 'hearts': '♥', 'check': '✓', 'star': '☆', 'ordf': 'ª', 'ordm': 'º',
  'sup1': '¹', 'sup2': '²', 'sup3': '³', 'acute': '´', 'uml': '¨', 'macr': '¯',
  'cedil': '¸', 'not': '¬', 'brvbar': '¦',
  'Agrave': 'À', 'Aacute': 'Á', 'Acirc': 'Â', 'Atilde': 'Ã', 'Auml': 'Ä',
  'Aring': 'Å', 'AElig': 'Æ', 'Ccedil': 'Ç', 'Egrave': 'È', 'Eacute': 'É',
  'Ecirc': 'Ê', 'Euml': 'Ë', 'Igrave': 'Ì', 'Iacute': 'Í', 'Icirc': 'Î',
  'Iuml': 'Ï', 'ETH': 'Ð', 'Ntilde': 'Ñ', 'Ograve': 'Ò', 'Oacute': 'Ó',
  'Ocirc': 'Ô', 'Otilde': 'Õ', 'Ouml': 'Ö', 'Oslash': 'Ø', 'Ugrave': 'Ù',
  'Uacute': 'Ú', 'Ucirc': 'Û', 'Uuml': 'Ü', 'Yacute': 'Ý', 'THORN': 'Þ',
  'szlig': 'ß', 'agrave': 'à', 'aacute': 'á', 'acirc': 'â', 'atilde': 'ã',
  'auml': 'ä', 'aring': 'å', 'aelig': 'æ', 'ccedil': 'ç', 'egrave': 'è',
  'eacute': 'é', 'ecirc': 'ê', 'euml': 'ë', 'igrave': 'ì', 'iacute': 'í',
  'icirc': 'î', 'iuml': 'ï', 'eth': 'ð', 'ntilde': 'ñ', 'ograve': 'ò',
  'oacute': 'ó', 'ocirc': 'ô', 'otilde': 'õ', 'ouml': 'ö', 'oslash': 'ø',
  'ugrave': 'ù', 'uacute': 'ú', 'ucirc': 'û', 'uuml': 'ü', 'yacute': 'ý',
  'thorn': 'þ', 'yuml': 'ÿ', 'OElig': 'Œ', 'oelig': 'œ', 'Scaron': 'Š',
  'scaron': 'š', 'Yuml': 'Ÿ', 'fnof': 'ƒ', 'circ': 'ˆ', 'tilde': '˜',
};
