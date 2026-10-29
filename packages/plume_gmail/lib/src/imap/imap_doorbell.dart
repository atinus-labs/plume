import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';

import '../util/backoff.dart';
import 'imap_reader.dart';

final Logger _log = Logger('plume.gmail.imap');

/// Opens the transport to the IMAP server. The default uses TLS to
/// imap.gmail.com:993; tests inject a plain local socket.
typedef ImapConnector = Future<Socket> Function();

final class ImapDoorbellConfig {
  const ImapDoorbellConfig({
    this.host = 'imap.gmail.com',
    this.port = 993,
    this.mailbox = 'INBOX',
    this.idleRestart = const Duration(minutes: 25),
    this.debounce = const Duration(seconds: 1),
    this.commandTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 30),
    this.keepAliveIdle = const Duration(seconds: 60),
    this.backoff = const RetryBackoff(initial: Duration(seconds: 2), max: Duration(minutes: 5)),
  });

  final String host;
  final int port;
  final String mailbox;

  /// RFC 2177 asks clients to re-issue IDLE at least every 29 minutes;
  /// servers drop idle connections after 30.
  final Duration idleRestart;

  /// Bursts of server notifications within this window ring once.
  final Duration debounce;

  /// How long to wait for a tagged response (also detects dead
  /// connections when IDLE is restarted).
  final Duration commandTimeout;
  final Duration connectTimeout;

  /// Silence after which TCP keepalive probes start. IDLE sends nothing
  /// for minutes, and routers silently drop connections that look idle;
  /// the probes keep them open, and a connection that died anyway fails
  /// within about two minutes instead of at the next IDLE restart.
  final Duration keepAliveIdle;
  final RetryBackoff backoff;
}

/// Real-time change signal for a Gmail account using IMAP IDLE.
///
/// This is only a doorbell: it carries no data. Each event means "the
/// mailbox changed, run an incremental sync", which then uses the REST API.
///
/// Connects with `AUTHENTICATE XOAUTH2`, `SELECT`s the inbox and IDLEs,
/// emitting (debounced) on untagged EXISTS / EXPUNGE / FETCH. IDLE is
/// restarted every [ImapDoorbellConfig.idleRestart]. Socket errors trigger
/// reconnection with exponential backoff, and one event after each
/// reconnect because changes may have been missed. An authentication
/// failure invalidates the token and retries once; a second failure is
/// emitted as an [AuthException] and the stream closes. Cancelling the
/// subscription ends IDLE, logs out and closes the socket.
final class GmailImapDoorbell {
  GmailImapDoorbell({
    required this.email,
    required this._tokens,
    this._connect,
    this.config = const ImapDoorbellConfig(),
    Random? random,
    Sleep? sleep,
  })  : _random = random ?? Random(),
        _sleep = sleep ?? defaultSleep;

  final String email;
  final TokenSource _tokens;
  final ImapConnector? _connect;
  final ImapDoorbellConfig config;
  final Random _random;
  final Sleep _sleep;

  /// A new connection per listener; single-subscription.
  Stream<void> watch() {
    _Runner? runner;
    late final StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        runner = _Runner(this, controller);
        unawaited(runner!.run());
      },
      onCancel: () => runner?.stop(),
    );
    return controller.stream;
  }

  Future<Socket> _open() async {
    final connect = _connect;
    if (connect != null) return connect();
    final socket = await SecureSocket.connect(config.host, config.port, timeout: config.connectTimeout);
    enableTcpKeepAlive(socket, idle: config.keepAliveIdle);
    return socket;
  }
}

/// Turns on TCP keepalive: a probe after [idle] of silence, then every 15 s,
/// giving up after 4 unanswered probes. Linux only (the option numbers are
/// Linux's); elsewhere the socket is left as is.
void enableTcpKeepAlive(Socket socket, {required Duration idle}) {
  if (!Platform.isLinux) return;
  const soKeepAlive = 9, tcpKeepIdle = 4, tcpKeepInterval = 5, tcpKeepCount = 6;
  try {
    socket
      ..setRawOption(RawSocketOption.fromBool(RawSocketOption.levelSocket, soKeepAlive, true))
      ..setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, tcpKeepIdle, idle.inSeconds))
      ..setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, tcpKeepInterval, 15))
      ..setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, tcpKeepCount, 4));
  } on Object catch (e) {
    _log.fine('Could not enable TCP keepalive: $e');
  }
}

final class _Runner {
  _Runner(this._bell, this._controller);

  final GmailImapDoorbell _bell;
  final StreamController<void> _controller;
  final _stopSignal = Completer<void>();
  final _done = Completer<void>();
  bool _stopped = false;
  _ImapSession? _session;
  Timer? _debounce;

  ImapDoorbellConfig get _config => _bell.config;

  Future<void> stop() async {
    if (_stopped) return _done.future;
    _stopped = true;
    _debounce?.cancel();
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    _session?.wake();
    await _done.future.timeout(const Duration(seconds: 5), onTimeout: () => _session?.destroy());
  }

  Future<void> run() async {
    var failures = 0;
    var authRetried = false;
    var connectedBefore = false;
    try {
      while (!_stopped) {
        _ImapSession? session;
        try {
          final socket = await _bell._open().timeout(_config.connectTimeout);
          if (_stopped) {
            socket.destroy();
            break;
          }
          session = _session = _ImapSession(socket, _config.commandTimeout);
          await session.expectGreeting();
          final token = await _bell._tokens.accessToken();
          if (_stopped) break;
          if (!await session.authenticate(_bell.email, token)) {
            if (authRetried) throw const AuthException('Gmail IMAP rejected the access token');
            _log.fine('IMAP authentication failed; refreshing the token and retrying');
            authRetried = true;
            _bell._tokens.invalidate();
            continue;
          }
          authRetried = false;
          await session.select(_config.mailbox);
          failures = 0;
          _log.fine('IMAP doorbell connected');
          if (connectedBefore) _ring();
          connectedBefore = true;
          while (!_stopped) {
            await session.idle(restartAfter: _config.idleRestart, isStopped: () => _stopped, onChange: _ring);
          }
          await session.logout();
        } on AuthException catch (e) {
          if (!_stopped && !_controller.isClosed) _controller.addError(e);
          return;
        } on Object catch (e) {
          if (_stopped) break;
          failures++;
          _log.fine('IMAP doorbell disconnected (attempt $failures): ${e.runtimeType}');
        } finally {
          session?.destroy();
          _session = null;
        }
        if (_stopped) break;
        if (failures > 0) {
          await Future.any([_bell._sleep(_config.backoff.delay(failures - 1, _bell._random)), _stopSignal.future]);
        }
      }
    } finally {
      _debounce?.cancel();
      if (!_done.isCompleted) _done.complete();
      if (!_controller.isClosed) unawaited(_controller.close());
    }
  }

  void _ring() {
    if (_stopped || _controller.isClosed) return;
    _debounce ??= Timer(_config.debounce, () {
      _debounce = null;
      if (!_stopped && !_controller.isClosed) _controller.add(null);
    });
  }
}

/// One IMAP connection. Reads are pulled from an internal queue so that a
/// timed-out wait never swallows a response.
final class _ImapSession {
  _ImapSession(this._socket, this._timeout) {
    _socket.listen(_onData, onError: _onError, onDone: _onDone, cancelOnError: true);
    // Write failures surface here; they are also seen by the reader.
    _socket.done.then((_) {}, onError: (Object e) => _onError(e)).ignore();
  }

  final Socket _socket;
  final Duration _timeout;
  final _reader = ImapResponseReader();
  final _queue = Queue<ImapResponse>();
  Completer<void>? _signal;
  Object? _error;
  bool _closed = false;
  int _tags = 0;

  static final RegExp _change = RegExp(r'^\* \d+ (EXISTS|EXPUNGE|FETCH)\b', caseSensitive: false);

  void _onData(List<int> data) {
    try {
      _queue.addAll(_reader.add(data));
    } on ImapProtocolException catch (e) {
      _error ??= e;
      _closed = true;
      _socket.destroy();
    }
    wake();
  }

  void _onError(Object e) {
    _error ??= e;
    _closed = true;
    wake();
  }

  void _onDone() {
    _closed = true;
    wake();
  }

  void wake() {
    final s = _signal;
    _signal = null;
    if (s != null && !s.isCompleted) s.complete();
  }

  void destroy() {
    _closed = true;
    _socket.destroy();
    wake();
  }

  /// The next response; null on timeout or when [isStopped] turns true.
  Future<ImapResponse?> read(Duration timeout, {bool Function()? isStopped}) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (_queue.isNotEmpty) return _queue.removeFirst();
      final error = _error;
      if (error != null) throw error;
      if (_closed) throw const SocketException('IMAP connection closed');
      if (isStopped != null && isStopped()) return null;
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) return null;
      final signal = _signal = Completer<void>();
      final timer = Timer(remaining, wake);
      await signal.future;
      timer.cancel();
    }
  }

  Future<ImapResponse> _expect() async {
    final r = await read(_timeout);
    if (r == null) throw TimeoutException('IMAP server did not respond', _timeout);
    return r;
  }

  String _nextTag() => 'P${++_tags}';

  void _send(String line) {
    if (_closed) throw const SocketException('IMAP connection closed');
    _socket.add(utf8.encode('$line\r\n'));
  }

  Future<void> expectGreeting() async {
    final r = await _expect();
    final upper = r.text.toUpperCase();
    if (upper.startsWith('* OK') || upper.startsWith('* PREAUTH')) return;
    throw ImapProtocolException('Unexpected IMAP greeting');
  }

  /// SASL XOAUTH2 with an initial response. Returns false when the server
  /// rejects the credentials.
  Future<bool> authenticate(String email, String token) async {
    final tag = _nextTag();
    final payload = base64.encode(utf8.encode('user=$email\x01auth=Bearer $token\x01\x01'));
    _send('$tag AUTHENTICATE XOAUTH2 $payload');
    while (true) {
      final r = await _expect();
      if (r.isContinuation) {
        // On failure Gmail sends a base64 JSON error as a challenge; an
        // empty response makes it finish with a tagged NO.
        _send('');
        continue;
      }
      if (r.tag == tag) {
        switch (r.status) {
          case 'OK':
            return true;
          case 'NO':
            return false;
          default:
            throw ImapProtocolException('AUTHENTICATE failed with ${r.status}');
        }
      }
    }
  }

  Future<void> select(String mailbox) async {
    final tag = _nextTag();
    _send('$tag SELECT "${mailbox.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"');
    while (true) {
      final r = await _expect();
      if (r.tag == tag) {
        if (r.status != 'OK') throw ImapProtocolException('SELECT failed with ${r.status}');
        return;
      }
    }
  }

  /// Runs one IDLE cycle until [restartAfter] elapses or [isStopped]
  /// turns true, then sends DONE and waits for the tagged completion.
  Future<void> idle({
    required Duration restartAfter,
    required bool Function() isStopped,
    required void Function() onChange,
  }) async {
    final tag = _nextTag();
    _send('$tag IDLE');
    while (true) {
      final r = await _expect();
      if (r.isContinuation) break;
      if (r.tag == tag) throw ImapProtocolException('IDLE rejected with ${r.status}');
      if (_change.hasMatch(r.text)) onChange();
    }

    final watch = Stopwatch()..start();
    while (!isStopped()) {
      final remaining = restartAfter - watch.elapsed;
      if (remaining <= Duration.zero) break;
      final r = await read(remaining, isStopped: isStopped);
      if (r == null) continue;
      if (r.tag == tag) return; // The server ended IDLE itself.
      if (_change.hasMatch(r.text)) onChange();
    }

    _send('DONE');
    final limit = isStopped() ? const Duration(seconds: 2) : _timeout;
    while (true) {
      final r = await read(limit);
      if (r == null) throw TimeoutException('No response to DONE', limit);
      if (r.tag == tag) return;
      if (_change.hasMatch(r.text)) onChange();
    }
  }

  Future<void> logout() async {
    try {
      _send('${_nextTag()} LOGOUT');
      await _socket.flush().timeout(const Duration(seconds: 2));
    } on Object {
      // Best effort.
    }
  }
}
