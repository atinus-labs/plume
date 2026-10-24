import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/imap/imap_client.dart';
import 'package:plume_imap/src/imap/imap_exception.dart';
import 'package:plume_imap/src/imap/uid_set.dart';
import 'package:test/test.dart';

import '../support/server_connection.dart';
import '../support/tls.dart';

const _caps = 'IMAP4rev1 AUTH=PLAIN SASL-IR ID ENABLE IDLE UIDPLUS MOVE LITERAL+ ESEARCH';

ServerEndpoint _local(int port, [ConnectionSecurity security = ConnectionSecurity.none]) =>
    ServerEndpoint(host: '127.0.0.1', port: port, security: security);

/// Answers the usual setup commands; returns the next other command.
Future<ReceivedCommand?> _serveBasics(ServerConnection c, {String caps = _caps}) async {
  while (true) {
    final cmd = await c.readCommand();
    if (cmd == null) return null;
    switch (cmd.name) {
      case 'CAPABILITY':
        c
          ..send('* CAPABILITY $caps')
          ..send('${cmd.tag} OK done');
      case 'AUTHENTICATE' || 'LOGIN':
        c.send('${cmd.tag} OK [CAPABILITY $caps] Logged in');
      case 'ID':
        c
          ..send('* ID ("name" "Fake")')
          ..send('${cmd.tag} OK');
      case 'LOGOUT':
        c
          ..send('* BYE bye')
          ..send('${cmd.tag} OK');
        return null;
      default:
        return cmd;
    }
  }
}

void main() {
  late ScriptedServer server;

  tearDown(() async => server.close());

  group('login', () {
    test('AUTHENTICATE PLAIN with SASL-IR, then ID; capabilities from the OK code', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        await _serveBasics(c, caps: '$_caps X-GM-EXT-1');
      });
      final client = await ImapClient.connect(_local(server.port));
      expect(client.supports('SASL-IR'), isTrue);
      await client.login('ana@example.org', 'pässword');
      expect(client.isGmail, isTrue, reason: 'post-login capabilities replace pre-login ones');
      final auth = server.connections.single.received.first;
      expect(auth.text, startsWith('AUTHENTICATE PLAIN '));
      final payload = utf8.decode(base64.decode(auth.text.split(' ').last));
      expect(payload, '\u0000ana@example.org\u0000pässword');
      expect(server.connections.single.received.map((c) => c.name), ['AUTHENTICATE', 'ID']);
      await client.logout();
    });

    test('AUTHENTICATE PLAIN without SASL-IR answers the continuation', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK ready');
        final cap = await c.readCommand();
        c
          ..send('* CAPABILITY IMAP4rev1 AUTH=PLAIN')
          ..send('${cap!.tag} OK');
        final auth = await c.readCommand();
        expect(auth!.text, 'AUTHENTICATE PLAIN');
        c.send('+ ');
        final response = await c.readLine();
        expect(utf8.decode(base64.decode(response)), '\u0000u\u0000p');
        c.send('${auth.tag} OK done');
        final cap2 = await c.readCommand();
        c
          ..send('* CAPABILITY IMAP4rev1 IDLE')
          ..send('${cap2!.tag} OK');
      });
      final client = await ImapClient.connect(_local(server.port));
      await client.login('u', 'p');
      expect(client.supports('IDLE'), isTrue);
      client.destroy();
    });

    test('LOGIN with a synchronizing literal for an 8-bit password', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1] ready');
        final login = await c.readCommand();
        expect(login!.text, 'LOGIN "user" {6}');
        expect(utf8.decode(login.literals.single), 'pässw');
        c.send('${login.tag} OK [CAPABILITY IMAP4rev1 MOVE] welcome');
      });
      final client = await ImapClient.connect(_local(server.port));
      await client.login('user', 'pässw');
      expect(client.supports('MOVE'), isTrue);
      client.destroy();
    });

    test('LOGINDISABLED without AUTH=PLAIN refuses to send the password', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 LOGINDISABLED STARTTLS] ready');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      await expectLater(client.login('u', 'p'), throwsA(isA<ImapAuthException>()));
      expect(server.connections.single.received, isEmpty);
      client.destroy();
    });

    test('a NO is an auth error carrying the server text', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 AUTH=PLAIN SASL-IR] ready');
        final auth = await c.readCommand();
        c.send('${auth!.tag} NO [ALERT] Application-specific password required: https://support.google.com (Failure)');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      final error = await client.login('u', 'p').then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<ImapAuthException>());
      expect((error! as ImapAuthException).serverText,
          '[ALERT] Application-specific password required: https://support.google.com (Failure)');
      client.destroy();
    });
  });

  group('commands', () {
    test('pipelined commands get their own untagged responses', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        final a = await c.readCommand();
        final b = await c.readCommand();
        // Server answers in order.
        c
          ..send('* 1 FETCH (UID 10 FLAGS (\\Seen))')
          ..send('${a!.tag} OK')
          ..send('* 2 FETCH (UID 20 FLAGS ())')
          ..send('${b!.tag} OK');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      final results = await Future.wait([client.fetch('10', ['FLAGS']), client.fetch('20', ['FLAGS'])]);
      expect(results[0].messages.single.uid, 10);
      expect(results[1].messages.single.uid, 20);
      client.destroy();
    });

    test('LITERAL+ sends 8-bit search text without waiting', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        final search = await c.readCommand();
        expect(search!.text, 'UID SEARCH RETURN (ALL) CHARSET UTF-8 TEXT {7}');
        expect(utf8.decode(search.literals.single), 'Grüße');
        c
          ..send('* ESEARCH (TAG "${search.tag}") UID ALL 3:5,9')
          ..send('${search.tag} OK');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      const q = 'Grüße';
      final result = await client.search(['TEXT ', ...client.searchString(q)], needsCharset: ImapClient.isNonAscii(q));
      expect(result.ids.toString(), '3:5,9');
      expect(server.connections.single.received.single.literals, hasLength(1));
      client.destroy();
    });

    test('MOVE falls back to COPY, \\Deleted and UID EXPUNGE', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 UIDPLUS] ready');
        final copy = await c.readCommand();
        expect(copy!.text, 'UID COPY 4:5 "Archive"');
        c.send('${copy.tag} OK [COPYUID 77 4:5 100:101] Done');
        final store = await c.readCommand();
        expect(store!.text, r'UID STORE 4:5 +FLAGS.SILENT (\Deleted)');
        c.send('${store.tag} OK');
        final expunge = await c.readCommand();
        expect(expunge!.text, 'UID EXPUNGE 4:5');
        c
          ..send('* 3 EXPUNGE')
          ..send('* 3 EXPUNGE')
          ..send('${expunge.tag} OK');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      final moved = await client.move(UidSet.of([4, 5]), 'Archive');
      expect(moved!.uidValidity, 77);
      expect(moved.mapping, {4: 100, 5: 101});
      client.destroy();
    });

    test('TRYCREATE surfaces as a command error with its code', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        final move = await c.readCommand();
        c.send('${move!.tag} NO [TRYCREATE] Mailbox does not exist');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      await expectLater(
          client.move(UidSet.of([1]), 'Nope'),
          throwsA(isA<ImapCommandException>()
              .having((e) => e.code, 'code', 'TRYCREATE')
              .having((e) => e.command, 'command', 'UID MOVE')));
      client.destroy();
    });

    test('SELECT with QRESYNC reports vanished UIDs and changed flags', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 ENABLE QRESYNC CONDSTORE] ready');
        final enable = await c.readCommand();
        c
          ..send('* ENABLED QRESYNC')
          ..send('${enable!.tag} OK');
        final select = await c.readCommand();
        expect(select!.text, 'SELECT "Archive/2026" (QRESYNC (67890007 20050715194045000 41:211,214:541))');
        c
          ..send('* 314 EXISTS')
          ..send('* OK [UIDVALIDITY 67890007] UIDVALIDITY')
          ..send('* OK [UIDNEXT 567] Predicted next UID')
          ..send('* OK [HIGHESTMODSEQ 90060115205545359] Highest')
          ..send('* VANISHED (EARLIER) 41,43:116,118,120:211,214:540')
          ..send('* 49 FETCH (UID 117 FLAGS (\\Seen \\Answered) MODSEQ (90060115194045001))')
          ..send('${select.tag} OK [READ-WRITE] mailbox selected');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      expect(await client.enable(['QRESYNC', 'UTF8=ACCEPT']), {'QRESYNC'});
      expect(client.condstoreEnabled, isTrue);
      final s = await client.select('Archive/2026',
          qresync: (uidValidity: 67890007, modseq: 20050715194045000, knownUids: UidSet.parse('41:211,214:541')));
      expect((s.exists, s.uidValidity, s.uidNext, s.highestModSeq), (314, 67890007, 567, 90060115205545359));
      expect(s.vanished.toString(), '41,43:116,118,120:211,214:540');
      expect(s.changed.single.uid, 117);
      expect(s.changed.single.flags, {r'\Seen', r'\Answered'});
      client.destroy();
    });

    test('APPEND with flags, date and APPENDUID', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 UIDPLUS] ready');
        final append = await c.readCommand();
        expect(append!.text, r'APPEND "Sent" (\Seen) "01-Mar-2026 09:00:00 +0000" {14}');
        expect(utf8.decode(append.literals.single), 'Subject: x\r\n\r\n');
        c.send('${append.tag} OK [APPENDUID 9 33] appended');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      final uid = await client.append('Sent', utf8.encode('Subject: x\r\n\r\n'),
          flags: [r'\Seen'], date: DateTime.utc(2026, 3, 1, 9));
      expect((uid!.uidValidity, uid.uid), (9, 33));
      client.destroy();
    });

    test('mailbox names are modified UTF-7 on the wire and decoded in LIST', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 SPECIAL-USE LIST-EXTENDED LIST-STATUS] ready');
        final list = await c.readCommand();
        expect(list!.text, 'LIST "" "*" RETURN (SPECIAL-USE STATUS (MESSAGES UIDNEXT))');
        c
          ..send(r'* LIST (\HasNoChildren) "/" Inbox')
          ..send(r'* LIST (\Drafts \HasNoChildren) "/" "Entw&APw-rfe"')
          ..send('* STATUS "Entw&APw-rfe" (MESSAGES 3 UIDNEXT 9)')
          ..send(r'* LIST (\Noselect \HasChildren) "/" {5}')
          ..send('Proj"')
          ..send('${list.tag} OK');
        final select = await c.readCommand();
        expect(select!.text, 'SELECT "Entw&APw-rfe"');
        c.send('${select.tag} OK');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port));
      final boxes = await client.list(statusItems: ['MESSAGES', 'UIDNEXT']);
      expect(boxes.map((b) => b.name), ['INBOX', 'Entwürfe', 'Proj"']);
      expect(boxes[1].has(r'\Drafts'), isTrue);
      expect(boxes[1].status!.messages, 3);
      expect(boxes[2].isSelectable, isFalse);
      await client.select('Entwürfe');
      client.destroy();
    });
  });

  group('failures and timeouts', () {
    test('a silent server times out instead of hanging', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        await c.readCommand(); // never answered
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port),
          config: const ImapClientConfig(responseTimeout: Duration(milliseconds: 300)));
      final watch = Stopwatch()..start();
      await expectLater(client.noop(), throwsA(isA<ImapTimeoutException>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(client.isClosed, isTrue);
    });

    test('a long upload is not mistaken for a silent server', () async {
      final big = Uint8List(24 << 20);
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        // A slow link: nothing read (and nothing said) for longer than the
        // response timeout while the client uploads.
        await c.stall(const Duration(milliseconds: 1200));
        final append = await c.readCommand();
        expect(append!.literals.single.length, big.length);
        c.send('${append.tag} OK [APPENDUID 1 1] done');
        await c.readCommand();
      });
      final client = await ImapClient.connect(_local(server.port),
          config: const ImapClientConfig(responseTimeout: Duration(milliseconds: 400)));
      final uid = await client.append('Sent', big);
      expect(uid!.uid, 1);
      client.destroy();
    });

        test('a server that never greets times out', () async {
      server = await ScriptedServer.start((c) async {
        await c.readCommand();
      });
      await expectLater(
          ImapClient.connect(_local(server.port),
              config: const ImapClientConfig(connectTimeout: Duration(milliseconds: 300))),
          throwsA(isA<ImapTimeoutException>()));
    });

    test('BYE and disconnects fail outstanding commands', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        await c.readCommand();
        c.send('* BYE Server shutting down');
        await c.close();
      });
      final client = await ImapClient.connect(_local(server.port));
      await expectLater(
          client.noop(), throwsA(isA<ImapConnectionException>().having((e) => e.message, 'message', contains('shutting down'))));
      await expectLater(client.noop(), throwsA(isA<ImapConnectionException>()));
    });

    test('plaintext to a remote host is refused before connecting', () async {
      server = await ScriptedServer.start((c) async {});
      await expectLater(
          ImapClient.connect(const ServerEndpoint(host: 'mail.example.com', port: 143, security: ConnectionSecurity.none)),
          throwsA(isA<ImapSecurityException>()));
    });
  });

  group('IDLE', () {
    test('delivers events, sends DONE on stop and re-issues after the restart interval', () async {
      final idles = <String>[];
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps] ready');
        while (true) {
          final cmd = await c.readCommand();
          if (cmd != null && cmd.name == 'SELECT') {
            c
              ..send('* 3 EXISTS')
              ..send('${cmd.tag} OK [READ-WRITE] selected');
            continue;
          }
          if (cmd == null || cmd.name != 'IDLE') return;
          idles.add(cmd.tag);
          c.send('+ idling');
          if (idles.length == 1) {
            c
              ..send('* 4 EXISTS')
              ..send('* 2 EXPUNGE');
          }
          final done = await c.readLine();
          expect(done, 'DONE');
          c.send('${cmd.tag} OK IDLE terminated');
        }
      });
      final client = await ImapClient.connect(_local(server.port),
          config: const ImapClientConfig(responseTimeout: Duration(milliseconds: 200)));
      final selected = await client.select('INBOX');
      expect(selected.exists, 3);
      final events = <ImapEvent>[];
      final sub = client.events.listen(events.add);
      // First cycle ends by itself after maxDuration; the server stays
      // silent for longer than the response timeout without tripping it.
      await client.idle(maxDuration: const Duration(milliseconds: 500));
      final stop = Completer<void>();
      final second = client.idle(stop: stop.future, maxDuration: const Duration(minutes: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      stop.complete();
      await second;
      expect(idles, hasLength(2));
      expect(events.map((e) => e.runtimeType), [ImapExistsEvent, ImapExpungeEvent]);
      expect(selected.exists, 3, reason: '4 EXISTS then one EXPUNGE');
      await sub.cancel();
      client.destroy();
    });
  });

  group('TLS', () {
    late Directory dir;
    late TestCertificate cert;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('plume_imap_tls');
      cert = await TestCertificate.generate(dir);
    });

    tearDownAll(() async => dir.delete(recursive: true));

    test('implicit TLS with a trusted certificate', () async {
      server = await ScriptedServer.start((c) async {
        await c.startTls(cert.serverContext());
        c.send('* OK [CAPABILITY $_caps] ready over TLS');
        await _serveBasics(c);
      });
      final client = await ImapClient.connect(_local(server.port, ConnectionSecurity.tls),
          config: ImapClientConfig(securityContext: cert.clientContext()));
      await client.login('u', 'p');
      await client.logout();
    });

    test('STARTTLS upgrades, then capabilities are re-read', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED] ready');
        final starttls = await c.readCommand();
        expect(starttls!.name, 'STARTTLS');
        c.send('${starttls.tag} OK Begin TLS negotiation now');
        await c.startTls(cert.serverContext());
        await _serveBasics(c);
      });
      final client = await ImapClient.connect(_local(server.port, ConnectionSecurity.startTls),
          config: ImapClientConfig(securityContext: cert.clientContext()));
      expect(client.supports('LOGINDISABLED'), isFalse);
      expect(client.supports('AUTH=PLAIN'), isTrue);
      await client.login('u', 'p');
      await client.logout();
    });

    test('STARTTLS required but not offered fails hard', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY IMAP4rev1 AUTH=PLAIN] ready');
        await c.readCommand();
      });
      await expectLater(
          ImapClient.connect(_local(server.port, ConnectionSecurity.startTls)),
          throwsA(isA<ImapSecurityException>().having((e) => e.startTlsUnavailable, 'startTlsUnavailable', isTrue)));
      expect(server.connections.single.received, isEmpty, reason: 'nothing sent in the clear');
    });

    test('checkImapLogin classifies untrusted certificates, auth failures and unreachable hosts', () async {
      server = await ScriptedServer.start((c) async {
        await c.startTls(cert.serverContext());
        c.send('* OK [CAPABILITY IMAP4rev1 AUTH=PLAIN SASL-IR X-GM-EXT-1] ready');
        final auth = await c.readCommand();
        if (auth == null) return;
        c.send('${auth.tag} NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)');
        await c.readCommand();
      });
      // System trust store: the self-signed certificate must be rejected.
      final untrusted = await checkImapLogin(_local(server.port, ConnectionSecurity.tls), 'u', 'p')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(untrusted, isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.certificate));

      final denied = await checkImapLogin(_local(server.port, ConnectionSecurity.tls), 'u', 'p',
              securityContext: cert.clientContext())
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(
          denied,
          isA<ConnectionCheckException>()
              .having((e) => e.failure, 'failure', ConnectionFailure.authFailed)
              .having((e) => e.serverMessage, 'serverMessage', '[AUTHENTICATIONFAILED] Invalid credentials (Failure)')
              .having((e) => e.protocol, 'protocol', MailProtocol.imap));

      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final refused = await checkImapLogin(_local(port), 'u', 'p').then<Object?>((_) => null, onError: (Object e) => e);
      expect(refused, isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.unreachable));

      final unknown = await checkImapLogin(
              const ServerEndpoint(host: 'no-such-host.invalid', port: 993, security: ConnectionSecurity.tls), 'u', 'p')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(unknown, isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.hostNotFound));
    });

    test('checkImapLogin: TLS on a plaintext port, wrong protocol, and success', () async {
      server = await ScriptedServer.start((c) async {
        c.send('* OK [CAPABILITY $_caps X-GM-EXT-1] plaintext only');
        await _serveBasics(c, caps: '$_caps X-GM-EXT-1');
      });
      final wrongMode = await checkImapLogin(_local(server.port, ConnectionSecurity.tls), 'u', 'p',
              timeout: const Duration(seconds: 2), securityContext: cert.clientContext())
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(wrongMode, isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.tls));

      final info = await checkImapLogin(_local(server.port), 'u', 'p');
      expect(info.isGmail, isTrue);
      expect(info.capabilities, contains('IDLE'));

      final http = await ScriptedServer.start((c) async {
        c.send('HTTP/1.1 400 Bad Request');
        await c.readCommand();
      });
      final notImap = await checkImapLogin(_local(http.port), 'u', 'p').then<Object?>((_) => null, onError: (Object e) => e);
      await http.close();
      expect(notImap, isA<ConnectionCheckException>().having((e) => e.failure, 'failure', ConnectionFailure.protocol));
    });
  });
}
