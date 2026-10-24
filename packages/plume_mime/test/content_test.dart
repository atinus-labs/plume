import 'dart:convert';
import 'dart:typed_data';

import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

/// A message with a forwarded message, nested alternatives and attachments,
/// written the way real mailers do (LF line endings, mixed encodings).
const _nested = 'From: Ana <ana@example.org>\r\n'
    'Subject: Fwd: report\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/mixed; boundary="outer"\r\n'
    '\r\n'
    'preamble is ignored\r\n'
    '--outer\r\n'
    'Content-Type: multipart/alternative; boundary="alt"\r\n'
    '\r\n'
    '--alt\r\n'
    'Content-Type: text/plain; charset=iso-8859-1\r\n'
    'Content-Transfer-Encoding: quoted-printable\r\n'
    '\r\n'
    'Caf=E9 at nine.\r\n'
    '--alt\r\n'
    'Content-Type: multipart/related; boundary="rel"\r\n'
    '\r\n'
    '--rel\r\n'
    'Content-Type: text/html; charset=utf-8\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'PHA+Q2Fmw6kgYXQgbmluZS48aW1nIHNyYz0iY2lkOmxvZ29AeCI+PC9wPg==\r\n'
    '--rel\r\n'
    'Content-Type: image/png\r\n'
    'Content-ID: <logo@x>\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'AQID\r\n'
    '--rel--\r\n'
    '--alt--\r\n'
    '--outer\r\n'
    'Content-Type: message/rfc822\r\n'
    '\r\n'
    'Subject: inner\r\n'
    '\r\n'
    'inner body\r\n'
    '--outer\r\n'
    'Content-Type: application/pdf; name="r.pdf"\r\n'
    'Content-Disposition: attachment; filename="r.pdf"\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'JVBERi0=\r\n'
    '--outer--\r\n';

void main() {
  group('parser', () {
    test('numbers parts like IMAP BODY sections', () {
      final root = parseMimeMessage(latin1.encode(_nested));
      expect(root.partId, '');
      final ids = [for (final p in root.allParts) '${p.partId} ${p.mimeType}'];
      expect(ids, [
        ' multipart/mixed',
        '1 multipart/alternative',
        '1.1 text/plain',
        '1.2 multipart/related',
        '1.2.1 text/html',
        '1.2.2 image/png',
        '2 message/rfc822',
        '3 application/pdf',
      ]);
      expect(root.header('subject'), 'Fwd: report');
      expect(root.parts[2].data, utf8.encode('%PDF-'));
    });

    test('a header-only message and LF line endings', () {
      final root = parseMimeMessage(utf8.encode('Subject: x\nX-Note: Grüße\n'));
      expect(root.partId, '1');
      expect(root.header('X-Note'), 'Grüße', reason: 'raw UTF-8 header (RFC 6532)');
      expect(root.data, isEmpty);
    });
  });

  group('content', () {
    test('extracts bodies, inline images and attachments from a parsed message', () {
      final c = extractContent(parseMimeMessage(latin1.encode(_nested)));
      expect(c.text, 'Café at nine.', reason: 'the CRLF before a boundary belongs to the boundary');
      expect(c.html, '<p>Café at nine.<img src="cid:logo@x"></p>');
      expect(c.attachments.map((a) => (a.partId, a.filename, a.isInline)), [
        ('1.2.2', 'image.png', true),
        ('2', 'message.eml', false),
        ('3', 'r.pdf', false),
      ]);
      expect(c.inlineParts['logo@x'], [1, 2, 3]);
    });

    test('structure-only trees: unresolved bodies, then resolved by part id', () {
      final structure = MimePart(mimeType: 'multipart/alternative', parts: [
        MimePart(partId: '1', mimeType: 'text/plain', headers: const [MimeHeader('Content-Type', 'text/plain')]),
        MimePart(
          partId: '2',
          mimeType: 'text/html',
          headers: const [MimeHeader('Content-Type', 'text/html; charset=windows-1252')],
          size: 900000,
        ),
      ]);
      final first = extractContent(structure);
      expect(first.unresolvedBodyParts.map((p) => p.partId), ['1', '2']);
      expect(first.html, isNull);
      final second = extractContent(structure, resolved: {
        '1': utf8.encode('plain'),
        '2': [0x3C, 0x62, 0x3E, 0x93, 0x51, 0x94], // <b>“Q”
      });
      expect(second.unresolvedBodyParts, isEmpty);
      expect(second.text, 'plain');
      expect(second.html, '<b>“Q”');
    });

    test('attachmentsOfStructure guesses inline parts without the html', () {
      final root = parseMimeMessage(latin1.encode(_nested));
      final list = attachmentsOfStructure(root);
      expect(list.map((a) => (a.partId, a.isInline)), [('1.2.2', true), ('2', false), ('3', false)]);
    });

    test('previewPartOf prefers plain text', () {
      final root = parseMimeMessage(latin1.encode(_nested));
      expect(previewPartOf(root)!.partId, '1.1');
      final htmlOnly = MimePart(mimeType: 'multipart/mixed', parts: [
        MimePart(partId: '1', mimeType: 'text/html', data: Uint8List(0)),
        MimePart(partId: '2', mimeType: 'image/png', data: Uint8List(0)),
      ]);
      expect(previewPartOf(htmlOnly)!.partId, '1');
      expect(previewPartOf(MimePart(partId: '1', mimeType: 'image/png', data: Uint8List(0))), isNull);
    });
  });

  group('previews', () {
    test('html to preview text drops head, styles and tags', () {
      const html = '<html><head><title>T</title><style>p{color:red}</style></head>'
          '<body><!-- hidden --><p>Hello&nbsp;<b>Ana</b>,</p><div>Your&#39;re <a href="x">in</a>.</div>'
          '<script>alert(1)</script></body></html>';
      expect(htmlToPreviewText(html), "Hello Ana , Your're in .");
      expect(htmlToPreviewText('<p>cut in the mid<sp'), 'cut in the mid');
      expect(htmlToPreviewText('<style>unterminated'), '');
    });

    test('previewSnippet skips quotes and cuts at a word boundary', () {
      expect(previewSnippet('Sounds good.\r\n\r\n> On Monday Ana wrote:\r\n> old text\r\nThanks'),
          'Sounds good. Thanks');
      final long = List.filled(60, 'word').join(' ');
      final s = previewSnippet(long, maxLength: 50);
      expect(s.length, lessThanOrEqualTo(50));
      expect(s.endsWith('word'), isTrue);
    });

    test('transfer decoding of fetched parts', () {
      expect(decodeTransferEncoding(ascii.encode('SGVsbG8='), 'BASE64'), utf8.encode('Hello'));
      expect(decodeTransferEncoding(ascii.encode('SGVsbG8gV29y'), 'base64'), utf8.encode('Hello Wor'));
      expect(decodeTransferEncoding(ascii.encode('SGVsbG8gV2'), 'base64'), utf8.encode('Hello W'),
          reason: 'a partial fetch cut mid-group decodes what it can');
      expect(decodeTransferEncoding(ascii.encode('a=3Db=\r\nc'), 'Quoted-Printable'), ascii.encode('a=bc'));
      expect(decodeTransferEncoding([0xE9], '8bit'), [0xE9]);
      expect(decodeTransferEncoding([0xE9], null), [0xE9]);
    });
  });
}
