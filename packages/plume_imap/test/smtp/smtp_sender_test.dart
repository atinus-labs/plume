import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/smtp/smtp_exception.dart';
import 'package:test/test.dart';

import 'fake_smtp_server.dart';

const _gmail534 = [
  '534-5.7.9 Application-specific password required. Learn more at',
  '534 5.7.9  https://support.google.com/mail/?p=InvalidSecondFactor d2e1a72fcca58-7f0a0c32f4bsm12345b3a.12 - gsmtp',
];

Uint8List _message([String body = 'Hello.']) =>
    Uint8List.fromList(utf8.encode('From: user@fake.test\r\nTo: friend@example.org\r\nSubject: Test\r\n\r\n$body\r\n'));

void main() {
  late FakeSmtpServer server;
  final trust = TestCerts.trusting();
  final sender = SmtpMailSender(config: SmtpConfig(securityContext: trust));

  ServerEndpoint endpoint(ConnectionSecurity security, {String host = '127.0.0.1'}) =>
      ServerEndpoint(host: host, port: server.port, security: security);

  Future<void> send(
    ConnectionSecurity security, {
    SmtpMailSender? using,
    String password = 'secret',
    String from = 'user@fake.test',
    List<String> recipients = const ['friend@example.org'],
    Uint8List? data,
  }) => (using ?? sender).send(
    endpoint: endpoint(security),
    username: 'user@fake.test',
    password: password,
    from: from,
    recipients: recipients,
    data: data ?? _message(),
  );

  Future<FakeSmtpServer> startServer({bool implicitTls = false, SecurityContext? tls}) async {
    server = FakeSmtpServer(implicitTls: implicitTls, tls: tls);
    await server.start();
    addTearDown(server.close);
    return server;
  }

  group('happy path', () {
    test('local plain connection (bridge style)', () async {
      await startServer();
      await send(ConnectionSecurity.none);
      final s = server.last;
      expect(s.commands.first, 'EHLO [127.0.0.1]');
      expect(s.logins, [('PLAIN', 'user@fake.test', 'secret')]);
      expect(s.mailFrom, startsWith('MAIL FROM:<user@fake.test> SIZE='));
      expect(s.recipients, ['friend@example.org']);
      expect(utf8.decode(s.messages.single), utf8.decode(_message()));
      expect(s.quit, isTrue);
    });

    test('implicit TLS', () async {
      await startServer(implicitTls: true);
      await send(ConnectionSecurity.tls);
      expect(server.last.secured, isTrue);
      expect(server.last.messages, hasLength(1));
      expect(server.last.quit, isTrue);
    });

    test('STARTTLS upgrades, then says EHLO again before signing in', () async {
      await startServer();
      server.offerStartTls = true;
      await send(ConnectionSecurity.startTls);
      final verbs = server.last.commands.map((c) => c.split(' ').first).toList();
      expect(verbs, ['EHLO', 'STARTTLS', 'EHLO', 'AUTH', 'MAIL', 'RCPT', 'DATA', 'QUIT']);
      expect(server.last.secured, isTrue);
      expect(server.last.messages, hasLength(1));
    });

    test('multi-line greeting and replies', () async {
      await startServer();
      server
        ..greeting = ['220-smtp.fake.test ESMTP', '220-No UCE', '220 ready']
        ..dataReply = ['250-2.0.0 Queued', '250 2.0.0 as 4711'];
      await send(ConnectionSecurity.none);
      expect(server.last.messages, hasLength(1));
    });

    test('one envelope for all recipients, duplicates removed', () async {
      await startServer();
      await send(ConnectionSecurity.none, recipients: ['a@example.org', 'b@example.org', 'A@example.org']);
      expect(server.sessions, hasLength(1));
      expect(server.last.recipients, ['a@example.org', 'b@example.org']);
      expect(server.last.messages, hasLength(1));
    });
  });

  group('security', () {
    test('STARTTLS required but not offered: fails before any password is sent', () async {
      await startServer();
      await expectLater(send(ConnectionSecurity.startTls), throwsA(isA<TransientException>()));
      expect(server.last.commands, ['EHLO [127.0.0.1]']);
      expect(server.last.logins, isEmpty);
    });

    test('plain text injected after STARTTLS is detected', () async {
      await startServer();
      server
        ..offerStartTls = true
        ..injectAfterStartTls = '250 AUTH PLAIN';
      final error = await _error(send(ConnectionSecurity.startTls));
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.protocol);
      expect(server.last.logins, isEmpty);
    });

    test('no encryption is refused for remote hosts without connecting', () async {
      final error = await _error(
        sender.send(
          endpoint: const ServerEndpoint(host: 'smtp.example.org', port: 25, security: ConnectionSecurity.none),
          username: 'u',
          password: 'p',
          from: 'u@example.org',
          recipients: const ['x@example.org'],
          data: _message(),
        ),
      );
      expect(error, isA<PermanentException>());
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.insecure);
    });

    test('an untrusted certificate is rejected', () async {
      await startServer(implicitTls: true);
      final error = await _error(send(ConnectionSecurity.tls, using: const SmtpMailSender()));
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.certificate);
      expect(error, isA<TransientException>());
    });
  });

  group('authentication', () {
    test('falls back to LOGIN when only LOGIN is offered', () async {
      await startServer();
      server.extensions = ['AUTH LOGIN'];
      await send(ConnectionSecurity.none);
      expect(server.last.logins, [('LOGIN', 'user@fake.test', 'secret')]);
      expect(server.last.messages, hasLength(1));
    });

    test('falls back to LOGIN when PLAIN is advertised but refused', () async {
      await startServer();
      server.refuseMechanisms = {'PLAIN'};
      await send(ConnectionSecurity.none);
      expect(server.last.commands.where((c) => c.startsWith('AUTH')).map((c) => c.split(' ').take(2).join(' ')), [
        'AUTH PLAIN',
        'AUTH LOGIN',
      ]);
      expect(server.last.logins, [('LOGIN', 'user@fake.test', 'secret')]);
    });

    test('understands the old AUTH= syntax', () async {
      await startServer();
      server.extensions = ['AUTH=LOGIN'];
      await send(ConnectionSecurity.none);
      expect(server.last.logins.single.$1, 'LOGIN');
    });

    test("Gmail's app password refusal becomes an AuthException with the server's text", () async {
      await startServer();
      server.authFailure = _gmail534;
      final error = await _error(send(ConnectionSecurity.none, password: 'my normal password'));
      expect(error, isA<AuthException>());
      expect((error as AuthException).message, contains('Application-specific password required'));
      expect(error.message, contains('https://support.google.com/mail/?p=InvalidSecondFactor'));
      expect(server.last.mailFrom, isNull);
    });

    test('wrong password', () async {
      await startServer();
      expect(send(ConnectionSecurity.none, password: 'nope'), throwsA(isA<AuthException>()));
    });

    test('temporary authentication failure is transient', () async {
      await startServer();
      server.authFailure = ['454 4.7.0 Too many login attempts, please try again later.'];
      expect(send(ConnectionSecurity.none, password: 'nope'), throwsA(isA<TransientException>()));
    });

    test('no AUTH offered at all', () async {
      await startServer();
      server.extensions = ['SIZE 1000'];
      final error = await _error(send(ConnectionSecurity.none));
      expect(error, isA<PermanentException>());
      expect((error as MailException).message, contains('does not accept a sign-in'));
    });

    test('HELO fallback when EHLO is refused', () async {
      await startServer();
      server.refuseEhlo = true;
      final error = await _error(send(ConnectionSecurity.none));
      expect(server.last.commands, ['EHLO [127.0.0.1]', 'HELO localhost']);
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.authUnavailable);
    });
  });

  group('envelope and data', () {
    test('a refused recipient: RSET, nothing sent, address named', () async {
      await startServer();
      server.rcptReply = (a) => a == 'gone@example.org'
          ? ['550-5.1.1 The email account that you tried to reach does not exist.', '550 5.1.1 Please check it.']
          : ['250 2.1.5 OK'];
      final error = await _error(send(ConnectionSecurity.none, recipients: ['ok@example.org', 'gone@example.org']));
      expect(error, isA<PermanentException>());
      expect((error as MailException).message, contains('gone@example.org'));
      expect(error.message, contains('does not exist'));
      expect(server.last.resets, 1);
      expect(server.last.commands.where((c) => c == 'DATA'), isEmpty);
      expect(server.last.messages, isEmpty);
    });

    test('several refusals are all named; any permanent one makes it permanent', () async {
      await startServer();
      server.rcptReply = (a) => switch (a) {
        'busy@example.org' => ['450 4.2.1 Mailbox busy'],
        'gone@example.org' => ['550 5.1.1 No such user'],
        _ => ['250 OK'],
      };
      final error = await _error(
        send(ConnectionSecurity.none, recipients: ['busy@example.org', 'ok@example.org', 'gone@example.org']),
      );
      expect(error, isA<PermanentException>());
      final smtp = (error as MailException).cause! as SmtpException;
      expect(smtp.recipients, ['busy@example.org', 'gone@example.org']);
      expect(server.last.messages, isEmpty);
    });

    test('only temporary refusals are transient', () async {
      await startServer();
      server.rcptReply = (_) => ['450 4.2.1 Mailbox busy'];
      expect(send(ConnectionSecurity.none), throwsA(isA<TransientException>()));
    });

    test('dot-stuffing and line endings survive the trip', () async {
      await startServer();
      const body = '.\n..leading dots\r\n.\rmid.dle\n.';
      await send(ConnectionSecurity.none, data: _message(body));
      final wire = latin1.decode(server.last.messages.single);
      expect(wire, contains('\r\n..\r\n...leading dots\r\n..\r\nmid.dle\r\n..\r\n'));
      expect(wire.contains(RegExp('[^\r]\n')), isFalse);
      // What the server stores after removing the stuffing.
      final unstuffed = wire.replaceAll('\r\n..', '\r\n.');
      expect(unstuffed, endsWith('\r\n\r\n.\r\n..leading dots\r\n.\r\nmid.dle\r\n.\r\n'));
    });

    test('8-bit body is announced as 8BITMIME, UTF-8 addresses use SMTPUTF8', () async {
      await startServer();
      await send(ConnectionSecurity.none, data: _message('Grüße'), recipients: ['jürgen@example.org']);
      expect(server.last.mailFrom, contains('BODY=8BITMIME'));
      expect(server.last.mailFrom, contains('SMTPUTF8'));
      expect(server.last.recipients, ['jürgen@example.org']);
    });

    test('UTF-8 addresses without SMTPUTF8 fail permanently', () async {
      await startServer();
      server.extensions = ['AUTH PLAIN'];
      expect(send(ConnectionSecurity.none, recipients: ['jürgen@example.org']), throwsA(isA<PermanentException>()));
    });

    test('SIZE limit is checked before sending', () async {
      await startServer();
      server.extensions = ['SIZE 100', 'AUTH PLAIN'];
      final error = await _error(send(ConnectionSecurity.none, data: _message('x' * 200)));
      expect(error, isA<PermanentException>());
      expect((error as MailException).message, contains('MB'));
      expect(server.last.mailFrom, isNull);
    });

    test('addresses cannot smuggle commands', () async {
      await startServer();
      final error = await _error(send(ConnectionSecurity.none, recipients: ['a@example.org>\r\nRCPT TO:<evil@x.org']));
      expect(error, isA<PermanentException>());
      expect(server.sessions, isEmpty);
    });

    test('message refused after DATA: 5xx permanent, 4xx transient', () async {
      await startServer();
      server.dataReply = ['554 5.7.1 Message rejected as spam'];
      await expectLater(send(ConnectionSecurity.none), throwsA(isA<PermanentException>()));
      server.dataReply = ['451 4.3.0 Try again later'];
      await expectLater(send(ConnectionSecurity.none), throwsA(isA<TransientException>()));
    });

    test('sender refused', () async {
      await startServer();
      server.mailReply = (_) => ['553 5.7.1 Sender address rejected: not owned by user user@fake.test'];
      final error = await _error(send(ConnectionSecurity.none, from: 'someone-else@example.org'));
      expect(error, isA<PermanentException>());
      expect((error as MailException).message, contains('someone-else@example.org'));
      expect(error.message, contains('not owned by user'));
      expect(server.last.recipients, isEmpty);
    });
  });

  group('failures in transit', () {
    const quick = SmtpConfig(replyTimeout: Duration(milliseconds: 300), connectTimeout: Duration(seconds: 2));

    test('a server that stops answering times out', () async {
      await startServer();
      server.stallOn = 'EHLO';
      final error = await _error(send(ConnectionSecurity.none, using: const SmtpMailSender(config: quick)));
      expect(error, isA<TransientException>());
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.timeout);
    });

    test('connection dropped during DATA is transient', () async {
      await startServer();
      server.dropDuringData = true;
      final error = await _error(send(ConnectionSecurity.none, data: _message('x' * 200000)));
      expect(error, isA<TransientException>());
      expect((error as MailException).message, contains('interrupted while sending'));
    });

    test('nobody listening', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final error = await _error(
        sender.send(
          endpoint: ServerEndpoint(host: '127.0.0.1', port: port, security: ConnectionSecurity.none),
          username: 'u',
          password: 'p',
          from: 'u@fake.test',
          recipients: const ['x@example.org'],
          data: _message(),
        ),
      );
      expect(error, isA<TransientException>());
      expect(((error as MailException).cause! as SmtpException).kind, SmtpErrorKind.unreachable);
    });
  });
}

/// The error [future] fails with, or null when it succeeds.
Future<Object?> _error(Future<void> future) async {
  try {
    await future;
    return null;
  } on Object catch (e) {
    return e;
  }
}
