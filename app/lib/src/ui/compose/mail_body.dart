import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:plume_core/plume_core.dart';

import '../common/format.dart';
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
String forwardQuote(Message m, String text) => [
      forwardedHeader,
      'From: ${m.from?.format() ?? ''}',
      'Date: ${fullDate(m.date)}',
      'Subject: ${m.subject}',
      'To: ${m.to.map((a) => a.format()).join(', ')}',
      if (m.cc.isNotEmpty) 'Cc: ${m.cc.map((a) => a.format()).join(', ')}',
      '',
      text,
    ].join('\n');

/// The plain text part.
String mailText(String typed, {String? signature, String? quote}) => [
      typed,
      if (signature != null && signature.isNotEmpty) '\n-- \n$signature',
      if (quote != null) '\n$quote',
    ].join('\n');

/// The HTML part around the formatted [body]: the signature and quote are
/// escaped with paragraphs kept, links clickable, and a reply's quote in a
/// blockquote.
String mailHtml(String body, {String? signature, String? quote}) {
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
  String para(String s) => linkifyHtml(esc(s)).replaceAll('\n', '<br>');
  final buffer = StringBuffer('<div dir="auto" style="font-family:sans-serif">')..write(body);
  if (signature != null && signature.isNotEmpty) {
    buffer.write('<br><div class="plume_signature">-- <br>${para(signature)}</div>');
  }
  buffer.write('</div>');
  if (quote != null) {
    if (quote.startsWith(forwardedHeader)) {
      buffer.write('<br><div class="gmail_quote">${para(quote)}</div>');
    } else {
      final lines = quote.split('\n');
      final attribution = lines.first;
      final quoted = lines.skip(1).map((l) => l.startsWith('> ') ? l.substring(2) : (l == '>' ? '' : l)).join('\n');
      buffer.write(
        '<br><div class="gmail_quote"><div>${esc(attribution)}</div>'
        '<blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">'
        '${para(quoted)}</blockquote></div>',
      );
    }
  }
  return buffer.toString();
}

/// A message laid out by [mailText] and [mailHtml], taken apart again: what
/// was typed, as text and as HTML when it has an HTML part, and the quote.
///
/// The signature is left out, to be added again on sending, when it can be
/// told apart from the rest: marked as [mailHtml] marks it, or in plain text
/// matching [signature], the account's signature. A reply's quote is only
/// looked for when [reply] is set. Drafts from other clients come apart as
/// far as they follow the same conventions; anything else stays with the
/// typed text, so nothing is lost.
({String text, String? html, String? quote}) editableBody({
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
  if (start >= 0) {
    quote = lines.sublist(start).join('\n');
    lines = lines.sublist(0, start);
    html = html?.substring(0, htmlQuote!.start);
  }

  final marked = html != null && _signatureHtml.hasMatch(html);
  final mark = lines.lastIndexOf('-- ');
  final sig = signature?.trim() ?? '';
  if (mark >= 0 && (marked || (sig.isNotEmpty && lines.sublist(mark + 1).join('\n').trim() == sig))) {
    lines = lines.sublist(0, mark);
  }
  if (marked) html = html.replaceFirst(_signatureHtml, '');

  return (text: lines.join('\n').trimRight(), html: html, quote: quote);
}

final _quoteHtml = RegExp(r'''(?:<br\s*/?>\s*)*<div\b[^>]*\bclass\s*=\s*["']?gmail_quote''', caseSensitive: false);
final _signatureHtml = RegExp(r'(?:<br>)?<div class="plume_signature">[\s\S]*?</div>');
