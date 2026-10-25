import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/compose/rich_text.dart';

/// Types [s] at the caret one character at a time, as the keyboard would.
void type(RichTextController c, String s) {
  for (final ch in s.split('')) {
    final sel = c.selection;
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, ch),
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }
}

void backspace(RichTextController c) {
  final at = c.selection.baseOffset;
  c.value = TextEditingValue(
    text: c.text.replaceRange(at - 1, at, ''),
    selection: TextSelection.collapsed(offset: at - 1),
  );
}

void select(RichTextController c, int start, int end) =>
    c.selection = TextSelection(baseOffset: start, extentOffset: end);

RichTextController empty() => RichTextController()..selection = const TextSelection.collapsed(offset: 0);

void main() {
  group('inline styles', () {
    test('bold on a selection', () {
      final c = empty();
      type(c, 'Hello world');
      select(c, 6, 11);
      c.toggle(InlineStyle.bold);
      expect(c.isActive(InlineStyle.bold), isTrue);
      expect(c.toHtml(), '<div>Hello <b>world</b></div>');
      expect(c.toPlainText(), 'Hello *world*');
    });

    test('toggling again removes the style', () {
      final c = empty();
      type(c, 'Hello');
      select(c, 0, 5);
      c.toggle(InlineStyle.italic);
      c.toggle(InlineStyle.italic);
      expect(c.hasFormatting, isFalse);
      expect(c.toHtml(), '<div>Hello</div>');
    });

    test('toggling at the caret styles what is typed next', () {
      final c = empty();
      type(c, 'a ');
      c.toggle(InlineStyle.bold);
      expect(c.isActive(InlineStyle.bold), isTrue);
      type(c, 'bold');
      c.toggle(InlineStyle.bold);
      type(c, ' c');
      expect(c.toHtml(), '<div>a <b>bold</b> c</div>');
    });

    test('typing after styled text continues the style', () {
      final c = empty();
      type(c, 'ab');
      select(c, 0, 2);
      c.toggle(InlineStyle.underline);
      c.selection = const TextSelection.collapsed(offset: 2);
      type(c, 'c');
      expect(c.toHtml(), '<div><u>abc</u></div>');
    });

    test('moving the caret drops a pending style', () {
      final c = empty();
      type(c, 'ab');
      c.toggle(InlineStyle.bold);
      c.selection = const TextSelection.collapsed(offset: 1);
      type(c, 'x');
      expect(c.hasFormatting, isFalse);
    });

    test('inserting between equal characters keeps styles in place', () {
      final c = empty();
      type(c, 'aa');
      select(c, 1, 2);
      c.toggle(InlineStyle.bold);
      c.selection = const TextSelection.collapsed(offset: 1);
      type(c, 'a');
      // The new "a" follows the plain first one, the bold one stays last.
      expect(c.toHtml(), '<div>aa<b>a</b></div>');
    });

    test('combined styles and remove formatting', () {
      final c = empty();
      type(c, 'x y');
      select(c, 0, 3);
      c.toggle(InlineStyle.bold);
      c.toggle(InlineStyle.italic);
      c.toggle(InlineStyle.strike);
      expect(c.toHtml(), '<div><b><i><s>x y</s></i></b></div>');
      expect(c.toPlainText(), '*/x y/*');
      select(c, 2, 3);
      c.clearFormatting();
      expect(c.toHtml(), '<div><b><i><s>x </s></i></b>y</div>');
    });

    test('a partly styled selection is styled as a whole', () {
      final c = empty();
      type(c, 'abcd');
      select(c, 0, 2);
      c.toggle(InlineStyle.bold);
      select(c, 0, 4);
      expect(c.isActive(InlineStyle.bold), isFalse);
      c.toggle(InlineStyle.bold);
      expect(c.toHtml(), '<div><b>abcd</b></div>');
    });
  });

  group('html', () {
    test('escapes text and keeps blank lines and spaces', () {
      final c = empty();
      type(c, '<a> & b\n\n  two');
      expect(c.toHtml(), '<div>&lt;a&gt; &amp; b</div><div><br></div><div>&nbsp;&nbsp;two</div>');
    });

    test('links bare addresses in unlinked text', () {
      final c = empty();
      type(c, 'see https://plume.dev.');
      expect(c.toHtml(), '<div>see <a href="https://plume.dev">https://plume.dev</a>.</div>');
    });

    test('drops trailing blank lines and returns nothing for an empty body', () {
      final c = empty();
      type(c, 'hi\n\n  ');
      expect(c.toHtml(), '<div>hi</div>');
      expect(empty().toHtml(), '');
      expect(empty().toPlainText(), '');
    });

    test('reads back what it writes', () {
      final c = empty();
      type(c, 'Hi Sam,\n\nPlan:\n');
      c.toggleList(ListKind.numbered);
      type(c, 'Ship\nTest\n\n');
      type(c, 'Thanks');
      select(c, 0, 2);
      c.toggle(InlineStyle.bold);
      select(c, 15, 19);
      c.setLink(const TextRange(start: 15, end: 19), 'Ship', 'https://example.com/a?b=1&c=2');
      final html = c.toHtml();
      final back = RichTextController.fromHtml(html);
      expect(back.text, c.text);
      expect(back.toHtml(), html);
      expect(back.toPlainText(), c.toPlainText());
    });

    test('reads other clients\' markup', () {
      final c = RichTextController.fromHtml('<html><head><style>p{}</style></head><body>'
          '<p>One <strong>two</strong>\n  <em>three</em></p>'
          '<ul><li><div>a</div></li><li>b</li></ul>'
          '<ol start="3"><li>c</li></ol>'
          '<blockquote>quoted<br>text</blockquote>'
          '<p><a href="mailto:x@y.z">mail</a> &amp;&nbsp;more</p></body></html>');
      expect(c.text, 'One two three\n• a\n• b\n3. c\n> quoted\n> text\nmail & more');
      expect(c.toPlainText(), 'One *two* /three/\n- a\n- b\n3. c\n> quoted\n> text\nmail <mailto:x@y.z> & more');
    });
  });

  group('lists', () {
    test('Enter continues a list and Enter on an empty item ends it', () {
      final c = empty();
      c.toggleList(ListKind.bullet);
      type(c, 'one\ntwo\n');
      expect(c.text, '• one\n• two\n• ');
      type(c, '\n');
      expect(c.text, '• one\n• two\n');
      type(c, 'after');
      expect(c.toHtml(),
          '<ul style="margin:0;padding-left:1.5em"><li>one</li><li>two</li></ul><div>after</div>');
      expect(c.toPlainText(), '- one\n- two\nafter');
    });

    test('numbered items are numbered and renumbered', () {
      final c = empty();
      c.toggleList(ListKind.numbered);
      type(c, 'a\nb\nc');
      expect(c.text, '1. a\n2. b\n3. c');
      // Remove the second item entirely.
      c.value = TextEditingValue(text: c.text.replaceRange(5, 10, ''), selection: const TextSelection.collapsed(offset: 5));
      expect(c.text, '1. a\n2. c');
      expect(c.toHtml(), '<ol style="margin:0;padding-left:1.5em"><li>a</li><li>c</li></ol>');
    });

    test('Backspace after a marker removes it', () {
      final c = empty();
      c.toggleList(ListKind.bullet);
      type(c, 'x');
      c.selection = const TextSelection.collapsed(offset: 2);
      backspace(c);
      expect(c.text, 'x');
      expect(c.selection.baseOffset, 0);
    });

    test('toggling covers every selected line and switches kinds', () {
      final c = empty();
      type(c, 'a\nb\nc');
      select(c, 0, 3);
      c.toggleList(ListKind.bullet);
      expect(c.text, '• a\n• b\nc');
      expect(c.listKind(), ListKind.bullet);
      c.toggleList(ListKind.numbered);
      expect(c.text, '1. a\n2. b\nc');
      c.toggleList(ListKind.numbered);
      expect(c.text, 'a\nb\nc');
    });

    test('a selection ending at a line start leaves that line out', () {
      final c = empty();
      type(c, 'a\nb');
      select(c, 0, 2);
      c.toggleList(ListKind.bullet);
      expect(c.text, '• a\nb');
    });

    test('Enter in a styled item keeps the style for the next item', () {
      final c = empty();
      c.toggleList(ListKind.bullet);
      c.toggle(InlineStyle.bold);
      type(c, 'a\nb');
      expect(c.toHtml(), '<ul style="margin:0;padding-left:1.5em"><li><b>a</b></li><li><b>b</b></li></ul>');
    });
  });

  group('links', () {
    test('links a selection and finds it again', () {
      final c = empty();
      type(c, 'read the docs');
      c.setLink(const TextRange(start: 9, end: 13), 'docs', 'https://plume.dev/docs');
      c.selection = const TextSelection.collapsed(offset: 11);
      expect(c.linkRange(), const TextRange(start: 9, end: 13));
      expect(c.linkAt(9), 'https://plume.dev/docs');
      expect(c.toHtml(), '<div>read the <a href="https://plume.dev/docs">docs</a></div>');
      expect(c.toPlainText(), 'read the docs <https://plume.dev/docs>');
    });

    test('inserts a link at the caret without extending it when typing on', () {
      final c = empty();
      type(c, 'go ');
      c.setLink(const TextRange.collapsed(3), 'here', 'https://a.b');
      expect(c.selection.baseOffset, 7);
      type(c, '!');
      expect(c.toHtml(), '<div>go <a href="https://a.b">here</a>!</div>');
    });

    test('typing inside a link extends it and removing unlinks', () {
      final c = empty();
      type(c, 'abc');
      c.setLink(const TextRange(start: 0, end: 3), 'abc', 'https://a.b');
      c.selection = const TextSelection.collapsed(offset: 1);
      type(c, 'x');
      expect(c.linkRange(), const TextRange(start: 0, end: 4));
      c.setLink(const TextRange(start: 0, end: 4), 'axbc', null);
      expect(c.hasFormatting, isFalse);
    });

    test('normalizes typed addresses', () {
      expect(normalizeLink('plume.dev'), 'https://plume.dev');
      expect(normalizeLink('me@plume.dev'), 'mailto:me@plume.dev');
      expect(normalizeLink('http://x.y'), 'http://x.y');
      expect(normalizeLink('javascript:alert(1)'), isNull);
      expect(normalizeLink('  '), isNull);
    });
  });

  testWidgets('renders styles in a text field', (tester) async {
    final c = RichTextController(text: 'plain bold');
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 10);
    c.toggle(InlineStyle.bold);
    await tester.pumpWidget(MaterialApp(home: Material(child: TextField(controller: c, maxLines: null))));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final span = editable.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)), style: null, withComposing: false);
    final children = span.children!.cast<TextSpan>();
    expect(children.map((s) => s.text), ['plain ', 'bold']);
    expect(children.last.style?.fontWeight, FontWeight.w700);
  });
}
