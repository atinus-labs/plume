import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/compose/body_editor.dart';
import 'package:plume/src/ui/compose/rich_text.dart';

QuillController empty() =>
    QuillController(document: Document(), selection: const TextSelection.collapsed(offset: 0));

QuillController withHtml(String html) =>
    QuillController(document: documentFromHtml(html), selection: const TextSelection.collapsed(offset: 0));

/// Types [s] at the caret one character at a time, as the keyboard would.
void type(QuillController c, String s) {
  for (final ch in s.split('')) {
    final sel = c.selection;
    c.replaceText(sel.start, sel.end - sel.start, ch, TextSelection.collapsed(offset: sel.start + 1));
  }
}

void select(QuillController c, int start, int end) =>
    c.updateSelection(TextSelection(baseOffset: start, extentOffset: end), ChangeSource.local);

void caret(QuillController c, int at) => select(c, at, at);

/// Starts a new undo step, as a pause in typing does.
void pause(QuillController c) => c.document.history.lastRecorded = 0;

String html(QuillController c) => c.document.toMailHtml();

const ul0 = '<ul style="margin:0;padding-left:1.5em;list-style-type:disc">';
const ul1 = '<ul style="margin:0;padding-left:1.5em;list-style-type:circle">';
const ol0 = '<ol style="margin:0;padding-left:1.5em;list-style-type:decimal">';
const ol1 = '<ol style="margin:0;padding-left:1.5em;list-style-type:lower-alpha">';
const quote = '<blockquote style="margin:0 0 0 0.8ex;border-left:3px solid #ccc;padding-left:1ex">';
const indent = '<blockquote style="margin:0 0 0 40px;border:none;padding:0">';

void main() {
  group('inline styles', () {
    test('bold on a selection', () {
      final c = empty();
      type(c, 'Hello world');
      select(c, 6, 11);
      c.toggle(Attribute.bold);
      expect(c.isActive(Attribute.bold), isTrue);
      expect(html(c), '<div>Hello <b>world</b></div>');
      expect(c.document.toMailText(), 'Hello *world*');
    });

    test('toggling again removes the style', () {
      final c = empty();
      type(c, 'Hello');
      select(c, 0, 5);
      c.toggle(Attribute.italic);
      c.toggle(Attribute.italic);
      expect(c.document.hasFormatting, isFalse);
      expect(html(c), '<div>Hello</div>');
    });

    test('toggling at the caret styles what is typed next', () {
      final c = empty();
      type(c, 'a ');
      c.toggle(Attribute.bold);
      expect(c.isActive(Attribute.bold), isTrue);
      type(c, 'bold');
      c.toggle(Attribute.bold);
      type(c, ' c');
      expect(html(c), '<div>a <b>bold</b> c</div>');
    });

    test('combined styles and remove formatting', () {
      final c = empty();
      type(c, 'x y');
      select(c, 0, 3);
      c.toggle(Attribute.bold);
      c.toggle(Attribute.italic);
      c.toggle(Attribute.strikeThrough);
      expect(html(c), '<div><b><i><s>x y</s></i></b></div>');
      expect(c.document.toMailText(), '*/x y/*');
      select(c, 2, 3);
      c.clearFormatting();
      expect(html(c), '<div><b><i><s>x </s></i></b>y</div>');
    });

    test('size and colour', () {
      final c = empty();
      type(c, 'big red small');
      select(c, 0, 3);
      c.setTextSize(TextSize.huge);
      expect(c.textSize, TextSize.huge);
      select(c, 4, 7);
      c.setTextColor(textColors.first.$2);
      expect(c.textColor, textColors.first.$2);
      select(c, 8, 13);
      c.setTextSize(TextSize.small);
      expect(
        html(c),
        '<div><span style="font-size:xx-large">big</span> <span style="color:#d93025">red</span> '
        '<span style="font-size:small">small</span></div>',
      );
      select(c, 0, 13);
      c.clearFormatting();
      expect(c.document.hasFormatting, isFalse);
    });

    test('remove formatting keeps lists and quotes', () {
      final c = empty();
      type(c, 'a\nb');
      select(c, 0, 3);
      c.toggle(Attribute.bold);
      caret(c, 0);
      c.toggle(Attribute.ul);
      caret(c, 2);
      c.toggle(Attribute.blockQuote);
      select(c, 0, 3);
      c.clearFormatting();
      expect(html(c), '$ul0<li>a</li></ul>$quote<div>b</div></blockquote>');
    });
  });

  group('undo', () {
    test('brings deleted text back with its formatting', () {
      final c = empty();
      type(c, 'Hello world');
      pause(c);
      select(c, 6, 11);
      c.toggle(Attribute.bold);
      c.setTextColor(textColors[5].$2);
      pause(c);
      c.replaceText(6, 5, '', const TextSelection.collapsed(offset: 6));
      expect(html(c), '<div>Hello </div>');
      pause(c);
      c.undo();
      expect(html(c), '<div>Hello <span style="color:#1a73e8"><b>world</b></span></div>');
      c.redo();
      expect(html(c), '<div>Hello </div>');
    });

    test('takes back formatting and lists', () {
      final c = empty();
      type(c, 'abc');
      pause(c);
      select(c, 0, 3);
      c.toggle(Attribute.underline);
      pause(c);
      c.toggle(Attribute.ol);
      expect(html(c), '$ol0<li><u>abc</u></li></ol>');
      c.undo();
      expect(html(c), '<div><u>abc</u></div>');
      c.undo();
      expect(html(c), '<div>abc</div>');
    });
  });

  group('lists', () {
    test('Enter continues a list and Enter on an empty item ends it', () {
      final c = empty();
      c.toggle(Attribute.ul);
      type(c, 'one\ntwo\n\nafter');
      expect(html(c), '$ul0<li>one</li><li>two</li></ul><div>after</div>');
      expect(c.document.toMailText(), '- one\n- two\nafter');
    });

    test('items nest, numbered 1, a, i and bulleted by depth', () {
      final c = empty();
      c.toggle(Attribute.ol);
      type(c, 'a\n');
      c.indentSelection(true);
      type(c, 'b\nc\n');
      c.indentSelection(false);
      type(c, 'd');
      expect(c.indentLevel, 0);
      expect(html(c), '$ol0<li>a$ol1<li>b</li><li>c</li></ol></li><li>d</li></ol>');
      expect(c.document.toMailText(), '1. a\n  a. b\n  b. c\n2. d');

      final b = empty();
      b.toggle(Attribute.ul);
      type(b, 'x\n');
      b.indentSelection(true);
      type(b, 'y');
      expect(html(b), '$ul0<li>x$ul1<li>y</li></ul></li></ul>');
      expect(b.document.toMailText(), '- x\n  - y');
    });

    test('a list nested without a parent item is indented', () {
      final c = empty();
      type(c, 'x');
      c.toggle(Attribute.ul);
      c.indentSelection(true);
      expect(html(c), '$indent$ul1<li>x</li></ul></blockquote>');
    });

    test('toggling covers every selected line and switches kinds', () {
      final c = empty();
      type(c, 'a\nb\nc');
      select(c, 0, 3);
      c.toggle(Attribute.ul);
      expect(c.listKind, 'bullet');
      expect(html(c), '$ul0<li>a</li><li>b</li></ul><div>c</div>');
      c.toggle(Attribute.ol);
      expect(c.listKind, 'ordered');
      c.toggle(Attribute.ol);
      expect(c.document.hasFormatting, isFalse);
    });
  });

  group('quotes and indents', () {
    test('a quote is a bordered blockquote', () {
      final c = empty();
      type(c, 'a\nb\nc');
      select(c, 0, 3);
      c.toggle(Attribute.blockQuote);
      expect(c.isActive(Attribute.blockQuote), isTrue);
      expect(html(c), '$quote<div>a</div><div>b</div></blockquote><div>c</div>');
      expect(c.document.toMailText(), '> a\n> b\nc');
    });

    test('indents nest and come back out', () {
      final c = empty();
      type(c, 'x');
      c.indentSelection(true);
      c.indentSelection(true);
      expect(c.indentLevel, 2);
      expect(html(c), '$indent$indent<div>x</div></blockquote></blockquote>');
      expect(c.document.toMailText(), '        x');
      c.indentSelection(false);
      c.indentSelection(false);
      expect(html(c), '<div>x</div>');
    });
  });

  group('html', () {
    test('escapes text and keeps blank lines and spaces', () {
      final c = empty();
      type(c, '<a> & b\n\n  two');
      expect(html(c), '<div>&lt;a&gt; &amp; b</div><div><br></div><div>&nbsp;&nbsp;two</div>');
    });

    test('links bare addresses in unlinked text', () {
      final c = empty();
      type(c, 'see https://plume.dev.');
      expect(html(c), '<div>see <a href="https://plume.dev">https://plume.dev</a>.</div>');
    });

    test('drops trailing blank lines and returns nothing for an empty body', () {
      final c = empty();
      type(c, 'hi\n\n  ');
      expect(html(c), '<div>hi</div>');
      expect(empty().document.toMailHtml(), '');
      expect(empty().document.toMailText(), '');
      expect(documentFromText('  \n').isBlank, isTrue);
    });

    test('reads back what it writes', () {
      final c = empty();
      type(c, 'Hi Sam,\n\nPlan:\nShip\nTest\nDocs\nQuoted\nAside\nThanks');
      select(c, 0, 2);
      c.toggle(Attribute.bold);
      c.setTextColor(textColors[3].$2);
      select(c, 15, 30);
      c.toggle(Attribute.ol);
      caret(c, 20);
      c.indentSelection(true);
      select(c, 15, 19);
      c.setLink(const TextRange(start: 15, end: 19), 'Ship', 'https://example.com/a?b=1&c=2');
      caret(c, 31);
      c.toggle(Attribute.blockQuote);
      caret(c, 38);
      c.indentSelection(true);
      select(c, 44, 50);
      c.setTextSize(TextSize.large);
      final written = html(c);
      final back = withHtml(written);
      expect(back.document.toPlainText(), c.document.toPlainText());
      expect(back.document.toMailHtml(), written);
      expect(back.document.toMailText(), c.document.toMailText());
    });

    test('reads other clients\' markup', () {
      final c = withHtml('<html><head><style>p{}</style></head><body>'
          '<p>One <strong>two</strong>\n  <em>three</em></p>'
          '<ul><li><div>a</div></li><ul><li>b</li></ul><li>c</li></ul>'
          '<ol start="3"><li>d</li></ol>'
          '<blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);'
          'padding-left:1ex">quoted<br>text</blockquote>'
          '<blockquote style="margin:0 0 0 40px;border:none;padding:0px"><div>indented</div></blockquote>'
          '<div><font color="#ff0000" size="4">red</font> <span style="font-weight:bold;color:rgb(0,0,0)">x</span>'
          '</div><p><a href="mailto:x@y.z">mail</a> &amp;&nbsp;more</p></body></html>');
      expect(c.document.toPlainText(), 'One two three\na\nb\nc\nd\nquoted\ntext\nindented\nred x\nmail & more\n');
      expect(
        c.document.toMailText(),
        'One *two* /three/\n- a\n  - b\n- c\n1. d\n> quoted\n> text\n    indented\nred *x*\nmail <mailto:x@y.z> & more',
      );
      // Red and large; black is another client's default and is left out.
      expect(html(c), contains('<span style="color:#ff0000;font-size:x-large">red</span> <b>x</b>'));
    });
  });

  group('links', () {
    test('links a selection and finds it again', () {
      final c = empty();
      type(c, 'read the docs');
      c.setLink(const TextRange(start: 9, end: 13), 'docs', 'https://plume.dev/docs');
      caret(c, 11);
      expect(c.linkRange(), const TextRange(start: 9, end: 13));
      caret(c, 13);
      expect(c.linkRange(), const TextRange(start: 9, end: 13));
      expect(c.linkAt(9), 'https://plume.dev/docs');
      expect(html(c), '<div>read the <a href="https://plume.dev/docs">docs</a></div>');
      expect(c.document.toMailText(), 'read the docs <https://plume.dev/docs>');
    });

    test('inserts a link at the caret without extending it when typing on', () {
      final c = empty();
      type(c, 'go ');
      c.setLink(const TextRange.collapsed(3), 'here', 'https://a.b');
      expect(c.selection.baseOffset, 7);
      type(c, '!');
      expect(html(c), '<div>go <a href="https://a.b">here</a>!</div>');
    });

    test('removing a link unlinks it', () {
      final c = empty();
      type(c, 'abc');
      c.setLink(const TextRange(start: 0, end: 3), 'abc', 'https://a.b');
      c.setLink(const TextRange(start: 0, end: 3), 'abc', null);
      expect(c.document.hasFormatting, isFalse);
    });

    test('normalizes typed addresses', () {
      expect(normalizeLink('plume.dev'), 'https://plume.dev');
      expect(normalizeLink('me@plume.dev'), 'mailto:me@plume.dev');
      expect(normalizeLink('http://x.y'), 'http://x.y');
      expect(normalizeLink('javascript:alert(1)'), isNull);
      expect(normalizeLink('  '), isNull);
    });
  });

  test('plain text mode keeps lists, quotes and links but not styles', () {
    final c = withHtml('<div><b>Hi</b> <a href="https://a.b">there</a></div>$ol0<li>one</li></ol>$quote<div>q</div>'
        '</blockquote>');
    expect(c.document.toMailText(marks: false), 'Hi there <https://a.b>\n1. one\n> q');
  });

  group('editor', () {
    Future<QuillController> pump(WidgetTester tester, String html) async {
      final c = withHtml(html);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: SizedBox(
            width: 400,
            child: BodyEditor(
              controller: c,
              focusNode: FocusNode(),
              scrollController: ScrollController(),
              onEditLink: () {},
              onEscape: () {},
            ),
          ),
        ),
      ));
      return c;
    }

    Rect rectOf(WidgetTester tester, String text) =>
        tester.getRect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().trimRight() == text));

    testWidgets('indents list items, nested items and quotes', (tester) async {
      await pump(tester, '<div>plain</div>$ul0<li>item$ul1<li>nested</li></ul></li></ul>$quote<div>quoted</div></blockquote>');
      final plain = rectOf(tester, 'plain').left;
      final item = rectOf(tester, 'item').left;
      final nested = rectOf(tester, 'nested').left;
      expect(item, greaterThan(plain + 16));
      expect(nested, greaterThan(item + 16));
      expect(rectOf(tester, 'quoted').left, greaterThan(plain + 8));
    });

    testWidgets('wrapped item lines stay indented', (tester) async {
      await pump(tester, '$ul0<li>${'word ' * 40}</li></ul>');
      final item = rectOf(tester, ('word ' * 40).trimRight());
      // One block of text, laid out right of the bullet on every line.
      expect(item.height, greaterThan(48));
      expect(item.left, greaterThan(16));
    });

    testWidgets('keyboard formats, nests and undoes', (tester) async {
      final c = await pump(tester, '<div>Hello world</div>');
      await tester.tap(find.byType(BodyEditor));
      await tester.pump();
      Future<void> keys(List<LogicalKeyboardKey> keys) async {
        for (final k in keys) {
          await tester.sendKeyDownEvent(k);
        }
        for (final k in keys.reversed) {
          await tester.sendKeyUpEvent(k);
        }
        await tester.pump();
      }

      select(c, 6, 11);
      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyB]);
      expect(html(c), '<div>Hello <b>world</b></div>');
      pause(c);
      c.replaceText(6, 5, '', const TextSelection.collapsed(offset: 6));
      pause(c);
      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ]);
      expect(html(c), '<div>Hello <b>world</b></div>');
      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.keyZ]);
      expect(html(c), '<div>Hello </div>');

      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.digit8]);
      expect(c.listKind, 'bullet');
      await keys([LogicalKeyboardKey.tab]);
      expect(c.indentLevel, 1);
      await keys([LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.tab]);
      expect(c.indentLevel, 0);
      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.digit9]);
      expect(c.isActive(Attribute.blockQuote), isTrue);
      await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.bracketRight]);
      expect(c.indentLevel, 1);
    });
  });
}
