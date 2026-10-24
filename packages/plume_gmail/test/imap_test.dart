import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/plume_gmail.dart';
import 'package:plume_gmail/src/imap/imap_reader.dart';
import 'package:test/test.dart';

import 'support/fake_tokens.dart';

/// One client connection on the fake server, line-oriented.
class Conn {
  Conn(this.socket) : lines = StreamQueue(utf8.decoder.bind(socket).transform(const LineSplitter()));

  final Socket socket;
  final StreamQueue<String> lines;
  final received = <String>[];

  Future<String?> next() async {
    if (!await lines.hasNext) return null;
    final line = await lines.next;
    received.add(line);
    return line;
  }

  void send(String line) => socket.add(utf8.encode('$line\r\n'));
}

/// A Gmail-like IMAP server for the doorbell: greeting, XOAUTH2, SELECT,
/// IDLE/DONE and LOGOUT.
class FakeImapServer {
  FakeImapServer({required this.acceptToken});

  bool Function(String token) acceptToken;
  late final ServerSocket _server;
  final connections = <Conn>[];
  final authPayloads = <String>[];
  final _idling = StreamController<Conn>.broadcast();
  bool dropAfterFirstIdle = false;

  /// Emits a connection each time it enters IDLE.
  Stream<Conn> get idling => _idling.stream;

  int get port => _server.port;

  Future<Socket> connect() => Socket.connect(InternetAddress.loopbackIPv4, port);

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((socket) => unawaited(_serve(Conn(socket))));
  }

  Future<void> close() async {
    await _server.close();
    for (final c in connections) {
      c.socket.destroy();
    }
    await _idling.close();
  }

  Future<void> _serve(Conn c) async {
    connections.add(c);
    c.send('* OK Gimap ready for requests from 127.0.0.1 x1mb12345');
    String? idleTag;
    try {
      while (true) {
        final line = await c.next();
        if (line == null) return;
        if (line == 'DONE') {
          c.send('$idleTag OK IDLE terminated (Success)');
          continue;
        }
        final parts = line.split(' ');
        final tag = parts[0];
        switch (parts[1].toUpperCase()) {
          case 'AUTHENTICATE':
            final payload = utf8.decode(base64.decode(parts[3]));
            authPayloads.add(payload);
            final token = RegExp('auth=Bearer ([^\x01]+)').firstMatch(payload)!.group(1)!;
            if (acceptToken(token)) {
              c.send('* CAPABILITY IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1');
              c.send('$tag OK me@example.com authenticated (Success)');
            } else {
              c.send('+ eyJzdGF0dXMiOiI0MDAiLCJzY2hlbWVzIjoiQmVhcmVyIiwic2NvcGUiOiJodHRwczovL21haWwuZ29vZ2xlLmNvbS8ifQ==');
              final empty = await c.next();
              expect(empty, '', reason: 'client must answer the error challenge with an empty line');
              c.send('$tag NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)');
            }
          case 'SELECT':
            c
              ..send(r'* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $NotPhishing $Phishing)')
              ..send('* OK [PERMANENTFLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen \\*)] Flags permitted.')
              ..send('* OK [UIDVALIDITY 3] UIDs valid.')
              ..send('* 3 EXISTS')
              ..send('* 0 RECENT')
              ..send('$tag OK [READ-WRITE] INBOX selected. (Success)');
          case 'IDLE':
            idleTag = tag;
            c.send('+ idling');
            _idling.add(c);
            if (dropAfterFirstIdle && connections.length == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              c.socket.destroy();
              return;
            }
          case 'LOGOUT':
            c
              ..send('* BYE LOGOUT Requested')
              ..send('$tag OK 73 good day (Success)');
            await c.socket.close();
            return;
          default:
            c.send('$tag BAD Unknown command');
        }
      }
    } on Object {
      // Connection torn down by the test.
    }
  }
}

void main() {
  group('ImapResponseReader', () {
    test('splits responses across arbitrary chunk boundaries', () {
      final reader = ImapResponseReader();
      final bytes = utf8.encode('* 4 EXISTS\r\n* 1 EXPUNGE\r\nA1 OK done\r\n');
      final out = <ImapResponse>[];
      for (var i = 0; i < bytes.length; i += 3) {
        out.addAll(reader.add(bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3)));
      }
      expect(out.map((r) => r.text), ['* 4 EXISTS', '* 1 EXPUNGE', 'A1 OK done']);
      expect(out[0].isUntagged, isTrue);
      expect(out[2].tag, 'A1');
      expect(out[2].status, 'OK');
    });

    test('reads literals without interpreting their bytes', () {
      final reader = ImapResponseReader();
      // A literal containing CRLF, a fake tagged line and a brace marker.
      const literal = 'line one\r\nA1 OK not really\r\n{99}\r\n';
      final literalBytes = utf8.encode(literal);
      final data = [
        ...utf8.encode('* 1 FETCH (BODY[HEADER] {${literalBytes.length}}\r\n'),
        ...literalBytes,
        ...utf8.encode(' FLAGS (\\Seen) X {0}\r\n'),
        ...utf8.encode(' Y {3+}\r\nabc)\r\n'),
        ...utf8.encode('A1 OK Success\r\n'),
      ];
      final out = <ImapResponse>[];
      for (final b in data) {
        out.addAll(reader.add([b])); // worst case: one byte at a time
      }
      expect(out, hasLength(2));
      expect(out[0].text, startsWith('* 1 FETCH (BODY[HEADER] {${literalBytes.length}}'));
      expect(out[0].text, endsWith(r' FLAGS (\Seen) X {0} Y {3+})'), reason: 'text continues after each literal');
      expect(out[0].text, isNot(contains('not really')), reason: 'literal bytes are not protocol text');
      expect(out[0].literals.map(utf8.decode).toList(), [literal, '', 'abc']);
      expect(out[1].text, 'A1 OK Success');
    });

    test('bounds literal and line sizes', () {
      expect(() => ImapResponseReader(maxLiteralSize: 10).add(utf8.encode('* 1 FETCH {11}\r\n')),
          throwsA(isA<ImapProtocolException>()));
      expect(() => ImapResponseReader(maxLineLength: 16).add(utf8.encode('* ${'x' * 40}')),
          throwsA(isA<ImapProtocolException>()));
    });
  });

  group('GmailImapDoorbell', () {
    late FakeImapServer server;
    late FakeTokenSource tokens;

    setUp(() async {
      tokens = FakeTokenSource();
      server = FakeImapServer(acceptToken: (_) => true);
      await server.start();
    });

    tearDown(() => server.close());

    GmailImapDoorbell bell({Duration idleRestart = const Duration(minutes: 25)}) => GmailImapDoorbell(
          email: 'me@example.com',
          tokens: tokens,
          connect: server.connect,
          config: ImapDoorbellConfig(
            idleRestart: idleRestart,
            debounce: const Duration(milliseconds: 80),
            commandTimeout: const Duration(seconds: 2),
          ),
          sleep: (_) => Future<void>.delayed(const Duration(milliseconds: 10)),
        );

    test('authenticates with XOAUTH2, IDLEs on INBOX and rings (debounced) on changes', () async {
      final events = <void>[];
      final idle = server.idling.first;
      final sub = bell().watch().listen(events.add);
      final conn = await idle.timeout(const Duration(seconds: 5));

      expect(server.authPayloads.single, 'user=me@example.com\x01auth=Bearer token-1\x01\x01');
      expect(conn.received.where((l) => l.contains('SELECT')).single, endsWith('SELECT "INBOX"'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(events, isEmpty, reason: 'EXISTS during SELECT is not a change');

      conn
        ..send('* 4 EXISTS')
        ..send('* 2 EXPUNGE')
        ..send('* 3 EXISTS');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(events, hasLength(1), reason: 'a burst rings once');

      conn.send(r'* 1 FETCH (FLAGS (\Seen))');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(events, hasLength(2));

      conn.send('* OK still here');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(events, hasLength(2), reason: 'keepalives are not changes');

      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(conn.received, containsAllInOrder(['DONE']));
      expect(conn.received.last, endsWith('LOGOUT'));
    });

    test('restarts IDLE periodically', () async {
      var idles = 0;
      final enough = Completer<void>();
      server.idling.listen((_) {
        if (++idles == 3 && !enough.isCompleted) enough.complete();
      });
      final events = <void>[];
      final sub = bell(idleRestart: const Duration(milliseconds: 150)).watch().listen(events.add);
      await enough.future.timeout(const Duration(seconds: 5));
      final conn = server.connections.single;
      expect(conn.received.where((l) => l == 'DONE').length, greaterThanOrEqualTo(2));
      expect(server.connections, hasLength(1), reason: 'same connection');
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('a rejected token is refreshed once, then sign-in is required', () async {
      server.acceptToken = (token) => token == 'token-2';
      final idle = server.idling.first;
      final sub = bell().watch().listen((_) {});
      await idle.timeout(const Duration(seconds: 5));
      expect(tokens.invalidations, 1);
      expect(server.authPayloads.map((p) => RegExp('Bearer ([^\x01]+)').firstMatch(p)!.group(1)), ['token-1', 'token-2']);
      await sub.cancel();

      server.acceptToken = (_) => false;
      final errors = <Object>[];
      final done = Completer<void>();
      bell().watch().listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 5));
      expect(errors.single, isA<AuthException>());
      expect(tokens.invalidations, 2);
    });

    test('token failures surface as stream errors', () async {
      tokens.failWith = const AuthException('revoked');
      final errors = <Object>[];
      final done = Completer<void>();
      bell().watch().listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 5));
      expect(errors.single, isA<AuthException>());
    });

    test('reconnects after the connection drops and rings once reconnected', () async {
      server.dropAfterFirstIdle = true;
      var idles = 0;
      final second = Completer<void>();
      server.idling.listen((_) {
        if (++idles == 2) second.complete();
      });
      final events = <void>[];
      final sub = bell().watch().listen(events.add);
      await second.future.timeout(const Duration(seconds: 5));
      expect(server.connections, hasLength(2));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events, hasLength(1), reason: 'changes may have been missed while disconnected');
      await sub.cancel();
    });

    test('keeps retrying with backoff while the server is unreachable', () async {
      var attempts = 0;
      final sleeps = <Duration>[];
      final unreachable = GmailImapDoorbell(
        email: 'me@example.com',
        tokens: tokens,
        connect: () async {
          attempts++;
          throw const SocketException('Network is unreachable');
        },
        config: const ImapDoorbellConfig(
          backoff: RetryBackoff(initial: Duration(seconds: 2), max: Duration(minutes: 5)),
        ),
        sleep: (d) {
          sleeps.add(d);
          return Future<void>.delayed(const Duration(milliseconds: 5));
        },
      );
      final sub = unreachable.watch().listen((_) {}, onError: (Object e) => fail('transient errors are internal: $e'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await sub.cancel();
      expect(attempts, greaterThan(3));
      expect(sleeps.first, lessThanOrEqualTo(const Duration(seconds: 2)));
      expect(sleeps[3], greaterThan(sleeps[0]), reason: 'exponential');
    });
  });
}
