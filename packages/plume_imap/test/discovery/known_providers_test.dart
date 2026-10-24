import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/discovery/email_address.dart';
import 'package:plume_imap/src/discovery/known_providers.dart';
import 'package:test/test.dart';

void main() {
  group('providerInfoFor', () {
    test('Gmail needs an app password', () {
      final info = providerInfoFor('jane@gmail.com')!;
      expect(info.name, 'Gmail');
      expect(info.needsAppPassword, isTrue);
      expect(info.appPasswordHelp, Uri.parse('https://myaccount.google.com/apppasswords'));
      expect(info.unsupportedReason, isNull);
      expect(info.note, contains('2-Step Verification'));
    });

    test('is forgiving about case and spaces', () {
      expect(providerInfoFor('  Jane.Doe@GoogleMail.COM ')?.name, 'Gmail');
    });

    test('Outlook.com and friends cannot use passwords', () {
      for (final email in ['a@outlook.com', 'a@hotmail.co.uk', 'a@live.com', 'a@msn.com']) {
        expect(providerInfoFor(email)?.unsupportedReason, contains('Microsoft'), reason: email);
      }
    });

    test('incomplete or unknown addresses give nothing', () {
      for (final email in ['', 'jane', 'jane@', 'jane@gmai', 'jane@gmail', '@gmail.com', 'jane@example.org']) {
        expect(providerInfoFor(email), isNull, reason: email);
      }
    });

    test('Proton explains Bridge', () {
      final info = providerInfoFor('me@proton.me')!;
      expect(info.note, contains('Bridge'));
      expect(info.unsupportedReason, isNull);
    });
  });

  group('built-in settings', () {
    MailServerSettings settings(String email) =>
        knownProviderForDomain(EmailAddress.tryParse(email)!.domain)!.settingsFor(EmailAddress.tryParse(email)!);

    test('Gmail', () {
      final s = settings('jane@gmail.com');
      expect(s.imap, const ServerEndpoint(host: 'imap.gmail.com', port: 993, security: ConnectionSecurity.tls));
      expect(s.smtp, const ServerEndpoint(host: 'smtp.gmail.com', port: 465, security: ConnectionSecurity.tls));
      expect(s.username, 'jane@gmail.com');
      expect(s.saveSentCopy, isFalse);
    });

    test('iCloud signs in to IMAP with the name only and to SMTP with the address', () {
      final s = settings('john.appleseed@me.com');
      expect(s.imap.host, 'imap.mail.me.com');
      expect(s.smtp, const ServerEndpoint(host: 'smtp.mail.me.com', port: 587, security: ConnectionSecurity.startTls));
      expect(s.username, 'john.appleseed');
      expect(s.smtpUsername, 'john.appleseed@me.com');
      expect(s.saveSentCopy, isTrue);
    });

    test('Proton goes through the local Bridge', () {
      final s = settings('me@pm.me');
      expect(s.imap, const ServerEndpoint(host: '127.0.0.1', port: 1143, security: ConnectionSecurity.none));
      expect(s.smtp, const ServerEndpoint(host: '127.0.0.1', port: 1025, security: ConnectionSecurity.none));
    });

    test('GMX international and German use different hosts', () {
      expect(settings('a@gmx.de').imap.host, 'imap.gmx.net');
      expect(settings('a@gmx.com').imap.host, 'imap.gmx.com');
    });

    test('every entry is sane', () {
      final seen = <String>{};
      for (final p in knownProviders) {
        for (final e in [p.imap, p.smtp]) {
          expect(e.security != ConnectionSecurity.none || e.isLocal, isTrue, reason: '${p.info.name} $e');
          expect(e.port, inInclusiveRange(1, 65535));
        }
        for (final d in p.domains) {
          expect(seen.add(d), isTrue, reason: 'duplicate domain $d');
          expect(EmailAddress.tryParse('x@$d')?.domain, d);
        }
        expect(p.domains.isNotEmpty || p.mxSuffixes.isNotEmpty, isTrue, reason: p.info.name);
      }
    });
  });

  group('MX matching', () {
    test('custom domains at known hosts', () {
      expect(knownProviderForMx('aspmx.l.google.com')?.info.name, 'Google Workspace');
      expect(knownProviderForMx('smtp.google.com')?.info.name, 'Google Workspace');
      expect(knownProviderForMx('alt1.aspmx.l.google.com')?.imap.host, 'imap.gmail.com');
      expect(knownProviderForMx('contoso-com.mail.protection.outlook.com')?.info.unsupportedReason, isNotNull);
      expect(knownProviderForMx('in1-smtp.messagingengine.com')?.info.name, 'Fastmail');
      expect(knownProviderForMx('mx01.mail.icloud.com')?.info.name, 'iCloud Mail');
      expect(knownProviderForMx('mail.protonmail.ch')?.info.name, 'Proton Mail');
      expect(knownProviderForMx('mx.zoho.eu')?.imap.host, 'imappro.zoho.eu');
      expect(knownProviderForMx('MX2.ZOHO.COM')?.imap.host, 'imappro.zoho.com');
    });

    test('suffixes match whole labels only', () {
      expect(knownProviderForMx('mx.notgoogle.com'), isNull);
      expect(knownProviderForMx('mx.example.org'), isNull);
    });
  });
}
