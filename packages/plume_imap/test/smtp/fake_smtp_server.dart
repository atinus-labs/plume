import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// TLS material for the fake servers. The PEM files in `fixtures/` are
/// throwaway self-signed certificates, regenerated with:
///
/// ```sh
/// openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
///   -keyout localhost.key.pem -out localhost.cert.pem -days 36500 \
///   -subj "/CN=localhost/O=Plume test" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
/// # elsewhere.*: the same with CN and SAN mail.example.org (host name mismatch).
/// ```
abstract final class TestCerts {
  static const _dir = 'test/smtp/fixtures';

  /// A server context presenting the certificate for 127.0.0.1/localhost,
  /// or with [elsewhere] one for a different host name.
  static SecurityContext server({bool elsewhere = false}) {
    final name = elsewhere ? 'elsewhere' : 'localhost';
    return SecurityContext()
      ..useCertificateChain('$_dir/$name.cert.pem')
      ..usePrivateKey('$_dir/$name.key.pem');
  }

  /// A client context trusting only the two test certificates.
  static SecurityContext trusting() => SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates('$_dir/localhost.cert.pem')
    ..setTrustedCertificates('$_dir/elsewhere.cert.pem');
}

/// What the fake server saw on one connection.
final class FakeSession {
  final commands = <String>[];
  final logins = <(String mechanism, String username, String password)>[];
  String? mailFrom;
  final recipients = <String>[];

  /// DATA as received on the wire: dot-stuffed, CRLF, without the final
  /// `.CRLF`.
  final messages = <Uint8List>[];
  bool secured = false;
  bool authenticated = false;
  bool quit = false;
  int resets = 0;
}

/// A scriptable SMTP submission server on 127.0.0.1.
///
/// Behaviour is set through the public fields before a client connects.
/// Plain by default; [implicitTls] serves TLS from the first byte;
/// [offerStartTls] advertises STARTTLS on a plain connection.
final class FakeSmtpServer {
  FakeSmtpServer({this.implicitTls = false, SecurityContext? tls}) : _tls = tls ?? TestCerts.server();

  final bool implicitTls;
  final SecurityContext _tls;

  List<String> greeting = ['220 smtp.fake.test ESMTP ready'];

  /// Never send the greeting (a TLS port reached in plain text behaves so).
  bool silent = false;

  /// Extensions after TLS (or always, on a plain server without STARTTLS).
  List<String> extensions = ['SIZE 10485760', '8BITMIME', 'ENHANCEDSTATUSCODES', 'SMTPUTF8', 'AUTH PLAIN LOGIN'];

  bool offerStartTls = false;

  /// Extensions advertised before STARTTLS, besides STARTTLS itself.
  List<String> extensionsBeforeTls = ['SIZE 10485760', '8BITMIME'];

  /// Plain text sent right after "220 Ready to start TLS" (an injection).
  String? injectAfterStartTls;

  bool refuseEhlo = false;

  /// Mechanisms answered with 504 although advertised.
  Set<String> refuseMechanisms = {};

  String username = 'user@fake.test';
  String password = 'secret';
  List<String> authFailure = ['535 5.7.8 Authentication credentials invalid'];

  /// The reply to MAIL FROM (the whole command line); accepted by default.
  List<String> Function(String line) mailReply = (_) => ['250 2.1.0 OK'];

  /// The reply to RCPT TO for an address; accepted by default.
  List<String> Function(String address) rcptReply = (_) => ['250 2.1.5 OK'];

  List<String> dataReply = ['250 2.0.0 OK queued as 4711'];

  /// A command verb after which the server stops answering.
  String? stallOn;

  /// Hang up after receiving part of the message.
  bool dropDuringData = false;

  late final Stream<Socket> _incoming;
  ServerSocket? _plain;
  SecureServerSocket? _secure;
  final sessions = <FakeSession>[];
  final _sockets = <Socket>[];

  int get port => _plain?.port ?? _secure!.port;

  FakeSession get last => sessions.last;

  Future<void> start() async {
    if (implicitTls) {
      _secure = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, _tls);
      _incoming = _secure!;
    } else {
      _plain = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _incoming = _plain!;
    }
    _incoming.listen((socket) => unawaited(_serve(socket)), onError: (Object _) {});
  }

  Future<void> close() async {
    await _plain?.close();
    await _secure?.close();
    for (final s in _sockets) {
      s.destroy();
    }
  }

  Future<void> _serve(Socket socket) async {
    _sockets.add(socket);
    final session = FakeSession()..secured = implicitTls;
    sessions.add(session);
    final conn = _ServerConnection(socket);
    try {
      if (silent) {
        await conn.readLine();
        return;
      }
      conn.sendAll(greeting);
      var stalled = false;
      while (true) {
        final line = await conn.readLine();
        if (line == null) return;
        session.commands.add(line);
        if (stalled) continue;
        final verb = line.split(' ').first.toUpperCase();
        if (verb == stallOn) {
          stalled = true;
          continue;
        }
        switch (verb) {
          case 'EHLO':
            if (refuseEhlo) {
              conn.send('502 5.5.1 Unrecognized command');
              continue;
            }
            final lines = [
              'smtp.fake.test at your service',
              if (offerStartTls && !session.secured) ...['STARTTLS', ...extensionsBeforeTls] else ...extensions,
            ];
            conn.sendAll([for (var i = 0; i < lines.length; i++) '250${i == lines.length - 1 ? ' ' : '-'}${lines[i]}']);
          case 'HELO':
            conn.send('250 smtp.fake.test');
          case 'STARTTLS':
            if (!offerStartTls || session.secured) {
              conn.send('502 5.5.1 Unrecognized command');
              continue;
            }
            conn.send('220 2.0.0 Ready to start TLS${injectAfterStartTls == null ? '' : '\r\n$injectAfterStartTls'}');
            await conn.secure(_tls);
            session.secured = true;
          case 'AUTH':
            await _auth(conn, session, line);
          case 'MAIL':
            if (!session.authenticated) {
              conn.send('530 5.7.0 Authentication required');
              continue;
            }
            final reply = mailReply(line);
            if (reply.last.startsWith('250')) session.mailFrom = line;
            conn.sendAll(reply);
          case 'RCPT':
            final address = RegExp('<(.*)>').firstMatch(line)!.group(1)!;
            final reply = rcptReply(address);
            if (reply.last.startsWith('25')) session.recipients.add(address);
            conn.sendAll(reply);
          case 'DATA':
            if (session.recipients.isEmpty) {
              conn.send('554 5.5.1 No valid recipients');
              continue;
            }
            conn.send('354 Go ahead');
            if (dropDuringData) {
              await conn.waitForBytes(1);
              socket.destroy();
              return;
            }
            final data = await conn.readData();
            if (data == null) return;
            session.messages.add(data);
            conn.sendAll(dataReply);
          case 'RSET':
            session
              ..resets += 1
              ..mailFrom = null
              ..recipients.clear();
            conn.send('250 2.0.0 OK');
          case 'NOOP':
            conn.send('250 2.0.0 OK');
          case 'QUIT':
            session.quit = true;
            conn.send('221 2.0.0 Bye');
            await conn.close();
            return;
          default:
            conn.send('502 5.5.1 Unrecognized command');
        }
      }
    } on Object {
      // The client went away mid-conversation; tests check what they need.
    }
  }

  Future<void> _auth(_ServerConnection conn, FakeSession session, String line) async {
    final parts = line.split(' ');
    final mechanism = parts[1].toUpperCase();
    final advertised = extensions.any((e) => e.toUpperCase().startsWith('AUTH') && e.toUpperCase().contains(mechanism));
    if (!advertised || refuseMechanisms.contains(mechanism)) {
      conn.send('504 5.5.4 Unrecognized authentication type');
      return;
    }
    String decode(String s) => utf8.decode(base64.decode(s));
    String user;
    String pass;
    switch (mechanism) {
      case 'PLAIN':
        var response = parts.length > 2 ? parts[2] : null;
        if (response == null) {
          conn.send('334 ');
          response = await conn.readLine();
        }
        final fields = decode(response!).split('\u0000');
        (user, pass) = (fields[1], fields[2]);
      case 'LOGIN':
        conn.send('334 VXNlcm5hbWU6');
        user = decode((await conn.readLine())!);
        conn.send('334 UGFzc3dvcmQ6');
        pass = decode((await conn.readLine())!);
      default:
        conn.send('504 5.5.4 Unrecognized authentication type');
        return;
    }
    session.logins.add((mechanism, user, pass));
    if (user == username && pass == password) {
      session.authenticated = true;
      conn.send('235 2.7.0 Accepted');
    } else {
      conn.sendAll(authFailure);
    }
  }
}

/// Server side of one connection, with in-place TLS upgrade.
final class _ServerConnection {
  _ServerConnection(this._socket) {
    _listen();
  }

  Socket _socket;
  late StreamSubscription<Uint8List> _subscription;
  final _buffer = <int>[];
  Completer<void>? _wake;
  bool _done = false;

  void _listen() {
    // Writes to a client that already hung up fail here; that is expected.
    _socket.done.then((_) {}, onError: (Object _) {}).ignore();
    _subscription = _socket.listen(
      (data) {
        _buffer.addAll(data);
        _signal();
      },
      onDone: () {
        _done = true;
        _signal();
      },
      onError: (Object _) {
        _done = true;
        _signal();
      },
      cancelOnError: true,
    );
  }

  void _signal() {
    final wake = _wake;
    _wake = null;
    wake?.complete();
  }

  Future<void> _more() {
    final wake = _wake = Completer<void>();
    return wake.future;
  }

  Future<String?> readLine() async {
    while (true) {
      final i = _buffer.indexOf(0x0A);
      if (i >= 0) {
        var line = _buffer.sublist(0, i);
        _buffer.removeRange(0, i + 1);
        if (line.isNotEmpty && line.last == 0x0D) line = line.sublist(0, line.length - 1);
        return utf8.decode(line, allowMalformed: true);
      }
      if (_done) return null;
      await _more();
    }
  }

  Future<void> waitForBytes(int count) async {
    while (_buffer.length < count && !_done) {
      await _more();
    }
  }

  /// Reads DATA up to the terminating CRLF.CRLF.
  Future<Uint8List?> readData() async {
    const end = [0x0D, 0x0A, 0x2E, 0x0D, 0x0A];
    while (true) {
      for (var i = 0; i + end.length <= _buffer.length; i++) {
        var match = true;
        for (var j = 0; j < end.length && match; j++) {
          match = _buffer[i + j] == end[j];
        }
        if (match) {
          final data = Uint8List.fromList(_buffer.sublist(0, i + 2));
          _buffer.removeRange(0, i + end.length);
          return data;
        }
      }
      if (_done) return null;
      await _more();
    }
  }

  void send(String line) => _socket.add(utf8.encode('$line\r\n'));

  void sendAll(List<String> lines) => _socket.add(utf8.encode(lines.map((l) => '$l\r\n').join()));

  Future<void> secure(SecurityContext context) async {
    _subscription.pause();
    _socket = await SecureSocket.secureServer(_socket, context);
    _listen();
  }

  Future<void> close() async {
    await _socket.flush();
    await _socket.close();
  }
}
