import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A command as received by a test server: its tag, the command text with
/// literals removed (each literal leaves `{n}` in place) and the literal
/// payloads in order.
final class ReceivedCommand {
  ReceivedCommand(this.tag, this.text, this.literals);

  final String tag;

  /// Everything after the tag, e.g. `UID FETCH 1:* (FLAGS)`.
  final String text;
  final List<Uint8List> literals;

  /// Upper-cased command name, including `UID` for UID commands.
  String get name {
    final words = text.split(' ');
    final first = words.first.toUpperCase();
    if (first == 'UID' && words.length > 1) return 'UID ${words[1].toUpperCase()}';
    return first;
  }

  /// Text after the command name.
  String get args {
    final n = name.split(' ').length;
    final words = text.split(' ');
    return words.length <= n ? '' : words.sublist(n).join(' ');
  }

  @override
  String toString() => '$tag $text';
}

/// Server side of one test connection: reads client commands (answering
/// synchronizing literals with a continuation) and writes responses.
/// Can be upgraded to TLS (STARTTLS).
final class ServerConnection {
  ServerConnection(Socket socket) : _socket = socket {
    _listen(socket);
  }

  Socket _socket;
  StreamSubscription<Uint8List>? _sub;
  final _buffer = BytesBuilder(copy: true);
  Completer<void>? _dataSignal;
  bool _closed = false;

  /// Every command received, for assertions.
  final received = <ReceivedCommand>[];

  bool get isClosed => _closed;

  void _listen(Stream<Uint8List> stream) {
    _sub = stream.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object _) {
        _closed = true;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );
  }

  void _wake() {
    final s = _dataSignal;
    _dataSignal = null;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _waitForData() async {
    if (_closed) throw const SocketException('client closed the connection');
    final s = _dataSignal = Completer<void>();
    await s.future;
  }

  /// Reads one CRLF-terminated line (without the CRLF).
  Future<String> readLine() async {
    while (true) {
      final bytes = _buffer.toBytes();
      final lf = bytes.indexOf(0x0A);
      if (lf >= 0) {
        _buffer.clear();
        _buffer.add(Uint8List.sublistView(bytes, lf + 1));
        var end = lf;
        if (end > 0 && bytes[end - 1] == 0x0D) end--;
        return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
      }
      await _waitForData();
    }
  }

  Future<Uint8List> _readBytes(int n) async {
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length >= n) {
        _buffer.clear();
        _buffer.add(Uint8List.sublistView(bytes, n));
        return Uint8List.fromList(bytes.sublist(0, n));
      }
      await _waitForData();
    }
  }

  /// Reads a full command, handling `{n}` (with a `+` continuation) and
  /// `{n+}` literals. Returns null when the client disconnected.
  Future<ReceivedCommand?> readCommand() async {
    try {
      final text = StringBuffer();
      final literals = <Uint8List>[];
      var line = await readLine();
      while (true) {
        final m = RegExp(r'\{(\d+)(\+?)\}$').firstMatch(line);
        if (m == null) {
          text.write(line);
          break;
        }
        text.write(line.substring(0, m.start));
        text.write('{${m.group(1)}}');
        if (m.group(2)!.isEmpty) send('+ go ahead');
        literals.add(await _readBytes(int.parse(m.group(1)!)));
        line = await readLine();
      }
      final full = text.toString();
      final space = full.indexOf(' ');
      final cmd = ReceivedCommand(space < 0 ? full : full.substring(0, space), space < 0 ? '' : full.substring(space + 1), literals);
      received.add(cmd);
      return cmd;
    } on SocketException {
      return null;
    }
  }

  /// Writes [line] plus CRLF.
  void send(String line) => sendBytes(utf8.encode('$line\r\n'));

  void sendBytes(List<int> bytes) {
    if (_closed) return;
    try {
      _socket.add(bytes);
    } on Object {
      _closed = true;
    }
  }

  /// Stops reading from the socket for [duration], like a slow server or
  /// network: the client's writes back up.
  Future<void> stall(Duration duration) async {
    _sub?.pause();
    await Future<void>.delayed(duration);
    _sub?.resume();
  }

  /// Upgrades to TLS as the server side.
  Future<void> startTls(SecurityContext context) async {
    final sub = _sub;
    sub?.pause();
    _socket = await SecureSocket.secureServer(_socket, context);
    _listen(_socket);
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _socket.flush();
    } on Object {
      // ignore
    }
    _socket.destroy();
    _wake();
  }
}

/// A server that runs [handler] for each accepted connection.
final class ScriptedServer {
  ScriptedServer._(this._server, this._handler) {
    _server.listen((socket) {
      final conn = ServerConnection(socket);
      connections.add(conn);
      unawaited(_run(conn));
    });
  }

  static Future<ScriptedServer> start(Future<void> Function(ServerConnection c) handler) async =>
      ScriptedServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), handler);

  final ServerSocket _server;
  final Future<void> Function(ServerConnection c) _handler;
  final connections = <ServerConnection>[];
  final errors = <Object>[];

  int get port => _server.port;

  Future<void> _run(ServerConnection c) async {
    try {
      await _handler(c);
    } on SocketException catch (e) {
      // The client went away; failed expectations still surface.
      errors.add(e);
    } on TlsException catch (e) {
      // The client rejected our certificate (tested on the client side).
      errors.add(e);
    } finally {
      await c.close();
    }
  }

  Future<void> close() async {
    await _server.close();
    for (final c in connections) {
      await c.close();
    }
  }
}
