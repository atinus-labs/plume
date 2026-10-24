import 'dart:io';

import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/discovery/autoconfig.dart';
import 'package:plume_imap/src/discovery/email_address.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/discovery/fixtures/$name').readAsStringSync();

EmailAddress email(String s) => EmailAddress.tryParse(s)!;

/// A minimal autoconfig file with the given server elements.
String config(String servers, {String? name = 'Example Mail'}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<clientConfig version="1.1">
  <emailProvider id="example.org">
    <domain>example.org</domain>
    ${name == null ? '' : '<displayName>$name</displayName>'}
    $servers
  </emailProvider>
</clientConfig>''';

String server(
  String kind,
  String type,
  String host,
  int port,
  String socket, {
  String username = '%EMAILADDRESS%',
  List<String> auth = const ['password-cleartext'],
}) =>
    '''
<$kind type="$type">
  <hostname>$host</hostname><port>$port</port><socketType>$socket</socketType>
  <username>$username</username>
  ${auth.map((a) => '<authentication>$a</authentication>').join()}
</$kind>''';

String imap(String host, int port, String socket, {String username = '%EMAILADDRESS%', List<String>? auth}) => server(
  'incomingServer',
  'imap',
  host,
  port,
  socket,
  username: username,
  auth: auth ?? const ['password-cleartext'],
);

String smtp(String host, int port, String socket, {String username = '%EMAILADDRESS%', List<String>? auth}) => server(
  'outgoingServer',
  'smtp',
  host,
  port,
  socket,
  username: username,
  auth: auth ?? const ['password-cleartext'],
);

void main() {
  group('real ISPDB files', () {
    test('gmail.com', () {
      final r = parseAutoconfig(fixture('ispdb-gmail.com.xml'), email('jane@gmail.com'))!;
      expect(
        r.settings.imap,
        const ServerEndpoint(host: 'imap.gmail.com', port: 993, security: ConnectionSecurity.tls),
      );
      expect(
        r.settings.smtp,
        const ServerEndpoint(host: 'smtp.gmail.com', port: 465, security: ConnectionSecurity.tls),
      );
      expect(r.settings.username, 'jane@gmail.com');
      expect(r.settings.smtpUsername, 'jane@gmail.com');
      expect(r.displayName, 'Google Mail');
      expect(r.oauthOnly, isFalse);
    });

    test('posteo.de prefers SSL over STARTTLS', () {
      final r = parseAutoconfig(fixture('ispdb-posteo.de.xml'), email('jane@posteo.net'))!;
      expect(r.settings.imap, const ServerEndpoint(host: 'posteo.de', port: 993, security: ConnectionSecurity.tls));
      expect(r.settings.smtp, const ServerEndpoint(host: 'posteo.de', port: 465, security: ConnectionSecurity.tls));
      expect(r.settings.username, 'jane@posteo.net');
    });

    test('gmx.net', () {
      final r = parseAutoconfig(fixture('ispdb-gmx.net.xml'), email('jane@gmx.de'))!;
      expect(r.settings.imap.host, 'imap.gmx.net');
      expect(r.settings.imap.security, ConnectionSecurity.tls);
      expect(r.settings.smtp, const ServerEndpoint(host: 'mail.gmx.net', port: 465, security: ConnectionSecurity.tls));
    });

    test('outlook.com offers only OAuth2', () {
      final r = parseAutoconfig(fixture('ispdb-outlook.com.xml'), email('jane@outlook.com'))!;
      expect(r.oauthOnly, isTrue);
      expect(r.settings.imap.host, 'outlook.office365.com');
      expect(r.settings.smtp.security, ConnectionSecurity.startTls);
    });
  });

  test('placeholders in user names and host names', () {
    final r = parseAutoconfig(
      config(
        imap('imap.%EMAILDOMAIN%', 993, 'SSL', username: '%EMAILLOCALPART%') +
            smtp('smtp.%EMAILDOMAIN%', 587, 'STARTTLS', username: '%EMAILLOCALPART%+smtp@%EMAILDOMAIN%'),
      ),
      email('Jane.Doe@Example.org'),
    )!;
    expect(r.settings.imap.host, 'imap.example.org');
    expect(r.settings.username, 'Jane.Doe');
    expect(
      r.settings.smtp,
      const ServerEndpoint(host: 'smtp.example.org', port: 587, security: ConnectionSecurity.startTls),
    );
    expect(r.settings.smtpUsername, 'Jane.Doe+smtp@example.org');
  });

  test('unknown placeholders fall back to the address', () {
    final r = parseAutoconfig(
      config(imap('imap.example.org', 993, 'SSL', username: '%REALNAME%') + smtp('smtp.example.org', 465, 'SSL')),
      email('jane@example.org'),
    )!;
    expect(r.settings.username, 'jane@example.org');
  });

  test('SSL wins over an earlier STARTTLS entry; document order breaks ties', () {
    final r = parseAutoconfig(
      config(
        imap('a.example.org', 143, 'STARTTLS') +
            imap('b.example.org', 993, 'SSL') +
            imap('c.example.org', 993, 'SSL') +
            smtp('a.example.org', 587, 'STARTTLS'),
      ),
      email('jane@example.org'),
    )!;
    expect(r.settings.imap.host, 'b.example.org');
    expect(r.settings.smtp.security, ConnectionSecurity.startTls);
  });

  test('plain text only for local servers', () {
    final remote = config(imap('imap.example.org', 143, 'plain') + smtp('smtp.example.org', 25, 'plain'));
    expect(parseAutoconfig(remote, email('jane@example.org')), isNull);
    final local = config(imap('127.0.0.1', 1143, 'plain') + smtp('localhost', 1025, 'plain'));
    final r = parseAutoconfig(local, email('jane@example.org'))!;
    expect(r.settings.imap.security, ConnectionSecurity.none);
    expect(r.settings.smtp.host, 'localhost');
  });

  test('a password-capable server is chosen over an OAuth-only one', () {
    final r = parseAutoconfig(
      config(
        imap('oauth.example.org', 993, 'SSL', auth: ['OAuth2']) +
            imap('pw.example.org', 143, 'STARTTLS') +
            smtp('smtp.example.org', 465, 'SSL', auth: ['OAuth2', 'password-cleartext']),
      ),
      email('jane@example.org'),
    )!;
    expect(r.oauthOnly, isFalse);
    expect(r.settings.imap.host, 'pw.example.org');
  });

  test('no <authentication> means password', () {
    final r = parseAutoconfig(
      config(imap('imap.example.org', 993, 'SSL', auth: []) + smtp('smtp.example.org', 465, 'SSL', auth: [])),
      email('jane@example.org'),
    )!;
    expect(r.oauthOnly, isFalse);
  });

  test('unusable files give nothing', () {
    final jane = email('jane@example.org');
    expect(parseAutoconfig('', jane), isNull);
    expect(parseAutoconfig('<html><body><h1>404 Not Found</h1></body></html>', jane), isNull);
    expect(parseAutoconfig('<clientConfig><emailProvider>', jane), isNull);
    expect(parseAutoconfig('<?xml version="1.0"?><other/>', jane), isNull);
    // POP3 only.
    expect(
      parseAutoconfig(
        config(server('incomingServer', 'pop3', 'pop.example.org', 995, 'SSL') + smtp('smtp.example.org', 465, 'SSL')),
        jane,
      ),
      isNull,
    );
    // No SMTP.
    expect(parseAutoconfig(config(imap('imap.example.org', 993, 'SSL')), jane), isNull);
    // NTLM only: neither password nor OAuth.
    expect(
      parseAutoconfig(
        config(imap('imap.example.org', 993, 'SSL', auth: ['NTLM']) + smtp('smtp.example.org', 465, 'SSL')),
        jane,
      ),
      isNull,
    );
    // Garbage values.
    expect(parseAutoconfig(config(imap('bad host', 993, 'SSL') + smtp('smtp.example.org', 465, 'SSL')), jane), isNull);
    expect(
      parseAutoconfig(config(imap('imap.example.org', 99999, 'SSL') + smtp('smtp.example.org', 465, 'SSL')), jane),
      isNull,
    );
    expect(
      parseAutoconfig(config(imap('imap.example.org', 993, 'TLS1.3') + smtp('smtp.example.org', 465, 'SSL')), jane),
      isNull,
    );
  });

  test('a missing display name is fine', () {
    final r = parseAutoconfig(
      config(imap('imap.example.org', 993, 'SSL') + smtp('smtp.example.org', 465, 'SSL'), name: null),
      email('jane@example.org'),
    )!;
    expect(r.displayName, isNull);
  });
}
