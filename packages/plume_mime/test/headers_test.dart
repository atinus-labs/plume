import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 2047', () {
    test('decodes B and Q encoded-words', () {
      expect(decodeHeaderValue('=?UTF-8?B?w4ljaGFudGlsbG9uIG5vIDQ=?='), 'Échantillon no 4');
      expect(decodeHeaderValue('=?ISO-8859-1?Q?Caf=E9_cr=E8me?='), 'Café crème');
      expect(decodeHeaderValue('=?utf-8?q?Gr=C3=BC=C3=9Fe?= aus Wien'), 'Grüße aus Wien');
    });

    test('drops whitespace between adjacent words and joins split characters', () {
      // "日本語" split mid-character across two B words.
      final bytes = utf8.encode('日本語');
      final first = base64.encode(bytes.sublist(0, 4));
      final second = base64.encode(bytes.sublist(4));
      expect(decodeHeaderValue('=?UTF-8?B?$first?=\r\n =?UTF-8?B?$second?='), '日本語');
      expect(decodeHeaderValue('=?UTF-8?Q?a?= =?UTF-8?Q?b?='), 'ab');
      // Whitespace between an encoded-word and plain text is kept.
      expect(decodeHeaderValue('Re: =?UTF-8?Q?caf=C3=A9?= time'), 'Re: café time');
    });

    test('handles mixed charsets, language tags and malformed input', () {
      expect(decodeHeaderValue('=?iso-8859-15?Q?=A4?= =?UTF-8?B?4oKs?='), '€€');
      expect(decodeHeaderValue('=?UTF-8*en?Q?Hi?='), 'Hi');
      expect(decodeHeaderValue('=?UTF-8?X?bogus?='), '=?UTF-8?X?bogus?=');
      expect(decodeHeaderValue('plain = text ?= here'), 'plain = text ?= here');
      expect(decodeHeaderValue('=?UTF-8?B?SGVsbG8?='), 'Hello', reason: 'missing padding');
      // Gmail already decoded it: unchanged.
      expect(decodeHeaderValue('Ünïcødé already'), 'Ünïcødé already');
    });

    test('encodes into words of at most 75 characters without splitting characters', () {
      final text = '日本語のテキスト' * 6;
      final words = encodeWords(text);
      expect(words.length, greaterThan(1));
      expect(words.every((w) => w.length <= 75), isTrue);
      expect(decodeHeaderValue(words.join('\r\n ')), text);
      expect(headerNeedsEncoding('plain ascii'), isFalse);
      expect(headerNeedsEncoding('looks =?like?= a word'), isTrue);
      expect(headerNeedsEncoding('naïve'), isTrue);
    });
  });

  group('charsets', () {
    test('utf-8 and us-ascii', () {
      expect(decodeCharset(utf8.encode('héllo'), 'utf-8'), 'héllo');
      expect(decodeCharset(utf8.encode('héllo'), '"UTF8"'), 'héllo');
      expect(decodeCharset(ascii.encode('plain'), 'us-ascii'), 'plain');
      // Mislabelled 8-bit data: UTF-8 first, else Windows-1252.
      expect(decodeCharset(utf8.encode('née'), 'us-ascii'), 'née');
      expect(decodeCharset([0x6E, 0xE9, 0x65], 'us-ascii'), 'née');
      expect(decodeCharset([0xEF, 0xBB, 0xBF, 0x41], 'utf-8'), 'A', reason: 'BOM stripped');
    });

    test('iso-8859-1, windows-1252 and iso-8859-15', () {
      expect(decodeCharset([0x63, 0x61, 0x66, 0xE9], 'iso-8859-1'), 'café');
      expect(decodeCharset([0x93, 0x51, 0x94], 'ISO-8859-1'), '“Q”', reason: 'WHATWG: latin1 is cp1252');
      expect(decodeCharset([0x80, 0x20, 0x99, 0x20, 0x85], 'windows-1252'), '€ ™ …');
      expect(decodeCharset([0xA4, 0xBD, 0xE9], 'iso-8859-15'), '€œé');
      expect(decodeCharset([0xA4], 'latin1'), '¤');
    });

    test('utf-16 with and without BOM', () {
      final text = 'Hé😀';
      final units = text.codeUnits;
      final be = [for (final u in units) ...[u >> 8, u & 0xFF]];
      final le = [for (final u in units) ...[u & 0xFF, u >> 8]];
      expect(decodeCharset([0xFE, 0xFF, ...be], 'utf-16'), text);
      expect(decodeCharset([0xFF, 0xFE, ...le], 'UTF-16'), text);
      expect(decodeCharset(be, 'utf-16'), text, reason: 'no BOM: big-endian');
      expect(decodeCharset(le, 'utf-16le'), text);
      expect(decodeCharset(be, 'utf-16be'), text);
    });

    test('unknown charsets and invalid bytes fall back to lenient utf-8', () {
      expect(decodeCharset(utf8.encode('ok ✓'), 'x-unknown'), 'ok ✓');
      expect(decodeCharset([0x61, 0xFF, 0x62], 'utf-8'), 'a�b');
      expect(decodeCharset(utf8.encode('x'), null), 'x');
    });
  });

  group('structured header values', () {
    test('parses parameters, quoting and RFC 2231', () {
      final ct = HeaderValue.parse('Text/HTML; charset="ISO-8859-1"; format=flowed');
      expect(ct.value, 'text/html');
      expect(ct['charset'], 'ISO-8859-1');
      expect(ct['FORMAT'], 'flowed');

      final cd = HeaderValue.parse("attachment; filename*=UTF-8''%E2%82%AC%20rates.pdf; filename=\"fallback.pdf\"");
      expect(cd.value, 'attachment');
      expect(cd['filename'], '€ rates.pdf');

      final continued = HeaderValue.parse("attachment;\r\n filename*0*=UTF-8''na%C3%AF;\r\n filename*1=ve.txt");
      expect(continued['filename'], 'naïve.txt');

      final quoted = HeaderValue.parse(r'attachment; filename="a \"quoted\"; name.txt"');
      expect(quoted['filename'], 'a "quoted"; name.txt');

      final encodedWord = HeaderValue.parse('image/png; name="=?UTF-8?B?w6lsw6k=?=.png"');
      expect(encodedWord['name'], 'élé.png');
    });
  });

  group('snippets and dates', () {
    test('decodes HTML entities and strips preheader padding', () {
      expect(cleanSnippet('Tom &amp; Jerry&#39;s &quot;deal&quot; &lt;3 &#x1F600; &euro;5'),
          'Tom & Jerry\'s "deal" <3 😀 €5');
      expect(cleanSnippet('Sale ends soon ͏ ‌ ͏ ‌  now'), 'Sale ends soon now');
      expect(cleanSnippet('&unknown; stays'), '&unknown; stays');
    });

    test('parses RFC 5322 dates leniently', () {
      expect(parseRfc5322Date('Tue, 14 Nov 2023 22:13:20 +0000'), DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(parseRfc5322Date('14 Nov 2023 23:13:20 +0100'), DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(parseRfc5322Date('Tue, 14 Nov 23 17:13 EST'), DateTime.utc(2023, 11, 14, 22, 13));
      expect(parseRfc5322Date('Tue, 14 Nov 2023 22:13:20 GMT (UTC)'), DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(parseRfc5322Date('garbage'), isNull);
      final now = DateTime(2026, 10, 24, 18, 5, 9);
      expect(parseRfc5322Date(formatRfc5322Date(now)), now.toUtc());
    });
  });

  group('addresses', () {
    test('parses quoted, encoded and malformed address lists', () {
      final list = parseAddressHeader(
        '"Doe, Jane" <jane@x.org>, =?UTF-8?Q?J=C3=BCrgen_M=C3=BCller?= <jm@x.de>, bob@x.com (Bob B), '
        '<bare@x.net>, "=?UTF-8?B?w4lsaXNl?=" <elise@x.fr>',
      );
      expect(list, [
        const Address('jane@x.org', 'Doe, Jane'),
        const Address('jm@x.de', 'Jürgen Müller'),
        const Address('bob@x.com', 'Bob B'),
        const Address('bare@x.net'),
        const Address('elise@x.fr', 'Élise'),
      ]);
    });

    test('keeps unquoted commas that Gmail leaves in decoded names', () {
      expect(parseAddressHeader('Müller, Hans <hans@x.de>, Ana <ana@x.pt>'), [
        const Address('hans@x.de', 'Müller, Hans'),
        const Address('ana@x.pt', 'Ana'),
      ]);
    });

    test('flattens groups and ignores empty ones', () {
      expect(parseAddressHeader('undisclosed-recipients:;'), isEmpty);
      expect(parseAddressHeader('Team: a@x.com, B <b@x.com>;'), [const Address('a@x.com'), const Address('b@x.com', 'B')]);
      expect(parseAddressHeader(''), isEmpty);
      expect(parseAddressHeader(null), isEmpty);
    });
  });
}
