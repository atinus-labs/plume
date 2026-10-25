import 'dart:convert';

import 'package:flutter/material.dart';

/// Inline text styles, as bit flags.
abstract final class InlineStyle {
  static const bold = 1;
  static const italic = 2;
  static const underline = 4;
  static const strike = 8;
}

enum ListKind { bullet, numbered }

const _bullet = '• ';
final _numbered = RegExp(r'(\d{1,3})\. ');

/// A text controller for the compose body that keeps formatting alongside
/// the text, like the rich editors of other mail clients.
///
/// Inline styles and links are kept per character and follow edits. Lists are
/// part of the text: a line starting with `• ` is a bulleted item and one
/// starting with `1. ` a numbered item, so they stay readable in plain text.
/// Enter continues a list, Enter on an empty item ends it, and Backspace
/// after a marker removes it. Numbered items are renumbered as they change.
class RichTextController extends TextEditingController {
  RichTextController({super.text})
      : _styles = List.filled(text?.length ?? 0, 0, growable: true),
        _links = List.filled(text?.length ?? 0, null, growable: true);

  /// A controller holding [html] as written by [toHtml] or another client.
  /// Unsupported markup is reduced to its text.
  factory RichTextController.fromHtml(String html) {
    final parsed = _HtmlReader(html).read();
    final c = RichTextController(text: parsed.text);
    c._styles.setAll(0, parsed.styles);
    c._links.setAll(0, parsed.links);
    return c;
  }

  final List<int> _styles;
  final List<String?> _links;

  /// Style for the next typed text, set by toggling a style with no
  /// selection. Cleared when the caret moves.
  int? _pending;

  // Editing --------------------------------------------------------------------

  @override
  set value(TextEditingValue next) {
    final old = text;
    if (next.text == old) {
      if (next.selection != selection) _pending = null;
      super.value = next;
      return;
    }
    final (start, end, inserted) = _diff(old, next);

    // Backspace just after a list marker removes the whole marker.
    if (inserted.isEmpty && end - start == 1) {
      final line = _lineStart(old, start);
      final marker = _markerLength(old, line);
      if (marker > 0 && end == line + marker) {
        _edit([(line, end, '', 0, null)], selection: TextSelection.collapsed(offset: line));
        return;
      }
    }

    final style = _pending ?? _styleBefore(start);
    final link = _linkAround(start, end);
    _styles.replaceRange(start, end, List.filled(inserted.length, style));
    _links.replaceRange(start, end, List.filled(inserted.length, link));
    _pending = null;
    super.value = next;
    if (inserted == '\n' && next.selection.isCollapsed) _continueList(start);
    _renumber();
  }

  /// The replaced range and inserted text between [old] and [next]. A
  /// collapsed caret marks where the edit ended, which settles repeated
  /// characters ("a|a" + "a").
  static (int, int, String) _diff(String old, TextEditingValue next) {
    final n = next.text;
    final sel = next.selection;
    var suffix = -1;
    if (sel.isValid && sel.isCollapsed && sel.baseOffset <= n.length) {
      final tail = n.length - sel.baseOffset;
      if (tail <= old.length && old.endsWith(n.substring(sel.baseOffset))) suffix = tail;
    }
    if (suffix < 0) {
      suffix = 0;
      final limit = old.length < n.length ? old.length : n.length;
      while (suffix < limit && old.codeUnitAt(old.length - 1 - suffix) == n.codeUnitAt(n.length - 1 - suffix)) {
        suffix++;
      }
    }
    var prefix = 0;
    final limit = (old.length < n.length ? old.length : n.length) - suffix;
    while (prefix < limit && old.codeUnitAt(prefix) == n.codeUnitAt(prefix)) {
      prefix++;
    }
    return (prefix, old.length - suffix, n.substring(prefix, n.length - suffix));
  }

  /// Applies replacements `(start, end, text, style, link)` that do not
  /// overlap, moving the selection with the text.
  void _edit(List<(int, int, String, int, String?)> ops, {TextSelection? selection}) {
    if (ops.isEmpty) return;
    ops.sort((a, b) => b.$1.compareTo(a.$1));
    var s = text;
    var base = this.selection.baseOffset;
    var extent = this.selection.extentOffset;
    int move(int o, int start, int end, int length) =>
        o < start ? o : (o >= end ? o + length - (end - start) : start + length);
    for (final (start, end, insert, style, link) in ops) {
      s = s.replaceRange(start, end, insert);
      _styles.replaceRange(start, end, List.filled(insert.length, style));
      _links.replaceRange(start, end, List.filled(insert.length, link));
      if (base >= 0) base = move(base, start, end, insert.length);
      if (extent >= 0) extent = move(extent, start, end, insert.length);
    }
    super.value = TextEditingValue(
      text: s,
      selection: selection ?? TextSelection(baseOffset: base, extentOffset: extent),
    );
  }

  /// After Enter at [newline] in a list item: starts the next item, or ends
  /// the list when the item was empty.
  void _continueList(int newline) {
    final s = text;
    final line = _lineStart(s, newline);
    final marker = _markerLength(s, line);
    if (marker == 0) return;
    if (newline == line + marker) {
      _edit([(line, newline + 1, '', 0, null)], selection: TextSelection.collapsed(offset: line));
      return;
    }
    final number = _numbered.matchAsPrefix(s, line);
    final next = number == null ? _bullet : '${int.parse(number[1]!) + 1}. ';
    _edit([(newline + 1, newline + 1, next, _styles[newline], null)]);
  }

  /// Numbers each run of consecutive numbered items on from its first item.
  void _renumber() {
    final s = text;
    final ops = <(int, int, String, int, String?)>[];
    int? expected;
    for (final (start, _) in _lines(s, s.length)) {
      final m = _numbered.matchAsPrefix(s, start);
      if (m == null) {
        expected = null;
        continue;
      }
      final n = int.parse(m[1]!);
      if (expected != null && n != expected) {
        ops.add((start, start + m[1]!.length, '$expected', _styles[start], null));
      }
      expected = (expected ?? n) + 1;
    }
    _edit(ops);
  }

  // Inline styles --------------------------------------------------------------

  /// The style typing at [offset] takes: that of the character before it.
  int _styleBefore(int offset) => offset > 0 ? _styles[offset - 1] : (_styles.isEmpty ? 0 : _styles[0]);

  /// The link typing between [start] and [end] takes: only inside a link.
  String? _linkAround(int start, int end) {
    if (start == 0 || end >= _links.length) return null;
    final link = _links[start - 1];
    return link != null && _links[end] == link ? link : null;
  }

  /// Indices of text in [start, end), leaving out line breaks and list markers.
  Iterable<int> _contentIn(int start, int end) sync* {
    final s = text;
    for (final (ls, le) in _lines(s, s.length, from: _lineStart(s, start))) {
      if (ls >= end && ls > start) break;
      final from = ls + _markerLength(s, ls);
      for (var i = from < start ? start : from; i < le && i < end; i++) {
        yield i;
      }
    }
  }

  /// Whether [flag] applies to the selection, or to typing at the caret.
  bool isActive(int flag) {
    final sel = selection;
    if (!sel.isValid) return false;
    if (sel.isCollapsed) return ((_pending ?? _styleBefore(sel.baseOffset)) & flag) != 0;
    var any = false;
    for (final i in _contentIn(sel.start, sel.end)) {
      if (_styles[i] & flag == 0) return false;
      any = true;
    }
    return any;
  }

  /// Turns [flag] on for the selection, or off when all of it has it. With
  /// no selection it applies to what is typed next.
  void toggle(int flag) {
    final sel = selection;
    if (!sel.isValid) return;
    final on = !isActive(flag);
    if (sel.isCollapsed) {
      final current = _pending ?? _styleBefore(sel.baseOffset);
      _pending = on ? current | flag : current & ~flag;
    } else {
      for (var i = sel.start; i < sel.end; i++) {
        _styles[i] = on ? _styles[i] | flag : _styles[i] & ~flag;
      }
    }
    notifyListeners();
  }

  /// Removes styles and links from the selection, or from typing at the caret.
  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid) return;
    if (sel.isCollapsed) {
      _pending = 0;
    } else {
      _styles.fillRange(sel.start, sel.end, 0);
      _links.fillRange(sel.start, sel.end, null);
    }
    notifyListeners();
  }

  /// Removes all styles and links, as switching to plain text does.
  void clearAllFormatting() {
    _styles.fillRange(0, _styles.length, 0);
    _links.fillRange(0, _links.length, null);
    _pending = 0;
    notifyListeners();
  }

  bool get hasFormatting => _styles.any((s) => s != 0) || _links.any((l) => l != null);

  // Links ----------------------------------------------------------------------

  /// The link around the caret, or the one covering the whole selection.
  TextRange? linkRange() {
    final sel = selection;
    if (!sel.isValid) return null;
    var at = sel.start;
    if (sel.isCollapsed && (at >= _links.length || _links[at] == null) && at > 0) at--;
    if (at >= _links.length) return null;
    final link = _links[at];
    if (link == null) return null;
    var start = at, end = at;
    while (start > 0 && _links[start - 1] == link) {
      start--;
    }
    while (end < _links.length && _links[end] == link) {
      end++;
    }
    if (sel.start < start || sel.end > end) return null;
    return TextRange(start: start, end: end);
  }

  String? linkAt(int offset) => offset >= 0 && offset < _links.length ? _links[offset] : null;

  /// Links [range] to [url] (none removes the link), replacing its text with
  /// [label] if that differs. A collapsed range inserts [label] at the caret.
  void setLink(TextRange range, String label, String? url) {
    if (label.isEmpty) label = url ?? '';
    if (range.textInside(text) == label) {
      _links.fillRange(range.start, range.end, url);
      notifyListeners();
      return;
    }
    final style = range.isCollapsed ? (_pending ?? _styleBefore(range.start)) : _styles[range.start];
    _edit([(range.start, range.end, label, style, url)],
        selection: TextSelection.collapsed(offset: range.start + label.length));
  }

  // Lists ----------------------------------------------------------------------

  /// The list kind of every line the selection touches, if they share one.
  ListKind? listKind() {
    final sel = selection;
    if (!sel.isValid) return null;
    ListKind? kind;
    for (final line in _selectedLines()) {
      final k = _kindAt(text, line);
      if (k == null || (kind != null && k != kind)) return null;
      kind = k;
    }
    return kind;
  }

  /// Makes the selected lines a [kind] list, or plain lines if they already are.
  void toggleList(ListKind kind) {
    if (!selection.isValid) return;
    final s = text;
    final marker = listKind() == kind ? '' : (kind == ListKind.bullet ? _bullet : '1. ');
    final ops = <(int, int, String, int, String?)>[];
    for (final line in _selectedLines()) {
      final end = line + _markerLength(s, line);
      // The marker takes the style of the item's text.
      ops.add((line, end, marker, end < _styles.length ? _styles[end] : _styleBefore(line), null));
    }
    _edit(ops);
    _renumber();
  }

  List<int> _selectedLines() {
    final s = text;
    final sel = selection;
    // A selection ending at the start of a line leaves that line out.
    final last = sel.end > sel.start && sel.end > 0 && s.codeUnitAt(sel.end - 1) == 0x0A ? sel.end - 1 : sel.end;
    return [for (final (ls, _) in _lines(s, s.length, from: _lineStart(s, sel.start))) if (ls <= last) ls];
  }

  // Output ---------------------------------------------------------------------

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final scheme = Theme.of(context).colorScheme;
    final s = text;
    final composing = withComposing && value.isComposingRangeValid ? value.composing : TextRange.empty;
    final children = <InlineSpan>[];
    var start = 0;
    for (var i = 1; i <= s.length; i++) {
      if (i < s.length &&
          _styles[i] == _styles[start] &&
          _links[i] == _links[start] &&
          i != composing.start &&
          i != composing.end) {
        continue;
      }
      final composed = start >= composing.start && start < composing.end;
      children.add(TextSpan(text: s.substring(start, i), style: _spanStyle(_styles[start], _links[start], composed, scheme)));
      start = i;
    }
    return TextSpan(style: style, children: children);
  }

  static TextStyle? _spanStyle(int flags, String? link, bool composing, ColorScheme scheme) {
    if (flags == 0 && link == null && !composing) return null;
    return TextStyle(
      fontWeight: flags & InlineStyle.bold != 0 ? FontWeight.w700 : null,
      fontStyle: flags & InlineStyle.italic != 0 ? FontStyle.italic : null,
      color: link != null ? scheme.primary : null,
      decoration: TextDecoration.combine([
        if (flags & InlineStyle.underline != 0 || link != null || composing) TextDecoration.underline,
        if (flags & InlineStyle.strike != 0) TextDecoration.lineThrough,
      ]),
    );
  }

  /// The text as HTML, one `<div>` per line and lists as `<ul>`/`<ol>`, the
  /// way other clients' editors write it. Trailing blank lines are dropped.
  String toHtml() {
    final s = text;
    if (s.trimRight().isEmpty) return '';
    final out = StringBuffer();
    ListKind? open;
    for (final (start, end) in _lines(s, s.trimRight().length)) {
      final marker = _markerLength(s, start);
      final kind = _kindAt(s, start);
      if (kind != open) {
        if (open != null) out.write(open == ListKind.bullet ? '</ul>' : '</ol>');
        if (kind == ListKind.bullet) out.write('<ul style="margin:0;padding-left:1.5em">');
        if (kind == ListKind.numbered) {
          final first = int.parse(_numbered.matchAsPrefix(s, start)![1]!);
          out.write('<ol${first == 1 ? '' : ' start="$first"'} style="margin:0;padding-left:1.5em">');
        }
        open = kind;
      }
      final inline = _inlineHtml(start + marker, end);
      final content = inline.isEmpty ? '<br>' : inline;
      out.write(kind == null ? '<div>$content</div>' : '<li>$content</li>');
    }
    if (open != null) out.write(open == ListKind.bullet ? '</ul>' : '</ol>');
    return out.toString();
  }

  String _inlineHtml(int start, int end) {
    final out = StringBuffer();
    for (final (from, to) in _runs(start, end)) {
      final flags = _styles[from];
      final link = _links[from];
      var t = _escape(text.substring(from, to)).replaceAll('  ', ' &nbsp;');
      // HTML drops spaces at the start of a line.
      if (from == start && t.startsWith(' ')) t = '&nbsp;${t.substring(1)}';
      if (link == null) t = linkifyHtml(t);
      if (flags & InlineStyle.strike != 0) t = '<s>$t</s>';
      if (flags & InlineStyle.underline != 0) t = '<u>$t</u>';
      if (flags & InlineStyle.italic != 0) t = '<i>$t</i>';
      if (flags & InlineStyle.bold != 0) t = '<b>$t</b>';
      if (link != null) t = '<a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(link)}">$t</a>';
      out.write(t);
    }
    return out.toString();
  }

  /// The text for the `text/plain` alternative. Styles are written the way
  /// mail clients read them in plain text (`*bold*`, `/italic/`,
  /// `_underline_`), links as `text <url>`, and bullets as `-`.
  String toPlainText() {
    final s = text;
    if (s.trimRight().isEmpty) return '';
    final lines = <String>[];
    for (final (start, end) in _lines(s, s.trimRight().length)) {
      final out = StringBuffer();
      var from = start;
      if (s.startsWith(_bullet, start)) {
        out.write('- ');
        from += _bullet.length;
      }
      for (final (a, b) in _runs(from, end)) {
        var t = s.substring(a, b);
        final link = _links[a];
        final flags = _styles[a];
        final core = t.trim();
        if (core.isNotEmpty) {
          var marked = core;
          if (flags & InlineStyle.underline != 0) marked = '_${marked}_';
          if (flags & InlineStyle.italic != 0) marked = '/$marked/';
          if (flags & InlineStyle.bold != 0) marked = '*$marked*';
          if (link != null && link != core && link != 'mailto:$core') marked = '$marked <$link>';
          final lead = t.length - t.trimLeft().length;
          t = '${t.substring(0, lead)}$marked${t.substring(lead + core.length)}';
        }
        out.write(t);
      }
      lines.add(out.toString());
    }
    return lines.join('\n');
  }

  /// Runs of [start, end) that share style and link.
  Iterable<(int, int)> _runs(int start, int end) sync* {
    var from = start;
    for (var i = start + 1; i <= end; i++) {
      if (i < end && _styles[i] == _styles[from] && _links[i] == _links[from]) continue;
      if (from < end) yield (from, i);
      from = i;
    }
  }
}

// Helpers -----------------------------------------------------------------------

String _escape(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

/// Makes bare web addresses in escaped HTML text clickable.
String linkifyHtml(String escaped) => escaped.replaceAllMapped(
    RegExp(r'(https?://[^\s<>"]+[^\s<>".,;:!?)\]])'), (m) => '<a href="${m[1]}">${m[1]}</a>');

/// `(start, end)` of each line of [s] up to [limit], from the line at [from].
Iterable<(int, int)> _lines(String s, int limit, {int from = 0}) sync* {
  var start = from;
  while (true) {
    final nl = s.indexOf('\n', start);
    if (nl < 0 || nl >= limit) {
      yield (start, limit < start ? start : limit);
      return;
    }
    yield (start, nl);
    start = nl + 1;
  }
}

int _lineStart(String s, int offset) => offset <= 0 ? 0 : s.lastIndexOf('\n', offset - 1) + 1;

int _markerLength(String s, int line) {
  if (s.startsWith(_bullet, line)) return _bullet.length;
  final m = _numbered.matchAsPrefix(s, line);
  return m == null ? 0 : m.end - line;
}

ListKind? _kindAt(String s, int line) {
  if (s.startsWith(_bullet, line)) return ListKind.bullet;
  return _numbered.matchAsPrefix(s, line) == null ? null : ListKind.numbered;
}

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

/// Reads the subset of HTML that mail editors write back into text, styles
/// and links.
class _HtmlReader {
  _HtmlReader(this.html);

  final String html;
  final _text = StringBuffer();
  final styles = <int>[];
  final links = <String?>[];
  final _open = <String, int>{};
  final _hrefs = <String?>[];
  final _lists = <(ListKind, int)>[];
  var _quote = 0;

  static const _flags = {
    'b': InlineStyle.bold,
    'strong': InlineStyle.bold,
    'i': InlineStyle.italic,
    'em': InlineStyle.italic,
    'u': InlineStyle.underline,
    's': InlineStyle.strike,
    'strike': InlineStyle.strike,
    'del': InlineStyle.strike,
  };
  static const _blocks = {'div', 'p', 'li', 'ul', 'ol', 'blockquote', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre'};

  /// Something, if only a list marker, was written on the current line.
  var _lineOpen = false;

  /// Text was written on the current line.
  var _lineHasText = false;

  int get _style {
    var s = 0;
    _open.forEach((tag, count) {
      if (count > 0) s |= _flags[tag]!;
    });
    return s;
  }

  void _append(String s, int style, String? link) {
    _text.write(s);
    styles.addAll(List.filled(s.length, style));
    links.addAll(List.filled(s.length, link));
  }

  void _openLine() {
    if (!_lineOpen && _quote > 0) _append('> ' * _quote, 0, null);
    _lineOpen = true;
  }

  void _write(String s) {
    if (s.isEmpty) return;
    _openLine();
    _append(s, _style, _hrefs.lastOrNull);
    _lineHasText = true;
  }

  void _newline() {
    _append('\n', 0, null);
    _lineOpen = _lineHasText = false;
  }

  /// Ends the current line before a block, unless it holds no text yet
  /// (`<li><div>…`).
  void _breakLine() {
    if (_lineHasText) _newline();
  }

  ({String text, List<int> styles, List<String?> links}) read() {
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
      if (tag == 'br') {
        _newline();
      } else if (_flags.containsKey(tag)) {
        _open[tag] = ((_open[tag] ?? 0) + (closing ? -1 : 1)).clamp(0, 1 << 20);
      } else if (tag == 'a') {
        if (closing) {
          if (_hrefs.isNotEmpty) _hrefs.removeLast();
        } else {
          final href = RegExp(r'''href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''', caseSensitive: false).firstMatch(m[3]!);
          final url = href == null ? null : _decode(href[2] ?? href[3] ?? href[4]!);
          _hrefs.add(url == null ? null : normalizeLink(url));
        }
      } else if (_blocks.contains(tag)) {
        _breakLine();
        switch ((tag, closing)) {
          case ('ul', false):
            _lists.add((ListKind.bullet, 1));
          case ('ol', false):
            final start = RegExp(r'start\s*=\s*"?(\d+)').firstMatch(m[3]!);
            _lists.add((ListKind.numbered, start == null ? 1 : int.parse(start[1]!)));
          case ('ul' || 'ol', true):
            if (_lists.isNotEmpty) _lists.removeLast();
          case ('li', false) when _lists.isNotEmpty:
            if (_lineOpen) _newline();
            final (kind, n) = _lists.last;
            _openLine();
            _append(kind == ListKind.bullet ? _bullet : '$n. ', _style, null);
            _lists.last = (kind, n + 1);
          case ('blockquote', false):
            _quote++;
          case ('blockquote', true):
            if (_quote > 0) _quote--;
          default:
        }
      }
    }
    // Drop trailing blank lines.
    final s = _text.toString().trimRight();
    return (text: s, styles: styles.sublist(0, s.length), links: links.sublist(0, s.length));
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
