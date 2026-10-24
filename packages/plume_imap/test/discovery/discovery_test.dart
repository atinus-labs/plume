import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/discovery/discovery.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/discovery/fixtures/$name').readAsStringSync();

const _exampleConfig = '''
<clientConfig version="1.1">
  <emailProvider id="example.org">
    <domain>example.org</domain>
    <displayName>Example Mail</displayName>
    <incomingServer type="imap">
      <hostname>imap.example.org</hostname><port>993</port><socketType>SSL</socketType>
      <username>%EMAILADDRESS%</username><authentication>password-cleartext</authentication>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>smtp.example.org</hostname><port>587</port><socketType>STARTTLS</socketType>
      <username>%EMAILADDRESS%</username><authentication>password-cleartext</authentication>
    </outgoingServer>
  </emailProvider>
</clientConfig>''';

/// Serves [pages] by URL; everything else is a 404. Records every request.
final class FakeWeb {
  FakeWeb([Map<String, http.Response Function()>? pages]) : pages = pages ?? {};

  final Map<String, http.Response Function()> pages;
  final requested = <Uri>[];

  late final client = MockClient((request) async {
    requested.add(request.url);
    expect(request.url.scheme, 'https');
    final page = pages[request.url.toString()];
    return page == null ? http.Response('<html>404 Not Found</html>', 404) : page();
  });

  void serve(String url, String body) => pages[url] = () => http.Response(body, 200);
}

Future<List<MxRecord>> noMx(String domain) async => const [];
Future<bool> nothingAnswers(ServerEndpoint endpoint, MailProtocol protocol) async => false;

void main() {
  Future<DiscoveredSettings?> discover(
    String email,
    FakeWeb web, {
    MxLookup mx = noMx,
    ServerProbe probe = nothingAnswers,
    Duration timeout = const Duration(seconds: 10),
  }) => discoverSettings(email, client: web.client, mxLookup: mx, probe: probe, timeout: timeout);

  test('built-in providers need no network', () async {
    final web = FakeWeb();
    final found = (await discover('jane@gmail.com', web, mx: (_) => fail('no DNS expected')))!;
    expect(found.source, DiscoverySource.builtIn);
    expect(found.provider!.name, 'Gmail');
    expect(found.settings.imap.host, 'imap.gmail.com');
    expect(found.settings.saveSentCopy, isFalse);
    expect(web.requested, isEmpty);
  });

  test('invalid addresses find nothing', () async {
    expect(await discover('not an address', FakeWeb()), isNull);
    expect(await discover('jane@localhost', FakeWeb()), isNull);
  });

  group("the domain's own autoconfig", () {
    test('autoconfig.<domain>, without the address in the URL', () async {
      final web = FakeWeb()..serve('https://autoconfig.example.org/mail/config-v1.1.xml', _exampleConfig);
      final found = (await discover('jane.doe@example.org', web))!;
      expect(found.source, DiscoverySource.provider);
      expect(found.provider?.name, 'Example Mail');
      expect(
        found.settings.imap,
        const ServerEndpoint(host: 'imap.example.org', port: 993, security: ConnectionSecurity.tls),
      );
      expect(found.settings.smtp.security, ConnectionSecurity.startTls);
      expect(found.settings.username, 'jane.doe@example.org');
      for (final url in web.requested) {
        expect(url.toString(), isNot(contains('jane')));
        expect(url.hasQuery, isFalse);
      }
    });

    test('.well-known when there is no autoconfig host', () async {
      final web = FakeWeb()..serve('https://example.org/.well-known/autoconfig/mail/config-v1.1.xml', _exampleConfig);
      final found = (await discover('jane@example.org', web))!;
      expect(found.source, DiscoverySource.provider);
      expect(web.requested.where((u) => u.host == 'autoconfig.thunderbird.net'), isEmpty);
    });

    test('HTTPS redirects are followed', () async {
      final web = FakeWeb({
        'https://autoconfig.example.org/mail/config-v1.1.xml': () =>
            http.Response('', 301, headers: {'location': 'https://config.example.net/example.xml'}),
      })..serve('https://config.example.net/example.xml', _exampleConfig);
      expect((await discover('jane@example.org', web))!.source, DiscoverySource.provider);
    });

    test('redirects to plain HTTP are not', () async {
      final web = FakeWeb({
        'https://autoconfig.example.org/mail/config-v1.1.xml': () =>
            http.Response('', 302, headers: {'location': 'http://evil.example.net/config.xml'}),
      });
      expect(await discover('jane@example.org', web), isNull);
      expect(web.requested.map((u) => u.scheme).toSet(), {'https'});
    });

    test('broken files and server errors fall through to ISPDB', () async {
      final web = FakeWeb({
        'https://autoconfig.example.org/mail/config-v1.1.xml': () => http.Response('<clientConfig><oops', 200),
        'https://example.org/.well-known/autoconfig/mail/config-v1.1.xml': () => http.Response('', 500),
      })..serve('https://autoconfig.thunderbird.net/v1.1/example.org', _exampleConfig);
      expect((await discover('jane@example.org', web))!.source, DiscoverySource.ispdb);
    });

    test('a network error is just a miss', () async {
      final failing = MockClient((request) async {
        if (request.url.host == 'autoconfig.thunderbird.net') return http.Response(_exampleConfig, 200);
        throw const SocketException('Connection refused');
      });
      final found = await discoverSettings('jane@example.org', client: failing, mxLookup: noMx, probe: nothingAnswers);
      expect(found!.source, DiscoverySource.ispdb);
    });
  });

  group('ISPDB', () {
    test('a real ISPDB file', () async {
      final web = FakeWeb()
        ..serve('https://autoconfig.thunderbird.net/v1.1/posteo.example', fixture('ispdb-posteo.de.xml'));
      final found = (await discover('jane@posteo.example', web))!;
      expect(found.source, DiscoverySource.ispdb);
      expect(found.settings.imap, const ServerEndpoint(host: 'posteo.de', port: 993, security: ConnectionSecurity.tls));
      expect(found.provider?.name, 'Posteo');
    });

    test('OAuth-only providers are reported as unsupported', () async {
      final web = FakeWeb()
        ..serve('https://autoconfig.thunderbird.net/v1.1/hotmail.example', fixture('ispdb-outlook.com.xml'));
      final found = (await discover('jane@hotmail.example', web))!;
      expect(found.provider!.unsupportedReason, contains('Microsoft'));
    });

    test('settings pointing at Gmail get its hints and quirks', () async {
      final web = FakeWeb()
        ..serve('https://autoconfig.thunderbird.net/v1.1/school.example', fixture('ispdb-gmail.com.xml'));
      final found = (await discover('pupil@school.example', web))!;
      expect(found.settings.saveSentCopy, isFalse);
      expect(found.provider!.name, 'Google Workspace');
      expect(found.provider!.needsAppPassword, isTrue);
    });
  });

  group('MX', () {
    test('Google Workspace', () async {
      final found = (await discover(
        'ceo@startup.example',
        FakeWeb(),
        mx: (d) async => [const MxRecord(1, 'aspmx.l.google.com'), const MxRecord(5, 'alt1.aspmx.l.google.com')],
      ))!;
      expect(found.source, DiscoverySource.builtIn);
      expect(found.provider!.name, 'Google Workspace');
      expect(found.settings.imap.host, 'imap.gmail.com');
      expect(found.settings.username, 'ceo@startup.example');
      expect(found.settings.saveSentCopy, isFalse);
    });

    test('Microsoft 365 is unsupported', () async {
      final found = (await discover(
        'ceo@contoso.example',
        FakeWeb(),
        mx: (d) async => [const MxRecord(0, 'contoso-example.mail.protection.outlook.com')],
      ))!;
      expect(found.provider!.unsupportedReason, isNotNull);
    });

    test('the MX host domain is looked up in ISPDB', () async {
      final web = FakeWeb()..serve('https://autoconfig.thunderbird.net/v1.1/hoster.example', _exampleConfig);
      final found = (await discover(
        'jane@small.example',
        web,
        mx: (d) async => [const MxRecord(10, 'mx1.mail.hoster.example')],
      ))!;
      expect(found.source, DiscoverySource.ispdb);
      expect(web.requested.where((u) => u.host == 'autoconfig.thunderbird.net').map((u) => u.path), [
        '/v1.1/small.example',
        '/v1.1/mail.hoster.example',
        '/v1.1/hoster.example',
      ]);
      // The user's own address still fills the placeholders.
      expect(found.settings.username, 'jane@small.example');
    });

    test('DNS failures are a miss', () async {
      final found = await discover('jane@small.example', FakeWeb(), mx: (d) async => throw const SocketException('x'));
      expect(found, isNull);
    });
  });

  group('guessing', () {
    test('picks the best answering servers', () async {
      final answering = {
        'mail.example.org:993',
        'imap.example.org:143',
        'smtp.example.org:587',
        'mail.example.org:587',
      };
      final probed = <String>[];
      final found = (await discover(
        'jane@example.org',
        FakeWeb(),
        probe: (e, p) async {
          probed.add('${p.name} ${e.host}:${e.port}');
          return answering.contains('${e.host}:${e.port}');
        },
      ))!;
      expect(found.source, DiscoverySource.guess);
      expect(found.provider, isNull);
      expect(
        found.settings.imap,
        const ServerEndpoint(host: 'mail.example.org', port: 993, security: ConnectionSecurity.tls),
      );
      expect(
        found.settings.smtp,
        const ServerEndpoint(host: 'smtp.example.org', port: 587, security: ConnectionSecurity.startTls),
      );
      expect(found.settings.username, 'jane@example.org');
      expect(probed, containsAll(['imap imap.example.org:993', 'smtp mail.example.org:465']));
    });

    test('nothing when either side is missing', () async {
      final found = await discover('jane@example.org', FakeWeb(), probe: (e, p) async => p == MailProtocol.imap);
      expect(found, isNull);
    });

    test('a failing probe counts as no answer', () async {
      final found = await discover(
        'jane@example.org',
        FakeWeb(),
        probe: (e, p) async {
          if (e.port == 993) throw const SocketException('boom');
          return true;
        },
      );
      expect(found!.settings.imap.port, 143);
    });
  });

  test('gives up after the timeout', () async {
    final hanging = MockClient((_) => Completer<http.Response>().future);
    final watch = Stopwatch()..start();
    final found = await discoverSettings(
      'jane@example.org',
      client: hanging,
      mxLookup: noMx,
      probe: nothingAnswers,
      timeout: const Duration(milliseconds: 300),
    );
    expect(found, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('registrable domains', () {
    expect(registrableDomain('mx1.mail.example.com'), 'example.com');
    expect(registrableDomain('mx.example.co.uk'), 'example.co.uk');
    expect(registrableDomain('example.com'), 'example.com');
    expect(mxLookupDomains('mx1.mail.example.co.uk'), ['mail.example.co.uk', 'example.co.uk']);
    expect(mxLookupDomains('mx.example.com'), ['example.com']);
  });
}
