import 'dart:convert';
import 'dart:typed_data';

/// An inline part referenced from HTML with a `cid:` URL.
typedef InlinePart = ({String mimeType, Uint8List bytes});

/// A message's HTML, made ready for the mail renderer.
final class MailDocument {
  const MailDocument({required this.html, required this.hasRemoteContent});

  final String html;

  /// Whether the message loads images or styles from the internet (beyond
  /// tracking pixels, which are always removed).
  final bool hasRemoteContent;
}

/// Content IDs referenced by `cid:` URLs in [html], normalised with
/// [normalizeContentId].
Set<String> referencedContentIds(String html) =>
    {for (final m in _cidUrl.allMatches(html)) normalizeContentId(m.group(1)!)};

/// The form of a Content-ID used as a key for [buildMailDocument]'s
/// `inlineParts`: unescaped, without angle brackets, lower-cased.
String normalizeContentId(String cid) {
  var decoded = cid;
  try {
    decoded = Uri.decodeComponent(cid);
  } on ArgumentError {
    // Not percent-encoded after all.
  }
  return decoded.replaceAll(RegExp('[<>]'), '').trim().toLowerCase();
}

/// Builds the document the renderer loads from a message's [html].
///
/// A Content Security Policy at the top of the document blocks remote
/// content unless [allowRemote] is set, along with scripts, frames, plugins
/// and forms (the renderer also disables scripts). `cid:` references are
/// replaced with the [inlineParts] they name, and tracking pixels are
/// dropped. Designed mail is always laid out in its light colour scheme;
/// the reader decides how to present it.
MailDocument buildMailDocument(
  String html, {
  required bool allowRemote,
  Map<String, InlinePart> inlineParts = const {},
}) {
  var hasRemote = false;
  var out = html
      .replaceAll(_script, '')
      .replaceAll(_metaRefresh, '')
      .replaceAll(_metaCharset, '')
      .replaceAll(_metaColorScheme, '')
      // Media queries for dark mode never match; light ones always do.
      .replaceAllMapped(_prefersColorScheme,
          (m) => m.group(1)!.toLowerCase() == 'dark' ? '(max-width: 0px)' : '(min-width: 0px)');

  out = out.replaceAllMapped(_imgTag, (m) {
    final tag = m.group(0)!;
    final attrs = _attributes(tag);
    final src = attrs['src']?.trim() ?? '';
    if (_isRemote(src)) {
      if (_isTrackingPixel(attrs)) return '';
      hasRemote = true;
      if (!allowRemote) {
        return _rewriteTag(tag, {'src': _placeholder(attrs), 'data-plume-blocked': ''}, remove: {'srcset', 'loading'});
      }
      return _rewriteTag(tag, const {}, remove: {'loading'});
    }
    if (src.toLowerCase().startsWith('cid:')) {
      final data = _dataUrl(inlineParts[normalizeContentId(src.substring(4))]);
      if (data != null) return _rewriteTag(tag, {'src': data}, remove: {'loading'});
    }
    return _rewriteTag(tag, const {}, remove: {'loading'});
  });

  // Inline parts used as backgrounds.
  out = out.replaceAllMapped(_cidUrl, (m) => _dataUrl(inlineParts[normalizeContentId(m.group(1)!)]) ?? m.group(0)!);
  if (!hasRemote && _remoteStyle.hasMatch(out)) hasRemote = true;

  final remote = allowRemote ? ' https: http:' : '';
  final csp = "default-src 'none'; img-src data: plume:$remote; style-src 'unsafe-inline' plume:$remote; "
      "font-src data: plume:$remote; form-action 'none'";
  final head = '<meta http-equiv="Content-Security-Policy" content="$csp"><style>$_baseStyle</style>';

  // The policy must come before anything that loads, but after a doctype so
  // the document keeps its rendering mode.
  final doctype = _leadingDoctype.firstMatch(out);
  final at = doctype?.end ?? 0;
  out = '${out.substring(0, at)}$head${out.substring(at)}';
  return MailDocument(html: out, hasRemoteContent: hasRemote);
}

/// Typography and resets every message starts from. The message's own
/// styles come later and win.
const _baseStyle = '''
@font-face { font-family: "Plume Sans"; src: url("plume://mail/fonts/plume-sans.ttf"); font-weight: 100 1000; font-stretch: 25% 151%; }
:root { color-scheme: light only; -webkit-text-size-adjust: 100%; }
body { margin: 0; overflow-wrap: break-word; }
pre { white-space: pre-wrap; }
img[data-plume-blocked] { background: rgba(127, 127, 127, 0.12); }
''';

const _transparentGif = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

/// An empty image with the blocked image's declared size, so the layout
/// (including its aspect ratio when scaled) is kept.
String _placeholder(Map<String, String> attrs) {
  final w = int.tryParse(attrs['width']?.trim() ?? '');
  final h = int.tryParse(attrs['height']?.trim() ?? '');
  if (w == null || h == null || w <= 0 || h <= 0) return _transparentGif;
  return "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='$w' height='$h'/%3E";
}

final _script = RegExp(r'<script\b[^>]*>[\s\S]*?</script\s*>', caseSensitive: false);
final _metaRefresh = RegExp(r'''<meta\b[^>]*http-equiv\s*=\s*["']?refresh[^>]*>''', caseSensitive: false);
final _metaCharset =
    RegExp(r'''<meta\b[^>]*(?:\bcharset\s*=|http-equiv\s*=\s*["']?content-type)[^>]*>''', caseSensitive: false);
final _metaColorScheme =
    RegExp(r'''<meta\b[^>]*name\s*=\s*["']?(?:supported-)?color-scheme[^>]*>''', caseSensitive: false);
final _prefersColorScheme = RegExp(r'\(\s*prefers-color-scheme\s*:\s*(dark|light)\s*\)', caseSensitive: false);
final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _attribute = RegExp(r'''([^\s"'<>/=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+))?''');
final _cidUrl = RegExp(r'''\bcid:([^\s"'()<>]+)''', caseSensitive: false);
final _remoteStyle = RegExp(r'''(?:url\(\s*["']?|\bbackground\s*=\s*["']?)(?:https?:)?//''', caseSensitive: false);
final _leadingDoctype = RegExp(r'^\s*(?:<!--[\s\S]*?-->\s*)*<!doctype[^>]*>', caseSensitive: false);

bool _isRemote(String url) {
  final lower = url.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('//');
}

/// Images of at most 2×2 pixels exist only to report that mail was opened.
bool _isTrackingPixel(Map<String, String> attrs) {
  double? px(String? v) => v == null ? null : double.tryParse(v.trim().replaceAll(RegExp(r'px$'), ''));
  final style = attrs['style'] ?? '';
  final w = px(attrs['width']) ?? px(RegExp(r'(?:^|;)\s*width\s*:\s*([\d.]+)px').firstMatch(style)?.group(1));
  final h = px(attrs['height']) ?? px(RegExp(r'(?:^|;)\s*height\s*:\s*([\d.]+)px').firstMatch(style)?.group(1));
  return (w != null && w <= 2) || (h != null && h <= 2);
}

String? _dataUrl(InlinePart? part) =>
    part == null ? null : 'data:${part.mimeType};base64,${base64Encode(part.bytes)}';

/// Attributes of an `<img>` tag, lower-cased names to unquoted values.
Map<String, String> _attributes(String tag) {
  final inner = tag.substring(4, tag.length - 1);
  final attrs = <String, String>{};
  for (final m in _attribute.allMatches(inner)) {
    var value = m.group(2) ?? '';
    if (value.length >= 2 && (value.startsWith('"') || value.startsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    attrs.putIfAbsent(m.group(1)!.toLowerCase(), () => _decodeEntities(value));
  }
  return attrs;
}

/// Rebuilds an `<img>` tag with [set] attributes replaced or added and
/// [remove] attributes dropped.
String _rewriteTag(String tag, Map<String, String> set, {Set<String> remove = const {}}) {
  final attrs = _attributes(tag);
  if (set.isEmpty && !remove.any(attrs.containsKey)) return tag;
  final merged = {
    for (final e in attrs.entries)
      if (!remove.contains(e.key) && !set.containsKey(e.key)) e.key: e.value,
    ...set,
  };
  final buffer = StringBuffer('<img');
  for (final e in merged.entries) {
    buffer.write(' ${e.key}');
    if (e.value.isNotEmpty) buffer.write('="${_escapeAttribute(e.value)}"');
  }
  buffer.write('>');
  return buffer.toString();
}

String _escapeAttribute(String value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

String _decodeEntities(String value) => value.contains('&')
    ? value
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
    : value;
