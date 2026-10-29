import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Text sizes the composer offers, by their Quill `size` value. [scale] is
/// against body text and [css] the keyword the size is sent as, so it follows
/// the reader's own default size.
enum TextSize {
  small('small', 13 / 16, 'small', 'Small'),
  normal(null, 1, null, 'Normal'),
  large('large', 1.5, 'x-large', 'Large'),
  huge('huge', 2, 'xx-large', 'Huge');

  const TextSize(this.value, this.scale, this.css, this.label);

  final String? value;
  final double scale;
  final String? css;
  final String label;

  static TextSize of(Object? value) => values.firstWhere((s) => s.value == value, orElse: () => normal);
}

/// Text colours the composer offers. Mid tones, so text stays readable on
/// the white most mail is read on and on the dark compose window.
const textColors = <(String, Color)>[
  ('Red', Color(0xFFD93025)),
  ('Orange', Color(0xFFE8710A)),
  ('Amber', Color(0xFFC88A00)),
  ('Green', Color(0xFF1E8E3E)),
  ('Teal', Color(0xFF00897B)),
  ('Blue', Color(0xFF1A73E8)),
  ('Indigo', Color(0xFF5C6BC0)),
  ('Purple', Color(0xFF9334E6)),
  ('Pink', Color(0xFFD01884)),
  ('Grey', Color(0xFF80868B)),
];

/// `#rrggbb` for [color], as Quill and HTML store it.
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The colour of a stored `#rrggbb` value, or null for anything else.
Color? colorFromHex(Object? value) {
  if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

/// Inline attributes "remove formatting" takes away.
const _inlineKeys = ['bold', 'italic', 'underline', 'strike', 'link', 'color', 'size', 'background'];

/// An empty body, or one holding [text] without formatting.
Document documentFromText(String? text) {
  final delta = Delta();
  final t = text?.replaceAll('\r\n', '\n').trimRight() ?? '';
  if (t.isNotEmpty) delta.insert(t);
  delta.insert('\n');
  return Document.fromDelta(delta);
}

/// A body holding [html] as written by [MailDocument.toMailHtml] or another
/// client. Unsupported markup is reduced to its text.
Document documentFromHtml(String html) => Document.fromDelta(_HtmlReader(html).read());

/// A line of a document: runs of text with their inline attributes, and the
/// line's own attributes (list, indent, quote).
class _Line {
  final runs = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> attrs = const {};

  bool get isBlank => runs.every((r) => r.$1.trim().isEmpty);

  String? get list => switch (attrs['list']) {
        'ordered' => 'ordered',
        null => null,
        _ => 'bullet',
      };
  int get indent => (attrs['indent'] as int?) ?? 0;
  bool get quote => attrs['blockquote'] == true;
}

extension MailDocument on Document {
  /// The lines up to the last one with text.
  List<_Line> _lines() {
    final lines = <_Line>[];
    var line = _Line();
    for (final op in toDelta().operations) {
      final data = op.data;
      if (data is! String) continue;
      final attrs = op.attributes ?? const <String, dynamic>{};
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) line.runs.add((parts[i], attrs));
        if (i < parts.length - 1) {
          line.attrs = attrs;
          lines.add(line);
          line = _Line();
        }
      }
    }
    if (line.runs.isNotEmpty) lines.add(line);
    while (lines.isNotEmpty && lines.last.isBlank) {
      lines.removeLast();
    }
    return lines;
  }

  bool get isBlank => _lines().isEmpty;

  /// Whether any text or line is formatted.
  bool get hasFormatting => toDelta().operations.any((op) => op.attributes?.isNotEmpty ?? false);

  /// The body as HTML, one `<div>` per line, lists as nested `<ul>`/`<ol>`,
  /// quotes as bordered `<blockquote>`s and indents as Gmail writes them.
  /// Trailing blank lines are dropped.
  String toMailHtml() {
    final lines = _lines();
    if (lines.isEmpty) return '';
    final out = StringBuffer();
    // Open containers, outermost first: 'ul', 'ol', 'quote' or 'indent',
    // and whether a list's last item is still open.
    final open = <(String, bool)>[];
    void close(int keep) {
      while (open.length > keep) {
        final (kind, item) = open.removeLast();
        if (item) out.write('</li>');
        out.write(switch (kind) { 'ul' => '</ul>', 'ol' => '</ol>', _ => '</blockquote>' });
      }
    }

    for (final line in lines) {
      final list = line.list;
      final path = <String>[];
      if (list != null) {
        // A nested item goes inside the open item one level up; with none,
        // the list is indented instead.
        for (var i = 0; i < line.indent; i++) {
          final kind = i < open.length ? open[i].$1 : null;
          path.add(kind == 'ul' || kind == 'ol' || kind == 'indent' ? kind! : 'indent');
        }
        path.add(list == 'ordered' ? 'ol' : 'ul');
      } else {
        if (line.quote) path.add('quote');
        path.addAll(List.filled(line.indent, 'indent'));
      }
      var keep = 0;
      while (keep < open.length && keep < path.length && open[keep].$1 == path[keep]) {
        keep++;
      }
      close(keep);
      for (var i = keep; i < path.length; i++) {
        out.write(switch (path[i]) {
          'ul' => '<ul style="margin:0;padding-left:1.5em;list-style-type:${const ['disc', 'circle', 'square'][i % 3]}">',
          'ol' =>
            '<ol style="margin:0;padding-left:1.5em;list-style-type:${const ['decimal', 'lower-alpha', 'lower-roman'][i % 3]}">',
          'quote' => '<blockquote style="margin:0 0 0 0.8ex;border-left:3px solid #ccc;padding-left:1ex">',
          _ => '<blockquote style="margin:0 0 0 40px;border:none;padding:0">',
        });
        open.add((path[i], false));
      }
      final inline = _inlineHtml(line.runs);
      final content = inline.isEmpty ? '<br>' : inline;
      if (list != null) {
        if (open.last.$2) out.write('</li>');
        out.write('<li>$content');
        open.last = (open.last.$1, true);
      } else {
        out.write('<div>$content</div>');
      }
    }
    close(0);
    return out.toString();
  }

  static String _inlineHtml(List<(String, Map<String, dynamic>)> runs) {
    final out = StringBuffer();
    for (final (i, (text, a)) in runs.indexed) {
      var t = _escape(text).replaceAll('  ', ' &nbsp;');
      // HTML drops spaces at the start of a line.
      if (i == 0 && t.startsWith(' ')) t = '&nbsp;${t.substring(1)}';
      final link = a['link'] as String?;
      if (link == null) t = linkifyHtml(t);
      if (a['strike'] == true) t = '<s>$t</s>';
      if (a['underline'] == true) t = '<u>$t</u>';
      if (a['italic'] == true) t = '<i>$t</i>';
      if (a['bold'] == true) t = '<b>$t</b>';
      final color = colorFromHex(a['color']);
      final size = TextSize.of(a['size']).css;
      final css = [if (color != null) 'color:${colorToHex(color)}', if (size != null) 'font-size:$size'];
      if (css.isNotEmpty) t = '<span style="${css.join(';')}">$t</span>';
      if (link != null) t = '<a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(link)}">$t</a>';
      out.write(t);
    }
    return out.toString();
  }

  /// The body as plain text: lists with `-` and numbers, nested items and
  /// indents led by spaces, quotes by `>`, and links as `text <url>`. With
  /// [marks], styles are written the way mail clients read them in plain
  /// text (`*bold*`, `/italic/`, `_underline_`), as the `text/plain`
  /// alternative does.
  String toMailText({bool marks = true}) {
    final out = <String>[];
    // The number reached at each level of the current numbered list.
    final counts = <int>[];
    for (final line in _lines()) {
      final list = line.list;
      if (list == null && line.isBlank) {
        counts.clear();
        out.add(line.quote ? '>' : '');
        continue;
      }
      final prefix = StringBuffer(line.quote ? '> ' : '');
      final level = line.indent;
      if (list == null) {
        counts.clear();
        prefix.write('    ' * level);
      } else {
        prefix.write('  ' * level);
        if (list == 'ordered') {
          if (counts.length > level + 1) counts.removeRange(level + 1, counts.length);
          while (counts.length <= level) {
            counts.add(0);
          }
          counts[level]++;
          prefix.write('${listNumber(counts[level], level)}. ');
        } else {
          if (counts.length > level) counts.removeRange(level, counts.length);
          prefix.write('- ');
        }
      }
      for (final (text, a) in line.runs) {
        final core = text.trim();
        if (core.isEmpty) {
          prefix.write(text);
          continue;
        }
        var marked = core;
        if (marks) {
          if (a['underline'] == true) marked = '_${marked}_';
          if (a['italic'] == true) marked = '/$marked/';
          if (a['bold'] == true) marked = '*$marked*';
        }
        final link = a['link'] as String?;
        if (link != null && link != core && link != 'mailto:$core') marked = '$marked <$link>';
        final lead = text.length - text.trimLeft().length;
        prefix.write('${text.substring(0, lead)}$marked${text.substring(lead + core.length)}');
      }
      out.add(prefix.toString());
    }
    return out.join('\n');
  }
}

/// The marker of item [n] of a numbered list nested [level] deep: `1`, then
/// `a`, then `i`, as the editor and HTML number them.
String listNumber(int n, int level) => switch (level % 3) {
      1 => _letters(n),
      2 => _roman(n),
      _ => '$n',
    };

String _letters(int n) {
  final out = StringBuffer();
  while (n > 0) {
    n--;
    out.write(String.fromCharCode(97 + n % 26));
    n ~/= 26;
  }
  return out.toString().split('').reversed.join();
}

String _roman(int n) {
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i'];
  final out = StringBuffer();
  for (var i = 0; i < values.length; i++) {
    while (n >= values[i]) {
      out.write(symbols[i]);
      n -= values[i];
    }
  }
  return out.toString();
}

/// Formatting commands on the compose body.
extension Formatting on QuillController {
  Map<String, Attribute<Object?>> get _style => getSelectionStyle().attributes;

  /// Whether the inline or line [attribute] applies to the selection, or to
  /// typing at the caret.
  bool isActive(Attribute<Object?> attribute) {
    final current = _style[attribute.key];
    return current != null && current.value == attribute.value;
  }

  /// Turns [attribute] on for the selection, or off when all of it has it.
  /// With no selection, inline styles apply to what is typed next.
  void toggle(Attribute<Object?> attribute) =>
      formatSelection(isActive(attribute) ? Attribute.clone(attribute, null) : attribute);

  TextSize get textSize => TextSize.of(_style[Attribute.size.key]?.value);

  void setTextSize(TextSize size) => formatSelection(SizeAttribute(size.value));

  /// The colour of the selection, null for the default.
  Color? get textColor => colorFromHex(_style[Attribute.color.key]?.value);

  void setTextColor(Color? color) => formatSelection(ColorAttribute(color == null ? null : colorToHex(color)));

  /// `bullet` or `ordered` when every selected line is in that list.
  String? get listKind => switch (_style[Attribute.list.key]?.value) {
        'bullet' => 'bullet',
        'ordered' => 'ordered',
        _ => null,
      };

  int get indentLevel => (_style[Attribute.indent.key]?.value as int?) ?? 0;

  /// Removes text styles, colours, sizes and links from the selection, or
  /// from typing at the caret. Lists, quotes and indents stay.
  void clearFormatting() {
    for (final key in _inlineKeys) {
      formatSelection(Attribute.fromKeyValue(key, null));
    }
  }

  /// The link around the caret, or the one covering the whole selection.
  TextRange? linkRange() {
    if (!selection.isValid) return null;
    var at = selection.start;
    // At the end of a link, the caret is still on it.
    if (selection.isCollapsed && linkAt(at) == null && at > 0) at--;
    final leaf = document.querySegmentLeafNode(at).leaf;
    if (leaf == null || linkAt(at) == null) return null;
    final range = getLinkRange(leaf);
    if (selection.start < range.start || selection.end > range.end) return null;
    return range;
  }

  String? linkAt(int offset) =>
      document.querySegmentLeafNode(offset).leaf?.style.attributes[Attribute.link.key]?.value as String?;

  /// Links [range] to [url] (none removes the link), replacing its text with
  /// [label] if that differs. A collapsed range inserts [label] at the caret.
  void setLink(TextRange range, String label, String? url) {
    if (label.isEmpty) label = url ?? '';
    final current = document.getPlainText(range.start, range.end - range.start);
    if (current != label) {
      replaceText(range.start, range.end - range.start, label, null);
    }
    formatText(range.start, label.length, LinkAttribute(url));
    // Typing on after the link does not extend it: Quill stops links at
    // their text.
    updateSelection(TextSelection.collapsed(offset: range.start + label.length), ChangeSource.local);
  }
}

// Helpers -----------------------------------------------------------------------

String _escape(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

/// Makes bare web addresses in escaped HTML text clickable.
String linkifyHtml(String escaped) => escaped.replaceAllMapped(
    RegExp(r'(https?://[^\s<>"]+[^\s<>".,;:!?)\]])'), (m) => '<a href="${m[1]}">${m[1]}</a>');

/// Normalises a typed link: bare addresses become `mailto:`, anything else
/// without a scheme `https://`. Returns null for an empty or unsafe link.
String? normalizeLink(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(s)?[1]?.toLowerCase();
  if (scheme != null) return const {'http', 'https', 'mailto'}.contains(scheme) ? s : null;
  if (RegExp(r'^[^\s@/]+@[^\s@/]+\.[^\s@/]+$').hasMatch(s)) return 'mailto:$s';
  return 'https://$s';
}

/// Reads the subset of HTML that mail editors write back into lines of text
/// with styles, links, lists, quotes and indents.
class _HtmlReader {
  _HtmlReader(this.html);

  final String html;
  final _lines = <_Line>[];
  var _line = _Line();

  /// Open inline elements and the attributes each gives its text.
  final _inline = <(String, Map<String, dynamic>)>[];
  final _hrefs = <String?>[];

  /// Open block elements: `ul`, `ol`, `quote`, `indent`, or another tag
  /// with the indent its margin gives.
  final _blocks = <(String, int)>[];

  static const _flags = {
    'b': 'bold',
    'strong': 'bold',
    'i': 'italic',
    'em': 'italic',
    'u': 'underline',
    'ins': 'underline',
    's': 'strike',
    'strike': 'strike',
    'del': 'strike',
  };
  static const _blockTags = {
    'div', 'p', 'li', 'ul', 'ol', 'blockquote', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', //
  };

  /// The line has started, if only as an empty list item.
  var _lineOpen = false;

  /// Text was written on the current line.
  var _lineHasText = false;

  Map<String, dynamic> get _style => {for (final (_, attrs) in _inline) ...attrs};

  /// The attributes of a line starting here; [item] for a list item.
  Map<String, dynamic> _blockAttrs({bool item = false}) {
    final lists = [for (final (kind, _) in _blocks) if (kind == 'ul' || kind == 'ol') kind];
    var indent = 0;
    for (final (kind, margin) in _blocks) {
      indent += kind == 'indent' ? 1 : margin;
    }
    if (item && lists.isNotEmpty) {
      indent += lists.length - 1;
      return {'list': lists.last == 'ol' ? 'ordered' : 'bullet', if (indent > 0) 'indent': math.min(indent, 5)};
    }
    indent += lists.length;
    return {
      if (_blocks.any((b) => b.$1 == 'quote')) 'blockquote': true,
      if (indent > 0) 'indent': math.min(indent, 5),
    };
  }

  void _openLine({bool item = false}) {
    if (_lineOpen) return;
    _line.attrs = _blockAttrs(item: item);
    _lineOpen = true;
  }

  void _write(String s) {
    if (s.isEmpty) return;
    _openLine();
    final attrs = {..._style, 'link': ?_hrefs.lastOrNull};
    _line.runs.add((s, attrs));
    _lineHasText = true;
  }

  void _newline() {
    _openLine();
    _lines.add(_line);
    _line = _Line();
    _lineOpen = _lineHasText = false;
  }

  Delta read() {
    final source = html.replaceAll(
        RegExp(r'<!--[\s\S]*?-->|<(head|style|script|title)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false), '');
    final token = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)|<');
    for (final m in token.allMatches(source)) {
      if (m[4] != null || m[2] == null) {
        final raw = (m[4] ?? '<').replaceAll(RegExp(r'\s+'), ' ');
        _write(_decode(_lineHasText ? raw : raw.trimLeft()));
        continue;
      }
      final closing = m[1]!.isNotEmpty;
      final tag = m[2]!.toLowerCase();
      final attrs = m[3]!;
      if (tag == 'br') {
        _newline();
      } else if (_flags.containsKey(tag) || tag == 'span' || tag == 'font') {
        if (closing) {
          final i = _inline.lastIndexWhere((e) => e.$1 == tag);
          if (i >= 0) _inline.removeAt(i);
        } else {
          _inline.add((tag, {?_flags[tag]: true, ..._styleAttrs(tag, attrs)}));
        }
      } else if (tag == 'a') {
        if (closing) {
          if (_hrefs.isNotEmpty) _hrefs.removeLast();
        } else {
          final href = RegExp(r'''href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''', caseSensitive: false).firstMatch(attrs);
          final url = href == null ? null : _decode(href[2] ?? href[3] ?? href[4]!);
          _hrefs.add(url == null ? null : normalizeLink(url));
        }
      } else if (_blockTags.contains(tag)) {
        // A closing list item ends its line even when empty; anything else
        // only once it holds text (`<li><div>…`).
        if (_lineHasText || (closing && _lineOpen && const {'li', 'ul', 'ol', 'blockquote'}.contains(tag))) {
          _newline();
        }
        if (closing) {
          if (tag == 'li') continue;
          final kind = switch (tag) { 'blockquote' => const {'quote', 'indent'}, _ => {tag} };
          final i = _blocks.lastIndexWhere((b) => kind.contains(b.$1));
          if (i >= 0) _blocks.removeRange(i, _blocks.length);
        } else {
          switch (tag) {
            case 'ul' || 'ol':
              _blocks.add((tag, 0));
            case 'blockquote':
              // Gmail indents with borderless blockquotes.
              final style = _attr(attrs, 'style')?.replaceAll(' ', '').toLowerCase() ?? '';
              _blocks.add((style.contains('border:none') || style.contains('border-left:none') ? 'indent' : 'quote', 0));
            case 'li':
              if (_lineOpen) _newline();
              _openLine(item: true);
            default:
              _blocks.add((tag, _marginIndent(attrs)));
          }
        }
      }
    }
    if (_lineOpen || _lineHasText) _newline();
    while (_lines.isNotEmpty && _lines.last.isBlank) {
      _lines.removeLast();
    }
    final delta = Delta();
    for (final line in _lines) {
      for (final (text, attrs) in line.runs) {
        delta.insert(text, attrs.isEmpty ? null : attrs);
      }
      delta.insert('\n', line.attrs.isEmpty ? null : line.attrs);
    }
    if (delta.isEmpty) delta.insert('\n');
    return delta;
  }

  static String? _attr(String attrs, String name) {
    final m = RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(attrs);
    return m == null ? null : _decode(m[2] ?? m[3] ?? m[4]!);
  }

  /// Text attributes from a `style`, or a `<font>`'s `color` and `size`.
  static Map<String, dynamic> _styleAttrs(String tag, String attrs) {
    final out = <String, dynamic>{};
    final css = <String, String>{
      for (final decl in (_attr(attrs, 'style') ?? '').split(';'))
        if (decl.indexOf(':') case final i when i > 0)
          decl.substring(0, i).trim().toLowerCase(): decl.substring(i + 1).trim().toLowerCase(),
    };
    final color = _parseColor(css['color'] ?? (tag == 'font' ? _attr(attrs, 'color') : null));
    if (color != null) out['color'] = color;
    final size = css['font-size'] != null
        ? _cssSize(css['font-size']!)
        : tag == 'font'
            ? switch (_attr(attrs, 'size')?.trim()) {
                '1' || '2' => TextSize.small,
                '4' || '5' => TextSize.large,
                '6' || '7' => TextSize.huge,
                _ => null,
              }
            : null;
    if (size?.value != null) out['size'] = size!.value;
    final weight = css['font-weight'];
    if (weight == 'bold' || weight == 'bolder' || (int.tryParse(weight ?? '') ?? 0) >= 600) out['bold'] = true;
    if (css['font-style'] == 'italic') out['italic'] = true;
    final decoration = css['text-decoration'] ?? css['text-decoration-line'] ?? '';
    if (decoration.contains('underline')) out['underline'] = true;
    if (decoration.contains('line-through')) out['strike'] = true;
    return out;
  }

  static TextSize? _cssSize(String v) {
    switch (v) {
      case 'xx-small' || 'x-small' || 'small' || 'smaller':
        return TextSize.small;
      case 'large' || 'x-large' || 'larger':
        return TextSize.large;
      case 'xx-large' || 'xxx-large':
        return TextSize.huge;
    }
    final m = RegExp(r'^([\d.]+)(px|pt|em|rem|%)$').firstMatch(v);
    final n = double.tryParse(m?[1] ?? '');
    if (n == null) return null;
    final px = switch (m![2]) { 'pt' => n * 4 / 3, 'em' || 'rem' => n * 16, '%' => n * 0.16, _ => n };
    return px < 14.5 ? TextSize.small : (px < 17.5 ? null : (px < 27 ? TextSize.large : TextSize.huge));
  }

  /// `#rrggbb` for a CSS colour. Black and white are left out: they are
  /// another client's default, and would vanish on the dark compose window.
  static String? _parseColor(String? v) {
    if (v == null) return null;
    v = v.trim().toLowerCase();
    int? rgb;
    if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) {
      rgb = int.parse(v.substring(1), radix: 16);
    } else if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(v)) {
      rgb = int.parse(v.substring(1).split('').map((c) => '$c$c').join(), radix: 16);
    } else if (RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(v) case final m?) {
      rgb = [m[1], m[2], m[3]].fold<int>(0, (acc, c) => (acc << 8) | int.parse(c!).clamp(0, 255));
    }
    if (rgb == null) return null;
    final luminance = Color(0xFF000000 | rgb).computeLuminance();
    if (luminance < 0.02 || luminance > 0.85) return null;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// Indent levels from a block's left margin, as Outlook indents.
  static int _marginIndent(String attrs) {
    final style = (_attr(attrs, 'style') ?? '').toLowerCase();
    final m = RegExp(r'margin-left\s*:\s*([\d.]+)(px|pt|em|in)').firstMatch(style);
    final n = double.tryParse(m?[1] ?? '');
    if (n == null) return 0;
    final px = switch (m![2]) { 'pt' => n * 4 / 3, 'em' => n * 16, 'in' => n * 96, _ => n };
    return (px / 40).round().clamp(0, 5);
  }

  static String _decode(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
        final e = m[1]!;
        if (e.startsWith('#x') || e.startsWith('#X')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
        if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
        return switch (e) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'nbsp' => ' ',
          _ => m[0]!,
        };
      });
}
