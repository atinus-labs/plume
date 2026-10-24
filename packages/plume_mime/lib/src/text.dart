/// Text helpers: HTML entity decoding, snippets, RFC 5322 dates and
/// format=flowed.
library;

/// Decodes HTML character references (`&amp;`, `&#39;`, `&#x1F600;`...).
/// Gmail API snippets are HTML-escaped. Unknown references are kept
/// verbatim.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  return input.replaceAllMapped(RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#\d{1,7}|[A-Za-z][A-Za-z0-9]{1,31});'), (m) {
    final ref = m.group(1)!;
    if (ref.startsWith('#')) {
      final isHex = ref.length > 1 && (ref[1] == 'x' || ref[1] == 'X');
      final code = int.tryParse(isHex ? ref.substring(2) : ref.substring(1), radix: isHex ? 16 : 10);
      if (code == null || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return '�';
      return String.fromCharCode(code);
    }
    final named = _namedEntities[ref] ?? _namedEntities[ref.toLowerCase()];
    return named == null ? m.group(0)! : String.fromCharCode(named);
  });
}

/// Cleans a snippet for display: decodes entities, removes the invisible
/// padding characters newsletters stuff into preheaders, and collapses
/// whitespace.
String cleanSnippet(String snippet) => _collapseWhitespace(decodeHtmlEntities(snippet));

/// Removes invisible padding characters and collapses whitespace.
String _collapseWhitespace(String text) {
  final stripped = text.replaceAll(RegExp('[\u034F\u00AD\u200B-\u200F\u2060-\u2064\uFEFF\u180E]'), '');
  return stripped.replaceAll(RegExp(r'[\s\u00A0\u2007\u202F]+'), ' ').trim();
}

const Map<String, int> _namedEntities = {
  'amp': 0x26, 'lt': 0x3C, 'gt': 0x3E, 'quot': 0x22, 'apos': 0x27, 'nbsp': 0xA0, //
  'iexcl': 0xA1, 'cent': 0xA2, 'pound': 0xA3, 'curren': 0xA4, 'yen': 0xA5, 'brvbar': 0xA6,
  'sect': 0xA7, 'uml': 0xA8, 'copy': 0xA9, 'ordf': 0xAA, 'laquo': 0xAB, 'not': 0xAC,
  'shy': 0xAD, 'reg': 0xAE, 'macr': 0xAF, 'deg': 0xB0, 'plusmn': 0xB1, 'sup2': 0xB2,
  'sup3': 0xB3, 'acute': 0xB4, 'micro': 0xB5, 'para': 0xB6, 'middot': 0xB7, 'cedil': 0xB8,
  'sup1': 0xB9, 'ordm': 0xBA, 'raquo': 0xBB, 'frac14': 0xBC, 'frac12': 0xBD, 'frac34': 0xBE,
  'iquest': 0xBF, 'Agrave': 0xC0, 'Aacute': 0xC1, 'Acirc': 0xC2, 'Atilde': 0xC3, 'Auml': 0xC4,
  'Aring': 0xC5, 'AElig': 0xC6, 'Ccedil': 0xC7, 'Egrave': 0xC8, 'Eacute': 0xC9, 'Ecirc': 0xCA,
  'Euml': 0xCB, 'Igrave': 0xCC, 'Iacute': 0xCD, 'Icirc': 0xCE, 'Iuml': 0xCF, 'ETH': 0xD0,
  'Ntilde': 0xD1, 'Ograve': 0xD2, 'Oacute': 0xD3, 'Ocirc': 0xD4, 'Otilde': 0xD5, 'Ouml': 0xD6,
  'times': 0xD7, 'Oslash': 0xD8, 'Ugrave': 0xD9, 'Uacute': 0xDA, 'Ucirc': 0xDB, 'Uuml': 0xDC,
  'Yacute': 0xDD, 'THORN': 0xDE, 'szlig': 0xDF, 'agrave': 0xE0, 'aacute': 0xE1, 'acirc': 0xE2,
  'atilde': 0xE3, 'auml': 0xE4, 'aring': 0xE5, 'aelig': 0xE6, 'ccedil': 0xE7, 'egrave': 0xE8,
  'eacute': 0xE9, 'ecirc': 0xEA, 'euml': 0xEB, 'igrave': 0xEC, 'iacute': 0xED, 'icirc': 0xEE,
  'iuml': 0xEF, 'eth': 0xF0, 'ntilde': 0xF1, 'ograve': 0xF2, 'oacute': 0xF3, 'ocirc': 0xF4,
  'otilde': 0xF5, 'ouml': 0xF6, 'divide': 0xF7, 'oslash': 0xF8, 'ugrave': 0xF9, 'uacute': 0xFA,
  'ucirc': 0xFB, 'uuml': 0xFC, 'yacute': 0xFD, 'thorn': 0xFE, 'yuml': 0xFF, 'OElig': 0x152,
  'oelig': 0x153, 'Scaron': 0x160, 'scaron': 0x161, 'Yuml': 0x178, 'fnof': 0x192, 'circ': 0x2C6,
  'tilde': 0x2DC, 'ensp': 0x2002, 'emsp': 0x2003, 'thinsp': 0x2009, 'zwnj': 0x200C, 'zwj': 0x200D,
  'lrm': 0x200E, 'rlm': 0x200F, 'ndash': 0x2013, 'mdash': 0x2014, 'lsquo': 0x2018, 'rsquo': 0x2019,
  'sbquo': 0x201A, 'ldquo': 0x201C, 'rdquo': 0x201D, 'bdquo': 0x201E, 'dagger': 0x2020,
  'Dagger': 0x2021, 'bull': 0x2022, 'hellip': 0x2026, 'permil': 0x2030, 'prime': 0x2032,
  'Prime': 0x2033, 'lsaquo': 0x2039, 'rsaquo': 0x203A, 'euro': 0x20AC, 'trade': 0x2122,
  'larr': 0x2190, 'uarr': 0x2191, 'rarr': 0x2192, 'darr': 0x2193, 'harr': 0x2194, 'minus': 0x2212,
  'le': 0x2264, 'ge': 0x2265, 'ne': 0x2260, 'infin': 0x221E, 'hearts': 0x2665, 'check': 0x2713,
};

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const Map<String, int> _zoneHours = {
  'ut': 0, 'utc': 0, 'gmt': 0, 'z': 0, //
  'est': -5, 'edt': -4, 'cst': -6, 'cdt': -5, 'mst': -7, 'mdt': -6, 'pst': -8, 'pdt': -7,
};

final RegExp _dateRe = RegExp(
  r'^\s*(?:[A-Za-z]{2,}\.?,?\s*)?(\d{1,2})[\s-]+([A-Za-z]{3,})\.?[\s-]+(\d{2,4})\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?(?:\.\d+)?\s*(?:([+-])(\d{2}):?(\d{2})|([A-Za-z]{1,5}))?',
);

/// Parses an RFC 5322 `Date` header leniently. Returns UTC, or null when
/// the value is not recognisable.
DateTime? parseRfc5322Date(String? value) {
  if (value == null) return null;
  final m = _dateRe.firstMatch(value);
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = _months.indexOf(m.group(2)!.substring(0, 3).toLowerCase()) + 1;
  if (month == 0) return null;
  var year = int.parse(m.group(3)!);
  if (m.group(3)!.length == 2) year += year < 50 ? 2000 : 1900;
  if (m.group(3)!.length == 3) year += 1900;
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = m.group(6) == null ? 0 : int.parse(m.group(6)!);
  var offsetMinutes = 0;
  if (m.group(7) != null) {
    final sign = m.group(7) == '-' ? -1 : 1;
    offsetMinutes = sign * (int.parse(m.group(8)!) * 60 + int.parse(m.group(9)!));
  } else if (m.group(10) != null) {
    offsetMinutes = (_zoneHours[m.group(10)!.toLowerCase()] ?? 0) * 60;
  }
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) return null;
  return DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: offsetMinutes));
}

/// Formats [date] for a `Date` header, in the date's own offset.
String formatRfc5322Date(DateTime date) {
  final offset = date.isUtc ? Duration.zero : date.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  final zone = '$sign${two(abs.inHours)}${two(abs.inMinutes % 60)}';
  return '${_weekdays[date.weekday - 1]}, ${date.day} ${_monthNames[date.month - 1]} ${date.year} '
      '${two(date.hour)}:${two(date.minute)}:${two(date.second)} $zone';
}

/// Undoes RFC 3676 `format=flowed`: lines ending in a space are joined with
/// the next line; with `DelSp=yes` that trailing space is removed too.
/// Space-stuffing is undone and quote depth is respected.
String unflowText(String text, {bool delSp = false}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final trailingNewline = lines.length > 1 && lines.last.isEmpty;
  if (trailingNewline) lines.removeLast();
  final out = StringBuffer();
  var paragraph = StringBuffer();
  var paragraphDepth = -1;

  void endParagraph() {
    if (paragraphDepth >= 0) {
      out
        ..write('>' * paragraphDepth)
        ..write(paragraphDepth > 0 ? ' ' : '')
        ..write(paragraph)
        ..write('\n');
    }
    paragraph = StringBuffer();
    paragraphDepth = -1;
  }

  for (final raw in lines) {
    var depth = 0;
    while (depth < raw.length && raw[depth] == '>') {
      depth++;
    }
    var line = raw.substring(depth);
    if (line.startsWith(' ')) line = line.substring(1); // space-stuffing
    final isSignatureSep = line == '-- ';
    final flowed = line.endsWith(' ') && !isSignatureSep;
    if (paragraphDepth >= 0 && depth != paragraphDepth) endParagraph();
    paragraphDepth = depth;
    if (flowed) {
      paragraph.write(delSp ? line.substring(0, line.length - 1) : line);
    } else {
      paragraph.write(line);
      endParagraph();
    }
  }
  if (paragraphDepth >= 0) endParagraph();
  final result = out.toString();
  if (!trailingNewline && result.endsWith('\n')) return result.substring(0, result.length - 1);
  return result;
}

/// Plain text for a message preview from an HTML body: drops `<head>`,
/// `<style>`, `<script>` and comments, removes tags, decodes entities and
/// collapses whitespace. Tolerates truncated input (a partial fetch).
String htmlToPreviewText(String html) {
  var s = html
      .replaceAll(RegExp(r'<!--.*?(-->|$)', dotAll: true), ' ')
      .replaceAll(RegExp(r'<(head|style|script|title)\b[^>]*>.*?(</\1\s*>|$)', caseSensitive: false, dotAll: true), ' ');
  // Block-level boundaries become spaces so words do not run together.
  s = s.replaceAll(RegExp(r'<[^>]*(>|$)'), ' ');
  return cleanSnippet(s);
}

/// A preview of at most [maxLength] characters from body text, cut at a
/// word boundary when possible. Quoted reply lines (`> ...`) are skipped.
String previewSnippet(String text, {int maxLength = 200}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n').where((l) => !l.trimLeft().startsWith('>'));
  final clean = _collapseWhitespace(lines.join(' '));
  if (clean.length <= maxLength) return clean;
  final cut = clean.lastIndexOf(' ', maxLength);
  return clean.substring(0, cut > maxLength ~/ 2 ? cut : maxLength).trimRight();
}
