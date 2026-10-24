import 'dart:io';

import 'package:plume_imap/plume_imap.dart';
import 'package:test/test.dart';

import 'fake_smtp_server.dart';

void main() {
  late FakeSmtpServer server;
  final trust = TestCerts.trusting();

  Future<void> start({bool implicitTls = false, bool elsewhere = false}) async {
    server = FakeSmtpServer(
      implicitTls: implicitTls,
      tls: TestCerts.server(elsewhere: elsewhere),
    );
    await server.start();
    addTearDown(server.close);
  }

  Future<void> check(
    ConnectionSecurity security, {
    String password = 'secret',
    bool systemTrust = false,
    Duration timeout = const Duration(seconds: 5),
    int? port,
  }) => checkSmtpLogin(
    ServerEndpoint(host: '127.0.0.1', port: port ?? server.port, security: security),
    'user@fake.test',
    password,
    timeout: timeout,
    securityContext: systemTrust ? null : trust,
  );

  Matcher fails(ConnectionFailure failure, {Object? serverMessage}) => throwsA(
    isA<ConnectionCheckException>()
        .having((e) => e.failure, 'failure', failure)
        .having((e) => e.protocol, 'protocol', MailProtocol.smtp)
        .having((e) => e.host, 'host', '127.0.0.1')
        .having((e) => e.serverMessage, 'serverMessage', serverMessage ?? anything),
  );

  test('STARTTLS login succeeds and quits', () async {
    await start();
    server.offerStartTls = true;
    await check(ConnectionSecurity.startTls);
    expect(server.last.logins.single, ('PLAIN', 'user@fake.test', 'secret'));
    expect(server.last.quit, isTrue);
    expect(server.last.commands.where((c) => c.startsWith('MAIL')), isEmpty);
  });

  test('implicit TLS login succeeds', () async {
    await start(implicitTls: true);
    await check(ConnectionSecurity.tls);
    expect(server.last.quit, isTrue);
  });

  test("Gmail's 534: authFailed with the server's explanation", () async {
    await start(implicitTls: true);
    server.authFailure = [
      '534-5.7.9 Application-specific password required. Learn more at',
      '534 5.7.9  https://support.google.com/mail/?p=InvalidSecondFactor x - gsmtp',
    ];
    await expectLater(
      check(ConnectionSecurity.tls, password: 'normal password'),
      fails(ConnectionFailure.authFailed, serverMessage: startsWith('Application-specific password required.')),
    );
  });

  test('wrong password', () async {
    await start(implicitTls: true);
    await expectLater(
      check(ConnectionSecurity.tls, password: 'wrong'),
      fails(ConnectionFailure.authFailed, serverMessage: 'Authentication credentials invalid'),
    );
  });

  test('STARTTLS not offered', () async {
    await start();
    await expectLater(check(ConnectionSecurity.startTls), fails(ConnectionFailure.startTlsUnavailable));
  });

  test('certificate for another host name', () async {
    await start(implicitTls: true, elsewhere: true);
    await expectLater(check(ConnectionSecurity.tls), fails(ConnectionFailure.certificate));
  });

  test('self-signed certificate is not trusted by the system', () async {
    await start(implicitTls: true);
    await expectLater(check(ConnectionSecurity.tls, systemTrust: true), fails(ConnectionFailure.certificate));
  });

  test('certificate problems after STARTTLS too', () async {
    await start(elsewhere: true);
    server.offerStartTls = true;
    await expectLater(check(ConnectionSecurity.startTls), fails(ConnectionFailure.certificate));
    expect(server.last.logins, isEmpty);
  });

  test('SSL/TLS against a plain port is a TLS failure', () async {
    await start();
    await expectLater(check(ConnectionSecurity.tls), fails(ConnectionFailure.tls));
  });

  test('STARTTLS against an SSL/TLS port times out waiting for the greeting', () async {
    await start(implicitTls: true);
    await expectLater(
      check(ConnectionSecurity.startTls, timeout: const Duration(milliseconds: 500)),
      fails(ConnectionFailure.timeout),
    );
  });

  test('an IMAP server on the port', () async {
    await start();
    server.greeting = ['* OK [CAPABILITY IMAP4rev1 STARTTLS] Dovecot ready.'];
    await expectLater(
      check(ConnectionSecurity.none),
      fails(ConnectionFailure.protocol, serverMessage: startsWith('* OK')),
    );
  });

  test('a silent server times out within the limit', () async {
    await start();
    server.silent = true;
    final watch = Stopwatch()..start();
    await expectLater(
      check(ConnectionSecurity.none, timeout: const Duration(milliseconds: 400)),
      fails(ConnectionFailure.timeout),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('connection refused', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    await expectLater(check(ConnectionSecurity.tls, port: port), fails(ConnectionFailure.unreachable));
  });

  test('no encryption to a remote host is refused up front', () async {
    await expectLater(
      checkSmtpLogin(
        const ServerEndpoint(host: 'smtp.example.org', port: 25, security: ConnectionSecurity.none),
        'u',
        'p',
      ),
      throwsA(isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.tls)),
    );
  });

  test('server greeting refusal is reported with its text', () async {
    await start();
    server.greeting = ['554 5.7.1 Your IP is on a blocklist'];
    await expectLater(
      check(ConnectionSecurity.none),
      fails(ConnectionFailure.protocol, serverMessage: 'Your IP is on a blocklist'),
    );
  });
}
