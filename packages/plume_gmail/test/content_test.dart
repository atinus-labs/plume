import 'dart:convert';

import 'package:plume_gmail/src/api/gmail_types.dart';
import 'package:plume_gmail/src/mapping/content_extractor.dart';
import 'package:plume_gmail/src/mapping/message_mapper.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

GmailMessagePart payload(Map<String, Object?> json) => GmailMessagePart.fromJson(json);

void main() {
  final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

  test('single text/plain part', () {
    final c = extractContent(payload(textPart('text/plain', 'Just text.\nLine 2')));
    expect(c.text, 'Just text.\nLine 2');
    expect(c.html, isNull);
    expect(c.attachments, isEmpty);
  });

  test('realistic newsletter: mixed > alternative > related, with attachment', () {
    // The shape Gmail returns for a message composed in Apple Mail / Gmail
    // with an inline logo and a PDF attached.
    final c = extractContent(payload(part('multipart/mixed', parts: [
      part('multipart/alternative', partId: '0', parts: [
        textPart('text/plain', 'Hello Ana,\nSee the report.', partId: '0.0'),
        part('multipart/related', partId: '0.1', headers: [header('Content-Type', 'multipart/related; boundary="r"')], parts: [
          textPart('text/html', '<p>Hello Ana,</p><img src="cid:logo@plume">', partId: '0.1.0'),
          part('image/png', partId: '0.1.1', filename: 'logo.png', data: b64Bytes(png), headers: [
            header('Content-Type', 'image/png; name="logo.png"'),
            header('Content-Disposition', 'inline; filename="logo.png"'),
            header('Content-ID', '<logo@plume>'),
          ]),
        ]),
      ]),
      part('application/pdf', partId: '1', filename: 'Q3 report.pdf', attachmentId: 'ANGjdJ_pdf', size: 48213, headers: [
        header('Content-Type', 'application/pdf; name="Q3 report.pdf"'),
        header('Content-Disposition', 'attachment; filename="Q3 report.pdf"'),
      ]),
    ])));

    expect(c.html, '<p>Hello Ana,</p><img src="cid:logo@plume">');
    expect(c.text, 'Hello Ana,\nSee the report.');
    expect(c.unresolvedBodyParts, isEmpty);
    expect(c.attachments, hasLength(2));
    final logo = c.attachments[0];
    expect(logo.partId, '0.1.1');
    expect(logo.filename, 'logo.png');
    expect(logo.mimeType, 'image/png');
    expect(logo.contentId, 'logo@plume');
    expect(logo.isInline, isTrue);
    expect(logo.size, png.length);
    expect(c.inlineParts['logo@plume'], png);
    final pdf = c.attachments[1];
    expect(pdf.partId, '1');
    expect(pdf.providerId, 'ANGjdJ_pdf');
    expect(pdf.filename, 'Q3 report.pdf');
    expect(pdf.size, 48213);
    expect(pdf.isInline, isFalse);
    expect(pdf.contentId, isNull);
    final body = c.toBody();
    expect(body.isEmpty, isFalse);
    expect(body.inlineParts.keys, ['logo@plume']);
  });

  test('decodes each part in its own charset', () {
    final cp1252 = [0x93, 0x48, 0x69, 0x94, 0x20, 0x80, 0x35]; // “Hi” €5
    final latin9 = [0x50, 0x72, 0x69, 0x78, 0x20, 0xA4]; // Prix €
    final c = extractContent(payload(part('multipart/alternative', parts: [
      part('text/plain', partId: '0', data: b64Bytes(latin9), headers: [header('Content-Type', 'text/plain; charset=iso-8859-15')]),
      part('text/html', partId: '1', data: b64Bytes(cp1252), headers: [header('Content-Type', 'text/html; charset="windows-1252"')]),
    ])));
    expect(c.text, 'Prix €');
    expect(c.html, '\u201CHi\u201D €5');
  });

  test('utf-16 html body', () {
    final units = '<b>Grüße</b>'.codeUnits;
    final bytes = [0xFF, 0xFE, for (final u in units) ...[u & 0xFF, u >> 8]];
    final c = extractContent(payload(
        part('text/html', data: b64Bytes(bytes), headers: [header('Content-Type', 'text/html; charset=UTF-16')])));
    expect(c.html, '<b>Grüße</b>');
  });

  test('format=flowed plain text is unwrapped', () {
    final c = extractContent(payload(part('text/plain',
        data: b64('This is a long \r\nflowed line.\r\n> quoted \r\n> more\r\nFixed line\r\n'),
        headers: [header('Content-Type', 'text/plain; charset=utf-8; format=flowed')])));
    expect(c.text, 'This is a long flowed line.\n> quoted more\nFixed line\n');
  });

  test('Apple Mail style mixed body with an inline image between text parts', () {
    final c = extractContent(payload(part('multipart/mixed', parts: [
      textPart('text/plain', 'Before the photo', partId: '0'),
      part('image/jpeg', partId: '1', filename: 'IMG_0001.jpeg', attachmentId: 'att-photo', size: 900000, headers: [
        header('Content-Disposition', 'inline; filename=IMG_0001.jpeg'),
        header('Content-ID', '<photo-1>'),
      ]),
      textPart('text/plain', 'After the photo', partId: '2'),
    ])));
    expect(c.text, 'Before the photo\n\nAfter the photo');
    expect(c.html, isNull);
    // No HTML references the image, so it is an attachment.
    expect(c.attachments.single.isInline, isFalse);
    expect(c.attachments.single.providerId, 'att-photo');
    expect(c.inlineParts, isEmpty);
  });

  test('text and html bodies in mixed are combined into html', () {
    final c = extractContent(payload(part('multipart/mixed', parts: [
      textPart('text/html', '<p>Part one</p>', partId: '0'),
      textPart('text/plain', 'a < b & c', partId: '1'),
    ])));
    expect(c.html, '<p>Part one</p>\n<div style="white-space: pre-wrap">a &lt; b &amp; c</div>');
    expect(c.text, 'a < b & c');
  });

  test('a cid image that the html does not reference is an attachment', () {
    final c = extractContent(payload(part('multipart/related', parts: [
      textPart('text/html', '<p>No images here</p>', partId: '0'),
      part('image/gif', partId: '1', data: b64Bytes([1, 2]), headers: [header('Content-ID', '<unused@x>')]),
    ])));
    expect(c.attachments.single.isInline, isFalse);
    expect(c.attachments.single.filename, 'image.gif');
    expect(c.inlineParts, isEmpty);
  });

  test('multipart/related honours the start parameter', () {
    final c = extractContent(payload(part('multipart/related', headers: [
      header('Content-Type', 'multipart/related; boundary=b; start="<root@x>"; type="text/html"'),
    ], parts: [
      part('image/png', partId: '0', data: b64Bytes(png), headers: [header('Content-ID', '<img@x>')]),
      part('text/html', partId: '1', data: b64('<img src="CID:img@x">'), headers: [
        header('Content-Type', 'text/html; charset=utf-8'),
        header('Content-ID', '<root@x>'),
      ]),
    ])));
    expect(c.html, '<img src="CID:img@x">');
    expect(c.attachments.single.isInline, isTrue, reason: 'cid: match is case-insensitive');
    expect(c.inlineParts['img@x'], png);
  });

  test('large html body delivered by attachmentId is reported, then resolved', () {
    final json = part('multipart/alternative', parts: [
      textPart('text/plain', 'short', partId: '0'),
      part('text/html', partId: '1', attachmentId: 'big-html', size: 2000000, headers: [
        header('Content-Type', 'text/html; charset=iso-8859-1'),
      ]),
    ]);
    final first = extractContent(payload(json));
    expect(first.unresolvedBodyParts.single.handle, 'big-html');
    expect(first.html, isNull);
    expect(first.text, 'short');
    final second = extractContent(payload(json), resolved: {
      'big-html': [0x3C, 0x70, 0x3E, 0xE9, 0x3C, 0x2F, 0x70, 0x3E], // <p>é</p> in latin-1
    });
    expect(second.unresolvedBodyParts, isEmpty);
    expect(second.html, '<p>é</p>');
    expect(second.attachments, isEmpty);
  });

  test('calendar invites, forwarded messages, signatures and odd filenames', () {
    final c = extractContent(payload(part('multipart/signed', parts: [
      part('multipart/mixed', partId: '0', parts: [
        part('multipart/alternative', partId: '0.0', parts: [
          textPart('text/plain', 'Invite', partId: '0.0.0'),
          textPart('text/html', '<p>Invite</p>', partId: '0.0.1'),
          part('text/calendar', partId: '0.0.2', data: b64('BEGIN:VCALENDAR'), headers: [
            header('Content-Type', 'text/calendar; charset=UTF-8; method=REQUEST'),
          ]),
        ]),
        part('message/rfc822', partId: '0.1', attachmentId: 'fwd', size: 5000),
        part('application/octet-stream', partId: '0.2', attachmentId: 'a2', size: 10, headers: [
          header('Content-Type', 'application/octet-stream; name="=?UTF-8?B?w6l0w6kudHh0?="'),
        ]),
        part('text/plain', partId: '0.3', attachmentId: 'a3', size: 3, filename: r'C:\Users\x\notes.txt'),
      ]),
      part('application/pkcs7-signature', partId: '1', attachmentId: 'sig', size: 2000),
    ])));
    expect(c.html, '<p>Invite</p>');
    expect(c.text, 'Invite');
    expect(c.attachments.map((a) => a.filename),
        ['invite.ics', 'message.eml', 'été.txt', 'notes.txt', 'smime.p7s']);
    expect(c.attachments.map((a) => a.partId), ['0.0.2', '0.1', '0.2', '0.3', '1']);
    expect(c.attachments.every((a) => !a.isInline), isTrue);
  });

  test('full messages map attachments onto Message', () {
    final gm = GmailMessage.fromJson(gmailMessage(
      id: 'm1',
      threadId: 't1',
      payload: part('multipart/mixed', parts: [
        textPart('text/plain', 'see attached', partId: '0'),
        part('application/zip', partId: '1', filename: 'files.zip', attachmentId: 'z', size: 77),
      ]),
    ));
    final content = extractContent(gm.payload!);
    final m = GmailMessageMapper.toMessage('acc', gm, content: content);
    expect(m.hasAttachments, isTrue);
    expect(m.attachments.single.filename, 'files.zip');
    expect(utf8.decode(utf8.encode(content.text!)), 'see attached');
  });
}
