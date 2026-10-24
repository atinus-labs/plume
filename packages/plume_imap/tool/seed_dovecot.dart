// Seeds a mailbox on the integration-test Dovecot over IMAP (APPEND).
//
// Usage: dart run tool/seed_dovecot.dart <port> <ca.pem> <user> <password>
//
// Used by tool/integration.sh; the integration tests check the result.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_imap/src/imap/imap_client.dart';
import 'package:plume_imap/src/settings.dart';

/// Messages seeded into INBOX (and one reply into Sent).
const seededInbox = 12;

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln('usage: seed_dovecot.dart <port> <ca.pem> <user> <password>');
    exit(64);
  }
  final port = int.parse(args[0]);
  final context = SecurityContext(withTrustedRoots: false)..setTrustedCertificates(args[1]);
  final client = await ImapClient.connect(
    ServerEndpoint(host: '127.0.0.1', port: port, security: ConnectionSecurity.tls),
    config: ImapClientConfig(securityContext: context),
  );
  await client.login(args[2], args[3]);
  for (var i = 1; i <= seededInbox; i++) {
    await client.append('INBOX', _message(i), date: DateTime.utc(2026, 3, 1, 9).add(Duration(hours: i)));
  }
  await client.append('Sent', _reply(), flags: const [r'\Seen'], date: DateTime.utc(2026, 3, 2));
  await client.logout();
  stdout.writeln('Seeded ${seededInbox + 1} messages for ${args[2]}');
}

Uint8List _message(int i) => _bytes([
      'From: Ben Okafor <ben@example.com>',
      'To: Plume <plume@example.org>',
      'Subject: Seeded message $i',
      'Date: ${_date(i)}',
      'Message-ID: <seed$i@example.com>',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      'This is seeded message number $i. Grüße!',
    ]);

Uint8List _reply() => _bytes([
      'From: Plume <plume@example.org>',
      'To: Ben Okafor <ben@example.com>',
      'Subject: Re: Seeded message 1',
      'Date: Mon, 02 Mar 2026 00:00:00 +0000',
      'Message-ID: <seed-reply@example.org>',
      'In-Reply-To: <seed1@example.com>',
      'References: <seed1@example.com>',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      'Thanks!',
    ]);

String _date(int i) => 'Sun, 01 Mar 2026 ${(9 + i).toString().padLeft(2, '0')}:00:00 +0000';

Uint8List _bytes(List<String> lines) => Uint8List.fromList(utf8.encode('${lines.join('\r\n')}\r\n'));
