import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart' show decodeHtmlEntities;

import '../common/format.dart';
import '../reader/mail_document.dart' show withoutTrackingPixels;
import 'rich_text.dart' show linkifyHtml;

// What a compose window sends: what was typed, then the signature, then the
// message replied to or forwarded. [editableBody] takes a message laid out
// this way apart again, so that a draft or a message taken back from the
// outbox can be edited.

/// The first line of a forwarded message.
const forwardedHeader = '---------- Forwarded message ---------';

/// `On Tue, 14 Oct 2025 at 10:42, Maya Chen <maya@…> wrote:`
String attributionLine(Message m) {
  final date = DateFormat("EEE, d MMM y 'at' HH:mm").format(m.date.toLocal());
  return 'On $date, ${m.from?.format() ?? 'someone'} wrote:';
}

/// [text], the body of [m], quoted below a reply.
String replyQuote(Message m, String text) =>
    '${attributionLine(m)}\n${text.trimRight().split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n')}';

/// [text], the body of [m], below a forward.
String forwardQuote(Message m, String text) => [..._forwardHeader(m), '', text].join('\n');

/// The lines heading a forward of [m].
List<String> _forwardHeader(Message m) => [
      forwardedHeader,
      'From: ${m.from?.format() ?? ''}',
      'Date: ${fullDate(m.date)}',
      'Subject: ${m.subject}',
      'To: ${m.to.map((a) => a.format()).join(', ')}',
      if (m.cc.isNotEmpty) 'Cc: ${m.cc.map((a) => a.format()).join(', ')}',
    ];

/// [html], the body of [m] made ready by [quotableHtml], quoted below a
/// reply in the HTML part, as [mailHtml] takes it.
String replyQuoteHtml(Message m, String html) => _replyQuoteHtml(_esc(attributionLine(m)), html);

/// [html], the body of [m] made ready by [quotableHtml], below a forward in
/// the HTML part, as [mailHtml] takes it.
String forwardQuoteHtml(Message m, String html) =>
    _forwardQuoteHtml('${_para(_forwardHeader(m).join('\n'))}<br><br>$html');

/// The plain text part.
String mailText(String typed, {String? signature, String? quote}) => [
      typed,
      if (signature != null && signature.isNotEmpty) '\n-- \n$signature',
      if (quote != null) '\n$quote',
    ].join('\n');

/// The HTML part around the formatted [body]: the signature and quote are
/// escaped with paragraphs kept, links clickable, and a reply's quote in a
/// blockquote. [quoteHtml], when given, is the quote as written by
/// [replyQuoteHtml] or [forwardQuoteHtml], and takes the place of [quote]'s
/// text.
String mailHtml(String body, {String? signature, String? quote, String? quoteHtml}) {
  final buffer = StringBuffer('<div dir="auto" style="font-family:sans-serif">')..write(body);
  if (signature != null && signature.isNotEmpty) {
    buffer.write('<br><div class="plume_signature">-- <br>${_para(signature)}</div>');
  }
  buffer.write('</div>');
  final quoted = quoteHtml ?? (quote == null ? null : _textQuoteHtml(quote));
  if (quoted != null) buffer.write('<br>$quoted');
  return buffer.toString();
}

/// A quote written by [replyQuote] or [forwardQuote], as HTML.
String _textQuoteHtml(String quote) {
  if (quote.startsWith(forwardedHeader)) return _forwardQuoteHtml(_para(quote));
  final lines = quote.split('\n');
  final quoted = lines.skip(1).map((l) => l.startsWith('> ') ? l.substring(2) : (l == '>' ? '' : l)).join('\n');
  return _replyQuoteHtml(_esc(lines.first), _para(quoted));
}

String _replyQuoteHtml(String attribution, String body) =>
    '<div class="gmail_quote"><div>$attribution</div>'
    '<blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">'
    '$body</blockquote></div>';

String _forwardQuoteHtml(String content) => '<div class="gmail_quote">$content</div>';

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

/// [s] as HTML, with its line breaks and links.
String _para(String s) => linkifyHtml(_esc(s)).replaceAll('\n', '<br>');

/// The body of an HTML message, to quote inside another: what is inside its
/// `<body>`, without scripts, comments or tracking pixels, and without style
/// sheets, which would restyle the rest of the message too.
String quotableHtml(String html) {
  var s = html.replaceAll(_comment, '');
  final body = _bodyTag.firstMatch(s);
  if (body != null) {
    s = s.substring(body.end);
    final end = s.toLowerCase().lastIndexOf('</body');
    if (end >= 0) s = s.substring(0, end);
  }
  s = s.replaceAll(_rawContent, '').replaceAll(_documentTag, '');
  return withoutTrackingPixels(s).trim();
}

/// An HTML message as plain text, to quote it where it has no text part:
/// paragraphs and line breaks kept, list items led by `-`, links written as
/// `text <url>`, and what is hidden left out.
String htmlToMailText(String html) {
  var s = html
      .replaceAll(_comment, '')
      .replaceAll(_rawContent, '')
      .replaceAll(_hidden, '')
      .replaceAllMapped(_pre, (m) => m[0]!.replaceAll('\n', '<br>'))
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(_link, (m) {
        final text = m[2]!;
        final href = _attribute('href', m[1]!);
        final shown = decodeHtmlEntities(text.replaceAll(_tag, '')).trim();
        if (href == null || !href.startsWith(RegExp('https?://')) || shown.isEmpty || _sameUrl(shown, href)) {
          return text;
        }
        return '$text &lt;${_esc(href)}&gt;';
      })
      .replaceAll(RegExp(r'<br\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '$_line- ')
      .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), ' ')
      .replaceAllMapped(_tag, (m) => switch (m[1]!.toLowerCase()) {
            'p' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'blockquote' || 'hr' => _paragraph,
            final name when _blockTags.contains(name) => _line,
            _ => '',
          });
  // Breaks between blocks run together; a <br> at the end of a block adds
  // no line of its own.
  s = s.replaceAllMapped(RegExp('\n? *[$_line$_paragraph][$_line$_paragraph ]*'),
      (m) => m[0]!.contains(_paragraph) ? '\n\n' : '\n');
  return decodeHtmlEntities(s)
      .replaceAll(_invisible, '')
      .split('\n')
      .map((l) => l.replaceAll(RegExp('[ \u00a0]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Marks where a block of [htmlToMailText] starts or ends a line, or a
/// paragraph.
const _line = '\x01';
const _paragraph = '\x02';

const _blockTags = {
  'address', 'article', 'aside', 'caption', 'center', 'dd', 'div', 'dl', 'dt', 'figcaption', 'figure', //
  'footer', 'header', 'li', 'main', 'nav', 'ol', 'pre', 'section', 'table', 'tbody', 'tfoot', 'thead', 'tr', 'ul',
};

/// Whether link [text] is the address [href] written out.
bool _sameUrl(String text, String href) {
  String bare(String url) =>
      url.toLowerCase().replaceFirst(RegExp(r'^https?://(?:www\.)?'), '').replaceFirst(RegExp(r'/$'), '');
  return bare(text) == bare(href);
}

/// The value of attribute [name] among a tag's [attributes].
String? _attribute(String name, String attributes) {
  final m = RegExp('(?:^|\\s)$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
      .firstMatch(attributes);
  final value = m == null ? null : (m[1] ?? m[2] ?? m[3]);
  return value == null ? null : decodeHtmlEntities(value).trim();
}

final _comment = RegExp(r'<!--[\s\S]*?-->');
final _rawContent =
    RegExp(r'<(head|script|style|title|template|noscript|xml)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false);
final _bodyTag = RegExp(r'<body\b[^>]*>', caseSensitive: false);
final _documentTag = RegExp(r'<(?:!doctype|/?html|/?head|/?body|meta|link|base)\b[^>]*>', caseSensitive: false);
final _hidden = RegExp(
    r'''<([a-z][a-z0-9]*)\b[^>]*\bstyle\s*=\s*["'][^"']*display\s*:\s*none[^"']*["'][^>]*>[\s\S]*?</\1\s*>''',
    caseSensitive: false);
final _pre = RegExp(r'<pre\b[^>]*>[\s\S]*?</pre\s*>', caseSensitive: false);
final _link = RegExp(r'<a\b([^>]*)>([\s\S]*?)</a\s*>', caseSensitive: false);
final _tag = RegExp(r'</?([a-z][a-z0-9]*)\b[^>]*>', caseSensitive: false);

/// Zero-width characters that marketing mail pads its preview text with,
/// and soft hyphens.
final _invisible = RegExp('[\u00ad\u034f\u200b\u200c\u2060\ufeff]');

/// A message laid out by [mailText] and [mailHtml], taken apart again: what
/// was typed and the quote, each as text and as HTML when it has an HTML
/// part.
///
/// The signature is left out, to be added again on sending, when it can be
/// told apart from the rest: marked as [mailHtml] marks it, or in plain text
/// matching [signature], the account's signature. A reply's quote is only
/// looked for when [reply] is set. Drafts from other clients come apart as
/// far as they follow the same conventions; anything else stays with the
/// typed text, so nothing is lost.
({String text, String? html, String? quote, String? quoteHtml}) editableBody({
  required String text,
  String? html,
  String? signature,
  bool reply = false,
}) {
  var lines = text.replaceAll('\r\n', '\n').trimRight().split('\n');

  // A forward from its header on, or a reply's quoted lines and the
  // attribution above them.
  var start = lines.indexOf(forwardedHeader);
  if (start < 0 && reply) {
    var i = lines.length;
    while (i > 0 && lines[i - 1].startsWith('>')) {
      i--;
    }
    final quoted = i < lines.length;
    while (i > 0 && lines[i - 1].trim().isEmpty) {
      i--;
    }
    if (quoted && i > 0 && lines[i - 1].trimRight().endsWith(':')) start = i - 1;
  }
  // In HTML the quote has to be marked too.
  final htmlQuote = html == null ? null : _quoteHtml.firstMatch(html);
  if (html != null && htmlQuote == null) start = -1;
  String? quote;
  String? quoteHtml;
  if (start >= 0) {
    quote = lines.sublist(start).join('\n');
    lines = lines.sublist(0, start);
    if (html != null) {
      quoteHtml = html.substring(htmlQuote!.start).replaceFirst(_leadingBreaks, '');
      html = html.substring(0, htmlQuote.start);
    }
  }

  final marked = html != null && _signatureHtml.hasMatch(html);
  final mark = lines.lastIndexOf('-- ');
  final sig = signature?.trim() ?? '';
  if (mark >= 0 && (marked || (sig.isNotEmpty && lines.sublist(mark + 1).join('\n').trim() == sig))) {
    lines = lines.sublist(0, mark);
  }
  if (marked) html = html.replaceFirst(_signatureHtml, '');

  return (text: lines.join('\n').trimRight(), html: html, quote: quote, quoteHtml: quoteHtml);
}

final _quoteHtml = RegExp(r'''(?:<br\s*/?>\s*)*<div\b[^>]*\bclass\s*=\s*["']?gmail_quote''', caseSensitive: false);
final _leadingBreaks = RegExp(r'^(?:<br\s*/?>\s*)*', caseSensitive: false);
final _signatureHtml = RegExp(r'(?:<br>)?<div class="plume_signature">[\s\S]*?</div>');
