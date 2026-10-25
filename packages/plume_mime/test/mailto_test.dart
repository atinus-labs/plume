import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart';
import 'package:test/test.dart';

void main() {
  List<String> emails(List<Address> list) => [for (final a in list) a.email];

  test('rejects other schemes', () {
    expect(MailtoLink.tryParse('https://example.org'), isNull);
    expect(MailtoLink.tryParse('mail'), isNull);
    expect(MailtoLink.tryParse(''), isNull);
  });

  test('bare and empty links', () {
    final empty = MailtoLink.tryParse('mailto:')!;
    expect(empty.isEmpty, isTrue);
    final one = MailtoLink.tryParse('MAILTO:jane@example.org')!;
    expect(emails(one.to), ['jane@example.org']);
    expect(one.isEmpty, isFalse);
  });

  test('RFC 6068 examples', () {
    final a = MailtoLink.tryParse('mailto:infobot@example.com?subject=current-issue')!;
    expect(emails(a.to), ['infobot@example.com']);
    expect(a.subject, 'current-issue');

    final b = MailtoLink.tryParse('mailto:list@example.org?In-Reply-To=%3C3469A91.D10AF4C@example.com%3E')!;
    expect(b.inReplyTo, '<3469A91.D10AF4C@example.com>');

    final c = MailtoLink.tryParse('mailto:?to=joe@example.com&cc=bob@example.com&body=hello')!;
    expect(emails(c.to), ['joe@example.com']);
    expect(emails(c.cc), ['bob@example.com']);
    expect(c.body, 'hello');

    final d = MailtoLink.tryParse('mailto:joe@example.com,bob@example.com?to=amy@example.com')!;
    expect(emails(d.to), ['joe@example.com', 'bob@example.com', 'amy@example.com']);

    final e = MailtoLink.tryParse('mailto:%22not%40me%22@example.org')!;
    expect(emails(e.to), ['"not@me"@example.org']);
  });

  test('percent-decoding is UTF-8 and plus stays a plus', () {
    final link = MailtoLink.tryParse(
      'mailto:a+tag@example.org?subject=Caf%C3%A9%20%E2%98%95&body=line%201%0D%0Aline+2',
    )!;
    expect(emails(link.to), ['a+tag@example.org']);
    expect(link.subject, 'Café ☕');
    expect(link.body, 'line 1\nline+2');
  });

  test('display names, semicolons and duplicates', () {
    final link = MailtoLink.tryParse(
      'mailto:Jane%20Doe%20%3Cjane@example.org%3E;bob@example.org?cc=JANE@example.org&bcc=x@example.org&bcc=x@example.org',
    )!;
    expect(link.to.first.name, 'Jane Doe');
    expect(emails(link.to), ['jane@example.org', 'bob@example.org']);
    expect(emails(link.cc), ['JANE@example.org']);
    expect(emails(link.bcc), ['x@example.org']);
  });

  test('tolerates sloppy links', () {
    final link = MailtoLink.tryParse('  mailto://me@example.org?subject=Hello World&body=100%&body=%E9#frag ')!;
    expect(emails(link.to), ['me@example.org']);
    expect(link.subject, 'Hello World');
    expect(link.body, '100%\n�');
  });

  test('subjects are single-line and header names are case-insensitive', () {
    final link = MailtoLink.tryParse('mailto:?SUBJECT=a%0D%0Ab&Body=x')!;
    expect(link.subject, 'a b');
    expect(link.body, 'x');
  });

  test('ignores attach, from and other headers', () {
    final link = MailtoLink.tryParse(
      'mailto:a@example.org?attach=/home/me/.ssh/id_ed25519&from=boss@example.org&X-Evil=1&subject=hi',
    )!;
    expect(emails(link.to), ['a@example.org']);
    expect(link.subject, 'hi');
    expect(link.body, isEmpty);
    expect(link.cc, isEmpty);
  });
}
