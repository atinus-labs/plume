import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'imap_exception.dart';
import 'imap_response.dart';

final Logger _log = Logger('plume.imap');

/// A literal argument of a command (`{n}` followed by raw bytes).
final class ImapLiteral {
  const ImapLiteral(this.bytes);

  final Uint8List bytes;
}

/// A command to send. [parts] are `String`s (sent as UTF-8, which is plain
/// ASCII unless UTF8=ACCEPT is enabled) and [ImapLiteral]s.
final class ImapCommand {
  ImapCommand(
    this.name,
    this.parts, {
    this.onContinuation,
    this.onUntagged,
    this.timeoutExempt = false,
  });

  /// Short name for logs and errors (`UID FETCH`); never contains
  /// arguments, which may be secret.
  final String name;
  final List<Object> parts;

  /// Handles `+` continuation requests not consumed by literals
  /// (AUTHENTICATE challenges, IDLE). Returns a line to send (without
  /// CRLF), or null to send nothing.
  final List<int>? Function(ImapResponse continuation)? onContinuation;

  /// Sees untagged responses attributed to this command, as they arrive.
  final void Function(ImapResponse response)? onUntagged;

  /// Whether the response timeout applies. IDLE turns this on once the
  /// server confirmed idling; the server may then stay silent for minutes.
  bool timeoutExempt;
}

/// The outcome of a command: its tagged completion and the untagged
/// responses received while it was the oldest outstanding command.
final class ImapResult {
  const ImapResult(this.command, this.tagged, this.untagged);

  final String command;
  final ImapResponse tagged;
  final List<ImapResponse> untagged;

  bool get isOk => tagged.status == 'OK';

  /// Untagged responses of [type] (e.g. `FETCH`, `LIST`).
  Iterable<ImapResponse> ofType(String type) => untagged.where((r) => r.type == type);

  /// Throws [ImapCommandException] unless the command succeeded.
  ImapResult check() {
    if (isOk) return this;
    throw ImapCommandException(
      command: command,
      status: tagged.status ?? 'BAD',
      code: tagged.code?.name,
      text: tagged.text,
    );
  }
}

final class _Pending {
  _Pending(this.tag, this.command);

  final String tag;
  final ImapCommand command;
  final untagged = <ImapResponse>[];
  final completer = Completer<ImapResult>();
  Completer<ImapResponse?>? continuation;
}

/// One IMAP connection: frames responses, matches tagged completions to
/// commands, sends literals (synchronizing or LITERAL+), and enforces a
/// response timeout so that a hung server cannot stall a caller forever.
///
/// Commands may be pipelined: [send] can be called again before earlier
/// commands complete. Untagged responses go to [onUntagged] and are also
/// attributed to the oldest outstanding command, which matches how servers
/// process pipelined commands.
final class ImapConnection {
  ImapConnection(
    Socket socket, {
    this.responseTimeout = const Duration(seconds: 60),
    this.maxLiteralSize = 256 << 20,
    this.debugName = 'imap',
  }) : _socket = socket {
    _listen();
  }

  /// Longest silence tolerated while a command is outstanding.
  Duration responseTimeout;
  final int maxLiteralSize;
  final String debugName;

  Socket _socket;
  late StreamSubscription<Uint8List> _subscription;
  late ImapResponseReader _reader;
  final _pending = Queue<_Pending>();
  final _greeting = Completer<ImapResponse>();
  final _closed = Completer<void>();
  Future<void> _writeTail = Future.value();
  Timer? _timer;
  int _tags = 0;
  bool _isClosed = false;
  Object? _closeError;
  String? _byeText;

  /// Literals up to this size may be sent without waiting for the server's
  /// continuation (LITERAL+ = unlimited, LITERAL- = 4096, else 0).
  int nonSyncLiteralLimit = 0;

  /// Called for every untagged response, before routing.
  void Function(ImapResponse response)? onUntagged;

  /// The server greeting (`* OK`, `* PREAUTH` or `* BYE`).
  Future<ImapResponse> get greeting => _greeting.future;

  bool get isClosed => _isClosed;

  /// Completes when the connection is closed, for any reason.
  Future<void> get done => _closed.future;

  /// Text of a `BYE` the server sent, if any.
  String? get byeText => _byeText;

  void _listen() {
    _reader = ImapResponseReader(maxLiteralSize: maxLiteralSize);
    _subscription = _socket.listen(
      _onData,
      onError: (Object e) => _fail(ImapConnectionException('Connection error', e)),
      onDone: () => _fail(ImapConnectionException(_byeText == null ? 'Connection closed by server' : 'Server closed the connection: $_byeText')),
      cancelOnError: true,
    );
    _armTimer();
  }

  void _onData(Uint8List chunk) {
    if (_isClosed) return;
    _armTimer();
    List<RawResponse> responses;
    try {
      responses = _reader.add(chunk);
    } on ImapProtocolException catch (e) {
      _fail(e);
      return;
    }
    for (final raw in responses) {
      ImapResponse response;
      try {
        response = ImapParser.parse(raw);
      } on ImapProtocolException catch (e) {
        _fail(e);
        return;
      }
      _dispatch(response);
      if (_isClosed) return;
    }
  }

  void _dispatch(ImapResponse r) {
    switch (r.kind) {
      case ImapResponseKind.continuation:
        _onContinuation(r);
      case ImapResponseKind.tagged:
        _onTagged(r);
      case ImapResponseKind.untagged:
        if (!_greeting.isCompleted) {
          _greeting.complete(r);
          return;
        }
        if (r.status == 'BYE') _byeText = r.text;
        onUntagged?.call(r);
        if (_pending.isNotEmpty) {
          final p = _pending.first;
          p.untagged.add(r);
          p.command.onUntagged?.call(r);
        }
    }
  }

  void _onContinuation(ImapResponse r) {
    for (final p in _pending) {
      final waiting = p.continuation;
      if (waiting != null && !waiting.isCompleted) {
        waiting.complete(r);
        return;
      }
    }
    for (final p in _pending) {
      final handler = p.command.onContinuation;
      if (handler != null) {
        final reply = handler(r);
        if (reply != null) _write([...reply, 0x0D, 0x0A]);
        _armTimer();
        return;
      }
    }
    _log.fine('[$debugName] Ignoring unexpected continuation request');
  }

  void _onTagged(ImapResponse r) {
    _Pending? match;
    for (final p in _pending) {
      if (p.tag == r.tag) {
        match = p;
        break;
      }
    }
    if (match == null) {
      _log.fine('[$debugName] Ignoring response for unknown tag ${r.tag}');
      return;
    }
    _pending.remove(match);
    // A literal the server refused: stop waiting for its continuation.
    final waiting = match.continuation;
    if (waiting != null && !waiting.isCompleted) waiting.complete(null);
    if (r.status != 'OK') _log.fine('[$debugName] ${match.command.name} ${r.status} ${r.code ?? ''}');
    match.completer.complete(ImapResult(match.command.name, r, match.untagged));
    _armTimer();
  }

  /// Sends [command] and completes with its result (also for `NO`/`BAD`;
  /// use [ImapResult.check]). Fails with an [ImapException] if the
  /// connection breaks or times out first.
  Future<ImapResult> send(ImapCommand command) {
    if (_isClosed) return Future.error(_closeError ?? const ImapConnectionException('Connection closed'));
    final pending = _Pending('P${++_tags}', command);
    _log.finer('[$debugName] C: ${pending.tag} ${command.name}');
    _pending.add(pending);
    _armTimer();
    _writeTail = _writeTail.then((_) => _writeCommand(pending)).catchError((Object e) {
      _fail(e is ImapException ? e : ImapConnectionException('Write failed', e));
    });
    return pending.completer.future;
  }

  Future<void> _writeCommand(_Pending p) async {
    if (_isClosed || p.completer.isCompleted) return;
    final buffer = BytesBuilder(copy: false)..add(ascii.encode('${p.tag} '));
    for (final part in p.command.parts) {
      if (part is String) {
        buffer.add(utf8.encode(part));
      } else if (part is ImapLiteral) {
        final n = part.bytes.length;
        if (n <= nonSyncLiteralLimit) {
          buffer
            ..add(ascii.encode('{$n+}\r\n'))
            ..add(part.bytes);
          continue;
        }
        buffer.add(ascii.encode('{$n}\r\n'));
        final waiting = p.continuation = Completer<ImapResponse?>();
        _write(buffer.takeBytes());
        final go = await waiting.future;
        p.continuation = null;
        if (go == null || _isClosed) return; // Refused, or connection gone.
        if (part.bytes.length >= _uploadThreshold) {
          await _upload(part.bytes);
          if (_isClosed) return;
          continue;
        }
        buffer.add(part.bytes);
      } else {
        throw ArgumentError('Unsupported command part ${part.runtimeType}');
      }
    }
    buffer.add(const [0x0D, 0x0A]);
    final bytes = buffer.takeBytes();
    if (bytes.length >= _uploadThreshold) {
      await _upload(bytes);
    } else {
      _write(bytes);
    }
  }

  /// Larger writes are uploads (APPEND of a message with attachments).
  static const _uploadThreshold = 64 << 10;
  int _uploading = 0;
  Completer<void>? _flushing;

  /// Writes [bytes] and waits until the system took them. While uploading
  /// the server is not expected to say anything, so the response timeout
  /// is suspended; instead the upload must progress at 16 KiB/s or better
  /// (on top of the response timeout), so a dead connection still fails.
  Future<void> _upload(List<int> bytes) async {
    if (_isClosed) return;
    final flushing = _flushing = Completer<void>();
    _uploading++;
    _armTimer();
    try {
      _socket.add(bytes);
      await _socket.flush().timeout(responseTimeout + Duration(milliseconds: bytes.length ~/ 16));
    } on TimeoutException {
      _fail(const ImapTimeoutException('Uploading to the server stalled'));
    } on Object catch (e) {
      _fail(ImapConnectionException('Write failed', e));
    } finally {
      _uploading--;
      _flushing = null;
      flushing.complete();
      _armTimer();
    }
  }

  /// Writes raw protocol bytes (e.g. `DONE\r\n`).
  void writeLine(String line) => _write(utf8.encode('$line\r\n'));

  void _write(List<int> bytes) {
    if (_isClosed) return;
    final flushing = _flushing;
    if (flushing != null) {
      // The socket refuses writes while a flush is pending.
      flushing.future.then((_) => _write(bytes)).ignore();
      return;
    }
    try {
      _socket.add(bytes);
    } on Object catch (e) {
      _fail(ImapConnectionException('Write failed', e));
    }
  }

  /// Restarts the response timer, or stops it when nothing is outstanding.
  void _armTimer() {
    _timer?.cancel();
    if (_isClosed) return;
    final waitingForGreeting = !_greeting.isCompleted;
    if (_uploading > 0) return; // See _upload.
    final active = _pending.any((p) => !p.command.timeoutExempt);
    if (!waitingForGreeting && !active) return;
    _timer = Timer(responseTimeout, () {
      _fail(ImapTimeoutException('No response from the server within ${responseTimeout.inSeconds} s'));
    });
  }

  /// Re-evaluates the timeout after a command's [ImapCommand.timeoutExempt]
  /// changed.
  void refreshTimeout() => _armTimer();

  /// Upgrades the connection to TLS after a successful `STARTTLS`.
  Future<void> startTls({required String host, SecurityContext? context, required Duration timeout}) async {
    if (_pending.isNotEmpty) throw StateError('STARTTLS with commands outstanding');
    _timer?.cancel();
    _subscription.pause();
    final plain = _socket;
    try {
      _socket = await SecureSocket.secure(plain, host: host, context: context).timeout(timeout);
    } on TimeoutException {
      plain.destroy();
      _markClosed(const ImapTimeoutException('TLS handshake timed out'));
      throw const ImapTimeoutException('TLS handshake timed out');
    } catch (e) {
      plain.destroy();
      _markClosed(ImapConnectionException('TLS handshake failed', e));
      rethrow;
    }
    _listen();
  }

  void _fail(Object error) {
    if (_isClosed) return;
    _log.fine('[$debugName] Connection closing: $error');
    _markClosed(error);
    _socket.destroy();
  }

  void _markClosed(Object error) {
    if (_isClosed) return;
    _isClosed = true;
    _closeError = error;
    _timer?.cancel();
    if (!_greeting.isCompleted) _greeting.completeError(error);
    // Avoid unhandled errors for greeting futures nobody awaits.
    _greeting.future.ignore();
    while (_pending.isNotEmpty) {
      final p = _pending.removeFirst();
      final waiting = p.continuation;
      if (waiting != null && !waiting.isCompleted) waiting.complete(null);
      if (!p.completer.isCompleted) p.completer.completeError(error);
    }
    if (!_closed.isCompleted) _closed.complete();
  }

  /// Closes the socket immediately; outstanding commands fail.
  void destroy() => _fail(const ImapConnectionException('Connection closed'));

  /// Sends what is buffered and closes the socket gracefully.
  Future<void> close() async {
    if (_isClosed) return;
    _markClosed(const ImapConnectionException('Connection closed'));
    try {
      await _socket.flush().timeout(const Duration(seconds: 2));
      await _socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Best effort.
    } finally {
      _socket.destroy();
    }
  }
}
