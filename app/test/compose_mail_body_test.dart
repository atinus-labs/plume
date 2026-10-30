import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/compose/mail_body.dart';
import 'package:plume/src/ui/compose/rich_text.dart';
import 'package:plume_core/plume_core.dart';

final _original = Message(
  accountId: 'a1',
  id: 'm1',
  threadId: 't1',
  subject: 'Plans',
  from: const Address('maya@example.com', 'Maya Chen'),
  to: const [Address('me@example.org', 'Me')],
  date: DateTime.utc(2026, 10, 14, 10, 42),
);

const _typedHtml = '<div>Hi <b>Maya</b>,</div><div><br></div><ul style="margin:0;padding-left:1.5em;list-style-type:disc">'
    '<li>Thursday works</li></ul>';
const _typedText = 'Hi *Maya*,\n\n- Thursday works';
const _signature = 'Alex\nhttps://example.com';

/// The body of [html] as the editor would write it back.
String _reread(String html) => documentFromHtml(html).toMailHtml();

void main() {
  group('a message Plume wrote comes apart again', () {
    test('a formatted reply with a signature', () {
      final quote = replyQuote(_original, 'See you then?\n\nMaya');
      final body = editableBody(
        text: mailText(_typedText, signature: _signature, quote: quote),
        html: mailHtml(_typedHtml, signature: _signature, quote: quote),
        signature: _signature,
        reply: true,
      );
      expect(body.quote, quote);
      expect(body.text, _typedText);
      expect(_reread(body.html!), _typedHtml);
      expect(body.html, isNot(contains('plume_signature')));
    });

    test('a signature changed since is still taken out of HTML', () {
      final body = editableBody(
        text: mailText(_typedText, signature: 'Old signature'),
        html: mailHtml(_typedHtml, signature: 'Old signature'),
        signature: _signature,
      );
      expect(body.text, _typedText);
      expect(_reread(body.html!), _typedHtml);
      expect(body.quote, isNull);
    });

    test('a forward, with nothing typed yet', () {
      final quote = forwardQuote(_original, 'Agenda attached.');
      final body = editableBody(text: mailText('', quote: quote), html: mailHtml('', quote: quote));
      expect(body.quote, quote);
      expect(body.text, '');
      expect(_reread(body.html!), '');
    });

    test('a plain text reply', () {
      final quote = replyQuote(_original, 'See you then?');
      final body = editableBody(
        text: mailText('Yes, Thursday.', signature: _signature, quote: quote),
        signature: _signature,
        reply: true,
      );
      expect(body, (text: 'Yes, Thursday.', html: null, quote: quote));
    });

    test('built again, it is the same message', () {
      final quote = replyQuote(_original, 'See you then?');
      final text = mailText(_typedText, signature: _signature, quote: quote);
      final html = mailHtml(_typedHtml, signature: _signature, quote: quote);
      final body = editableBody(text: text, html: html, signature: _signature, reply: true);
      expect(mailText(body.text, signature: _signature, quote: body.quote), text);
      expect(mailHtml(_reread(body.html!), signature: _signature, quote: body.quote), html);
    });
  });

  group('what cannot be told apart stays in the text', () {
    test('a plain text signature that is not the account’s', () {
      final body = editableBody(text: 'Thanks!\n\n-- \nSomeone else', signature: _signature);
      expect(body.text, 'Thanks!\n\n-- \nSomeone else');
    });

    test('a quote typed at the end of a formatted message', () {
      const html = '<div>As you said:</div><blockquote style="margin:0 0 0 0.8ex;border-left:3px solid #ccc;padding-left:1ex">'
          '<div>Ship it</div></blockquote>';
      final body = editableBody(text: 'As you said:\n> Ship it', html: mailHtml(html), reply: true);
      expect(body.quote, isNull);
      expect(body.text, 'As you said:\n> Ship it');
      expect(_reread(body.html!), html);
    });

    test('quoted lines in a message that is not a reply', () {
      final body = editableBody(text: 'Notes:\n> one\n> two');
      expect(body.quote, isNull);
      expect(body.text, 'Notes:\n> one\n> two');
    });
  });

  test('a reply drafted in Gmail', () {
    const text = 'Sounds good\r\n\r\nOn Tue, 14 Oct 2025 at 10:42, Maya Chen <maya@example.com> wrote:\r\n\r\n'
        '> See you then?\r\n>\r\n> Maya\r\n';
    const html = '<div dir="ltr">Sounds good</div><br><div class="gmail_quote gmail_quote_container">'
        '<div dir="ltr" class="gmail_attr">On Tue, 14 Oct 2025 at 10:42, Maya Chen &lt;maya@example.com&gt; wrote:<br></div>'
        '<blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex">See you then?<br><br>Maya</blockquote></div>';
    final body = editableBody(text: text, html: html, reply: true);
    expect(body.text, 'Sounds good');
    expect(body.quote, startsWith('On Tue, 14 Oct 2025'));
    expect(body.quote, endsWith('> Maya'));
    expect(_reread(body.html!), '<div>Sounds good</div>');
  });
}
