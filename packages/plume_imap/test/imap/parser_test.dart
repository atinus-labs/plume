import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/src/imap/imap_client.dart';
import 'package:plume_imap/src/imap/imap_exception.dart';
import 'package:plume_imap/src/imap/imap_fetch.dart';
import 'package:plume_imap/src/imap/imap_response.dart';
import 'package:plume_imap/src/imap/mutf7.dart';
import 'package:plume_imap/src/imap/uid_set.dart';
import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

/// Frames and parses [wire] (which may contain several responses).
List<ImapResponse> parseAll(List<int> wire, {int chunk = 1 << 20}) {
  final reader = ImapResponseReader();
  final out = <ImapResponse>[];
  for (var i = 0; i < wire.length; i += chunk) {
    final end = i + chunk > wire.length ? wire.length : i + chunk;
    out.addAll(reader.add(wire.sublist(i, end)).map(ImapParser.parse));
  }
  return out;
}

ImapResponse parseOne(String wire) => parseAll(latin1.encode(wire)).single;

void main() {
  group('framing', () {
    test('literals split across arbitrary chunks, including CRLF inside literals', () {
      final body = 'line one\r\nline two {5}\r\n';
      final wire = utf8.encode('* 1 FETCH (UID 7 BODY[] {${utf8.encode(body).length}}\r\n$body FLAGS (\\Seen))\r\n'
          'P1 OK done\r\n');
      for (final size in [1, 2, 3, 7, 1000]) {
        final responses = parseAll(wire, chunk: size);
        expect(responses, hasLength(2), reason: 'chunk size $size');
        final f = ImapFetch.parse(responses[0].number!, responses[0].data);
        expect(f.uid, 7);
        expect(utf8.decode(f.sections['']!), body);
        expect(f.flags, {r'\Seen'});
        expect(responses[1].tag, 'P1');
      }
    });

    test('zero-length, binary and LITERAL+ style literals', () {
      final bytes = [0, 1, 2, 0x0D, 0x0A, 0xFF];
      final wire = [
        ...latin1.encode('* 2 FETCH (BODY[1] {0}\r\n BODY[2] {6+}\r\n'),
        ...bytes,
        ...latin1.encode(' BODY[3] ~{1}\r\nx)\r\n'),
      ];
      final f = ImapFetch.parse(2, parseAll(wire).single.data);
      expect(f.sections['1'], isEmpty);
      expect(f.sections['2'], bytes);
      expect(latin1.decode(f.sections['3']!), 'x');
    });

    test('oversized literals and lines are refused', () {
      final reader = ImapResponseReader(maxLiteralSize: 10, maxLineLength: 50);
      expect(() => reader.add(latin1.encode('* 1 FETCH (BODY[] {11}\r\n')), throwsA(isA<ImapProtocolException>()));
      final r2 = ImapResponseReader(maxLineLength: 50);
      expect(() => r2.add(latin1.encode('* OK ${'x' * 60}')), throwsA(isA<ImapProtocolException>()));
    });
  });

  group('responses', () {
    test('status responses with codes and text', () {
      final r = parseOne('P7 NO [ALERT] Application-specific password required: https://x/y (Failure)\r\n');
      expect(r.isTagged, isTrue);
      expect(r.status, 'NO');
      expect(r.code!.name, 'ALERT');
      expect(r.text, 'Application-specific password required: https://x/y (Failure)');

      final u = parseOne('* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n');
      expect(u.code!.name, 'PERMANENTFLAGS');
      expect(u.code!.args, r'(\Deleted \Seen \*)');
      expect(parseOne('* OK [UIDVALIDITY 3857529045] UIDs valid\r\n').code!.number, 3857529045);
      final copy = ImapCopyUid.parse(parseOne('P3 OK [COPYUID 38505 304,319:320 3956:3958] Done\r\n').code)!;
      expect(copy.uidValidity, 38505);
      expect(copy.mapping, {304: 3956, 319: 3957, 320: 3958});
      final append = ImapAppendUid.parse(parseOne('P4 OK [APPENDUID 38505 3955] APPEND completed\r\n').code)!;
      expect((append.uidValidity, append.uid), (38505, 3955));
      expect(parseOne('+ idling\r\n').isContinuation, isTrue);
      expect(parseOne('+\r\n').text, '');
      expect(parseOne('* BYE Autologout; idle for too long\r\n').status, 'BYE');
    });

    test('nested lists, quoted strings with escapes, NIL and 8-bit text', () {
      final r = parseOne('* LIST (\\HasNoChildren \\Sent) "/" "Sent \\"Items\\" \\\\ x"\r\n');
      expect(r.type, 'LIST');
      expect(r.data[0].items.map((v) => v.text), [r'\HasNoChildren', r'\Sent']);
      expect(r.data[1].text, '/');
      expect(r.data[2].text, r'Sent "Items" \ x');
      final nil = parseOne('* LIST () NIL INBOX\r\n');
      expect(nil.data[1].isNil, isTrue);
      expect(nil.data[2].text, 'INBOX');
      final utf = parseAll(utf8.encode('* LIST () "/" "Entwürfe"\r\n')).single;
      expect(utf.data[2].text, 'Entwürfe', reason: 'UTF8=ACCEPT servers send raw UTF-8');
    });

    test('untagged data responses', () {
      expect(parseOne('* 23 EXISTS\r\n').number, 23);
      expect(parseOne('* 5 EXPUNGE\r\n').type, 'EXPUNGE');
      final caps = parseOne('* CAPABILITY IMAP4rev1 AUTH=PLAIN LITERAL+ X-GM-EXT-1\r\n');
      expect(caps.data.map((v) => v.text), ['IMAP4rev1', 'AUTH=PLAIN', 'LITERAL+', 'X-GM-EXT-1']);
      final search = parseOne('* SEARCH 2 84 882 (MODSEQ 917162500)\r\n');
      expect(search.data.take(3).map((v) => v.asInt), [2, 84, 882]);
      final esearch = parseOne('* ESEARCH (TAG "P5") UID ALL 1:3,5 COUNT 4\r\n');
      expect(esearch.data.map((v) => v.toString()), ['(TAG "P5")', 'UID', 'ALL', '1:3,5', 'COUNT', '4']);
      final vanished = parseOne('* VANISHED (EARLIER) 41,43:116\r\n');
      expect(vanished.data.last.text, '41,43:116');
      final status = parseOne('* STATUS "Sent" (MESSAGES 231 UIDNEXT 44292 HIGHESTMODSEQ 7011231777)\r\n');
      final s = ImapMailboxStatus.parse(status.data[1].items);
      expect((s.messages, s.uidNext, s.highestModSeq), (231, 44292, 7011231777));
    });

    test('garbage is tolerated where possible and refused where not', () {
      expect(parseOne('* OK [unterminated code\r\n').code!.name, 'UNTERMINATED');
      final odd = parseOne('* FLAGS (\\Seen ) x)\r\n');
      expect(odd.data.first.items.single.text, r'\Seen');
      expect(() => parseOne('HTTP/1.1 400 Bad Request\r\n'), throwsA(isA<ImapProtocolException>()));
    });
  });

  group('fetch items', () {
    test('envelope with encoded words, groups and missing fields', () {
      final r = parseOne('* 12 FETCH (UID 4827 FLAGS (\\Seen \$Forwarded) INTERNALDATE "17-Jul-1996 02:44:25 -0700" '
          'RFC822.SIZE 4286 MODSEQ (12121) '
          'ENVELOPE ("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)" "=?UTF-8?Q?R=C3=A9union?= lundi" '
          '(("=?ISO-8859-1?Q?Ana_L=F3pez?=" NIL "ana" "example.org")) NIL NIL '
          '((NIL NIL "team" NIL)("Ben" NIL "ben" "example.com")(NIL NIL NIL NIL)("Doe, Jane" NIL "jane" "x.org")) '
          'NIL NIL "<parent@x.org>" "<m1@example.org>"))\r\n');
      final f = ImapFetch.parse(r.number!, r.data);
      expect(f.uid, 4827);
      expect(f.flags, {r'\Seen', r'$Forwarded'});
      expect(f.internalDate, DateTime.utc(1996, 7, 17, 9, 44, 25));
      expect(f.size, 4286);
      expect(f.modseq, 12121);
      final e = f.envelope!;
      expect(e.subject, 'Réunion lundi');
      expect(e.from, [const Address('ana@example.org', 'Ana López')]);
      expect(e.to, [const Address('ben@example.com', 'Ben'), const Address('jane@x.org', 'Doe, Jane')]);
      expect(e.cc, isEmpty);
      expect(e.inReplyTo, '<parent@x.org>');
      expect(e.messageId, '<m1@example.org>');
      expect(e.date, DateTime.utc(1996, 7, 17, 9, 23, 25));
    });

    test('Gmail ids and labels', () {
      final r = parseOne('* 1 FETCH (X-GM-THRID 1266894439832287888 X-GM-MSGID 1278455344230334865 '
          'X-GM-LABELS (\\Inbox \\Important "Muy &AOk-tiqueta" Work/Q3) UID 9)\r\n');
      final f = ImapFetch.parse(r.number!, r.data);
      expect(f.gmailMessageId, '11bdfc5cae0c8191');
      expect(f.gmailThreadId, '1194e9c7de1efa90');
      expect(gmailIdToDecimal('11bdfc5cae0c8191'), '1278455344230334865');
      expect(f.gmailLabels, [r'\Inbox', r'\Important', 'Muy étiqueta', 'Work/Q3']);
      final utf = ImapFetch.parse(1, parseAll(utf8.encode('* 1 FETCH (X-GM-LABELS ("Étiquette"))\r\n')).single.data,
          utf8Names: true);
      expect(utf.gmailLabels, ['Étiquette']);
    });

    test('header field sections and partial bodies', () {
      const headers = 'References: <a@x>\r\n <b@x>\r\nList-Unsubscribe: <mailto:u@x>\r\n\r\n';
      final r = parseOne('* 3 FETCH (UID 3 BODY[HEADER.FIELDS (REFERENCES LIST-UNSUBSCRIBE)] {${headers.length}}\r\n'
          '$headers BODY[1]<0> {5}\r\nHello)\r\n');
      final f = ImapFetch.parse(r.number!, r.data);
      final h = headersOf(f.sections['HEADER.FIELDS (REFERENCES LIST-UNSUBSCRIBE)']);
      expect(parseMessageIdList(headerValue(h, 'references')), ['<a@x>', '<b@x>']);
      expect(headerValue(h, 'List-Unsubscribe'), '<mailto:u@x>');
      expect(latin1.decode(f.sections['1']!), 'Hello');
    });

    test('bodystructure becomes a MIME tree with IMAP section ids', () {
      // multipart/mixed[alternative[text/plain, related[html, image]], pdf, message/rfc822]
      final r = parseOne('* 1 FETCH (UID 1 BODYSTRUCTURE ('
          '(("TEXT" "PLAIN" ("CHARSET" "utf-8") NIL NIL "QUOTED-PRINTABLE" 120 4 NIL NIL NIL NIL)'
          '(("TEXT" "HTML" ("CHARSET" "utf-8") NIL NIL "BASE64" 780 10 NIL NIL NIL NIL)'
          '("IMAGE" "PNG" ("NAME" "logo.png") "<logo@x>" NIL "BASE64" 7800 NIL ("INLINE" ("FILENAME" "logo.png")) NIL NIL)'
          ' "RELATED" ("BOUNDARY" "rel" "TYPE" "text/html") NIL NIL NIL)'
          ' "ALTERNATIVE" ("BOUNDARY" "alt") NIL NIL NIL)'
          '("APPLICATION" "PDF" ("NAME" "=?UTF-8?Q?r=C3=A9sum=C3=A9.pdf?=") NIL NIL "BASE64" 78000 NIL '
          '("ATTACHMENT" ("FILENAME*" "utf-8\'\'r%C3%A9sum%C3%A9.pdf")) NIL NIL)'
          '("MESSAGE" "RFC822" NIL NIL NIL "7BIT" 500 (NIL "fwd" NIL NIL NIL NIL NIL NIL NIL NIL) '
          '("TEXT" "PLAIN" NIL NIL NIL "7BIT" 10 1 NIL NIL NIL NIL) 12 NIL ("ATTACHMENT" NIL) NIL NIL)'
          ' "MIXED" ("BOUNDARY" "mix") NIL NIL NIL))\r\n');
      final root = ImapFetch.parse(r.number!, r.data).structure!;
      expect([for (final p in root.allParts) '${p.partId} ${p.mimeType}'], [
        ' multipart/mixed',
        '1 multipart/alternative',
        '1.1 text/plain',
        '1.2 multipart/related',
        '1.2.1 text/html',
        '1.2.2 image/png',
        '2 application/pdf',
        '3 message/rfc822',
      ]);
      final attachments = attachmentsOfStructure(root);
      expect(attachments.map((a) => (a.partId, a.filename, a.isInline)), [
        ('1.2.2', 'logo.png', true),
        ('2', 'résumé.pdf', false),
        ('3', 'message.eml', false),
      ]);
      expect(attachments[1].size, 57000);
      expect(attachments[0].contentId, 'logo@x');
      expect(previewPartOf(root)!.partId, '1.1');
      final content = extractContent(root);
      expect(content.unresolvedBodyParts.map((p) => p.partId), ['1.1', '1.2.1']);
    });

    test('single-part bodystructure is section 1', () {
      final r = parseOne('* 1 FETCH (BODYSTRUCTURE ("text" "html" ("charset" "iso-8859-1") NIL NIL "8bit" 42 2 NIL NIL NIL))\r\n');
      final root = ImapFetch.parse(1, r.data).structure!;
      expect(root.partId, '1');
      expect(root.mimeType, 'text/html');
      expect(root.header('content-type'), 'text/html; charset="iso-8859-1"');
      expect(root.header('content-transfer-encoding'), '8bit');
    });
  });

  group('modified UTF-7', () {
    test('round trips and RFC 3501 examples', () {
      expect(ModifiedUtf7.encode('~peter/mail/台北/日本語'), '~peter/mail/&U,BTFw-/&ZeVnLIqe-');
      expect(ModifiedUtf7.decode('~peter/mail/&U,BTFw-/&ZeVnLIqe-'), '~peter/mail/台北/日本語');
      expect(ModifiedUtf7.encode('Tom & Jerry'), 'Tom &- Jerry');
      expect(ModifiedUtf7.decode('Tom &- Jerry'), 'Tom & Jerry');
      for (final name in ['Entwürfe', 'Корзина', '[Gmail]/Отправленные', 'a&b', '😀 emoji', 'Ü']) {
        expect(ModifiedUtf7.decode(ModifiedUtf7.encode(name)), name);
      }
      expect(ModifiedUtf7.decode('broken &AOk'), 'broken &AOk');
      expect(ModifiedUtf7.decode('bad &!!!-'), 'bad &!!!-');
    });
  });

  group('uid sets', () {
    test('compress, parse, set algebra and chunking', () {
      final s = UidSet.of([5, 1, 2, 3, 9, 10, 11, 20]);
      expect(s.toString(), '1:3,5,9:11,20');
      expect(UidSet.parse('20,1:3,5,9:11,10'), s);
      expect(UidSet.parse('3:1'), UidSet.of([1, 2, 3]));
      expect(s.length, 8);
      expect((s.min, s.max), (1, 20));
      expect(s.contains(10), isTrue);
      expect(s.contains(12), isFalse);
      expect(s.difference(UidSet.parse('2,9:30')).toString(), '1,3,5');
      expect(s.intersection(UidSet.range(3, 10)).toString(), '3,5,9:10');
      expect(s.union(UidSet.parse('4,6:8')).toString(), '1:11,20');
      expect(s.from(10).toString(), '10:11,20');
      expect(s.newest(4).toString(), '9:11,20');
      expect(UidSet.range(5, 3).isEmpty, isTrue);
      final big = UidSet.of([for (var i = 1; i < 5000; i += 2) i]);
      final chunks = big.chunks(maxChars: 100);
      expect(chunks.every((c) => c.toString().length <= 100), isTrue);
      expect(chunks.fold(UidSet.empty, (a, b) => a.union(b)), big);
    });
  });

  test('internal dates round trip', () {
    final d = DateTime.utc(2026, 10, 4, 7, 5, 9);
    expect(formatInternalDate(d), '04-Oct-2026 07:05:09 +0000');
    expect(parseInternalDate(formatInternalDate(d)), d);
    expect(parseInternalDate(' 4-Oct-2026 09:05:09 +0200'), d);
  });
}
