import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

void main() {
  final fixedDate = DateTime(2026, 10, 24, 18, 30, 5);
  MimeMessageBuilder builder() => MimeMessageBuilder(random: Random(42), clock: () => fixedDate);

  final logo = Uint8List.fromList(List<int>.generate(300, (i) => (i * 7) & 0xFF));
  final pdf = Uint8List.fromList(List<int>.generate(5000, (i) => (i * 13) & 0xFF));

  final message = OutgoingMessage(
    accountId: 'acc1',
    from: const Address('zoe@plume.example', 'Zoë Ångström'),
    to: const [
      Address('jane@x.org', 'Doe, Jane'),
      Address('jm@x.de', 'Jürgen Müller'),
      Address('plain@x.com'),
      Address('long.recipient.address.number.one@very-long-domain.example.com', 'Recipient One'),
    ],
    cc: const [Address('cc@x.org', 'CC Person')],
    bcc: const [Address('hidden@x.org')],
    subject: 'Résumé of the 日本 offsite — final agenda and logistics for everyone attending',
    textBody: 'Hi all,\nHere is the plan. Café at 9.\n\n-- \nZoë',
    htmlBody: '<p>Hi all,</p><p>Here is the plan. Café at 9.</p><img src="cid:logo@plume">',
    attachments: [
      OutgoingAttachment(filename: 'logo.png', mimeType: 'image/png', bytes: logo, contentId: 'logo@plume'),
      OutgoingAttachment(filename: 'Agenda – été.pdf', mimeType: 'application/pdf', bytes: pdf),
    ],
    threadId: 'thread-1',
    inReplyTo: '<parent@x.org>',
    references: const ['<root@x.org>', 'parent@x.org'],
  );

  test('round-trips through the parser and the content extractor', () {
    final built = builder().build(message);
    final text = utf8.decode(built.bytes);

    // 7-bit clean, RFC 5322 line limits, CRLF only.
    expect(built.bytes.every((b) => b < 0x80), isTrue);
    final lines = text.split('\r\n');
    expect(lines.every((l) => l.length <= 998), isTrue);
    expect(text.replaceAll('\r\n', '').contains('\n'), isFalse);

    final root = parseMimeMessage(built.bytes);
    String? h(String name) => root.header(name);

    expect(h('MIME-Version'), '1.0');
    expect(parseRfc5322Date(h('Date')), fixedDate.toUtc());
    expect(h('Message-ID'), built.messageId);
    expect(built.messageId, matches(RegExp(r'^<[0-9a-z]+\.[0-9a-f]{20}@plume\.example>$')));
    expect(h('In-Reply-To'), '<parent@x.org>');
    expect(unfoldHeader(h('References')!), '<root@x.org> <parent@x.org>');
    expect(decodeHeaderValue(h('Subject')!), message.subject);
    expect(h('Subject'), contains('=?UTF-8?B?'));
    expect(parseAddressHeader(h('From')), [message.from]);
    expect(parseAddressHeader(h('To')), message.to);
    expect(parseAddressHeader(h('Cc')), message.cc);
    expect(parseAddressHeader(h('Bcc')), message.bcc);

    // Structure: mixed[related[alternative[text, html], image], pdf].
    expect(root.mimeType, 'multipart/mixed');
    final related = root.parts[0];
    expect(related.mimeType, 'multipart/related');
    expect(related.parts[0].mimeType, 'multipart/alternative');
    expect(related.parts[0].parts.map((p) => p.mimeType), ['text/plain', 'text/html']);
    expect(related.parts[1].mimeType, 'image/png');
    expect(root.parts[1].mimeType, 'application/pdf');
    // IMAP section numbering, so attachments can be fetched by part id.
    expect(root.partId, '');
    expect(root.parts[1].partId, '2');
    expect(related.parts[0].parts[1].partId, '1.1.2');
    expect(related.parts[1].partId, '1.2');

    final content = extractContent(root);
    expect(content.text, message.textBody.replaceAll('\n', '\r\n'));
    expect(content.html, message.htmlBody);
    expect(content.inlineParts['logo@plume'], logo);
    expect(content.attachments, hasLength(2));
    final image = content.attachments[0];
    expect(image.isInline, isTrue);
    expect(image.contentId, 'logo@plume');
    expect(image.filename, 'logo.png');
    final attachment = content.attachments[1];
    expect(attachment.isInline, isFalse);
    expect(attachment.filename, 'Agenda – été.pdf');
    expect(attachment.mimeType, 'application/pdf');
    expect(attachment.size, pdf.length);
    expect(root.parts[1].data, pdf);
  });

  test('base64 bodies are wrapped at 76 characters and headers folded', () {
    final text = utf8.decode(builder().build(message).bytes);
    final lines = text.split('\r\n');
    final base64Lines = lines.where((l) => RegExp(r'^[A-Za-z0-9+/=]{20,}$').hasMatch(l)).toList();
    expect(base64Lines, isNotEmpty);
    expect(base64Lines.every((l) => l.length <= 76), isTrue);
    expect(base64Lines.where((l) => l.length == 76), isNotEmpty);

    final headerBlock = text.substring(0, text.indexOf('\r\n\r\n'));
    final toHeader = RegExp(r'^To: .*(\r\n[ \t].*)*', multiLine: true).firstMatch(headerBlock)!.group(0)!;
    expect(toHeader, contains('\r\n '), reason: 'long address list is folded');
    expect(toHeader.split('\r\n').every((l) => l.length <= 78), isTrue);
    final subject = RegExp(r'^Subject: .*(\r\n[ \t].*)*', multiLine: true).firstMatch(headerBlock)!.group(0)!;
    expect(subject.split('\r\n').every((l) => l.length <= 78), isTrue);
    expect(headerBlock, contains('"Doe, Jane" <jane@x.org>'));
  });

  test('plain ASCII text without html is a single 7bit part', () {
    final built = builder().build(const OutgoingMessage(
      accountId: 'a',
      from: Address('me@example.com'),
      to: [Address('you@example.com')],
      subject: 'Lunch?',
      textBody: 'Noon at the usual place.\nBring Ben.',
    ));
    final text = utf8.decode(built.bytes);
    expect(text, contains('Content-Type: text/plain; charset="UTF-8"\r\nContent-Transfer-Encoding: 7bit\r\n'));
    expect(text, contains('\r\n\r\nNoon at the usual place.\r\nBring Ben.\r\n'));
    expect(text, isNot(contains('multipart')));
    expect(text, contains('Subject: Lunch?\r\n'));
    expect(text, isNot(contains('Cc:')));
    final root = parseMimeMessage(built.bytes);
    expect(root.partId, '1', reason: 'the body of a single-part message is section 1');
    // The final CRLF of a single-part message belongs to its body.
    expect(extractContent(root).text, 'Noon at the usual place.\r\nBring Ben.\r\n');
    expect(built.raw, base64Url.encode(built.bytes));
  });

  test('without html, cid attachments are regular attachments', () {
    final built = builder().build(OutgoingMessage(
      accountId: 'a',
      from: const Address('me@example.com'),
      subject: '',
      textBody: 'photo',
      attachments: [OutgoingAttachment(filename: 'p.jpg', mimeType: 'image/jpeg', bytes: logo, contentId: 'c1')],
    ));
    final root = parseMimeMessage(built.bytes);
    expect(root.mimeType, 'multipart/mixed');
    expect(root.parts.map((p) => p.mimeType), ['text/plain', 'image/jpeg']);
    expect(root.header('Content-Disposition'), isNull);
    expect(root.parts[1].header('Content-Disposition'), startsWith('attachment'));
  });

  test('display names are quoted or encoded as needed', () {
    expect(MimeMessageBuilder.formatAddress(const Address('a@x.org')), 'a@x.org');
    expect(MimeMessageBuilder.formatAddress(const Address('a@x.org', 'Ann Lee')), 'Ann Lee <a@x.org>');
    expect(MimeMessageBuilder.formatAddress(const Address('a@x.org', 'Lee, Ann "AL"')),
        r'"Lee, Ann \"AL\"" <a@x.org>');
    final encoded = MimeMessageBuilder.formatAddress(const Address('a@x.org', 'Ånn'));
    expect(encoded, '=?UTF-8?B?w4Vubg==?= <a@x.org>');
    expect(parseAddressHeader(encoded), [const Address('a@x.org', 'Ånn')]);
  });

  test('SMTP variant without Bcc is otherwise identical', () {
    final b = builder();
    final withBcc = b.build(message, messageId: '<fixed@plume.example>', date: fixedDate);
    final withoutBcc = b.build(message, messageId: '<fixed@plume.example>', date: fixedDate, includeBcc: false);
    final a = utf8.decode(withBcc.bytes);
    final c = utf8.decode(withoutBcc.bytes);
    expect(a, contains('\r\nBcc: hidden@x.org\r\n'));
    expect(c, isNot(contains('Bcc:')));
    expect(parseMimeMessage(withoutBcc.bytes).header('Message-ID'), '<fixed@plume.example>');
    // Boundaries are random per build, so compare content, not bytes.
    expect(extractContent(parseMimeMessage(withoutBcc.bytes)).text, extractContent(parseMimeMessage(withBcc.bytes)).text);
  });
}
