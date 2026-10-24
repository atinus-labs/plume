@Tags(['live'])
library;

import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/discovery/dns.dart';
import 'package:plume_imap/src/discovery/probe.dart';
import 'package:test/test.dart';

/// Against the real network: the system resolver, Mozilla's ISPDB and real
/// mail servers. No sign-in is attempted. Run with
/// `dart test --run-skipped -t live`.
void main() {
  test('MX lookup through the system resolver', () async {
    final records = await DnsClient().lookupMx('gmail.com');
    expect(records, isNotEmpty);
    expect(records.first.host, endsWith('google.com'));
    expect(await DnsClient().lookupMx('does-not-exist.invalid'), isEmpty);
  });

  test('a Google Workspace domain resolves to Gmail servers', () async {
    final found = (await discoverSettings('nobody@google.com'))!;
    expect(found.settings.imap.host, 'imap.gmail.com');
    expect(found.settings.saveSentCopy, isFalse);
  });

  test('a domain known only to ISPDB', () async {
    final found = (await discoverSettings('nobody@freenet.de'))!;
    expect(found.source, anyOf(DiscoverySource.provider, DiscoverySource.ispdb));
    expect(found.settings.imap.security, isNot(ConnectionSecurity.none));
  });

  test('greeting probes', () async {
    const imap = ServerEndpoint(host: 'imap.gmail.com', port: 993, security: ConnectionSecurity.tls);
    const smtp = ServerEndpoint(host: 'smtp.gmail.com', port: 587, security: ConnectionSecurity.startTls);
    expect(await probeGreeting(imap, MailProtocol.imap), isTrue);
    expect(await probeGreeting(smtp, MailProtocol.smtp), isTrue);
    // Right server, wrong protocol.
    expect(await probeGreeting(imap, MailProtocol.smtp), isFalse);
  });
}
