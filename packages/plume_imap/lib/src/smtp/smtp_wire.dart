import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'smtp_exception.dart';

/// A line-oriented SMTP transport over a socket that can be upgraded to TLS
/// in place (STARTTLS).
///
/// Incoming lines are queued, so a read that times out never loses data,
/// and a dead connection is reported to the next read instead of as an
/// unhandled error.
final class SmtpWire {
  SmtpWire(Socket socket, {required this.host}) : _socket = socket {
    _attach();
  }

  /// The server name, used for messages and TLS host name verification.
  final String host;

  Socket _socket;
  late StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _partial = BytesBuilder();
  final Queue<String> _lines = Queue();
  Completer<void>? _wake;
  Object? _error;
  bool _closed = false;
  bool _destroyed = false;

  /// RFC 5321 limits reply lines to 512 octets; this is generous slack
  /// before deciding the peer is not an SMTP server.
  static const _maxLineLength = 16 * 1024;

  /// Whether the connection is encrypted.
  bool get isSecure => _socket is SecureSocket;

  void _attach() {
    final socket = _socket;
    _subscription = socket.listen(_onData, onError: _onError, onDone: _onDone, cancelOnError: true);
    // Write failures complete `done` with an error; the next read sees it.
    socket.done.then((_) {}, onError: _onError).ignore();
  }

  void _onData(Uint8List data) {
    var start = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != 0x0A) continue;
      _partial.add(Uint8List.sublistView(data, start, i));
      var bytes = _partial.takeBytes();
      if (bytes.isNotEmpty && bytes.last == 0x0D) bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      _lines.add(utf8.decode(bytes, allowMalformed: true));
      start = i + 1;
    }
    if (start < data.length) _partial.add(Uint8List.sublistView(data, start));
    if (_partial.length > _maxLineLength) {
      _error ??= SmtpException(SmtpErrorKind.protocol, '$host is not answering like a mail server.');
      destroy();
    }
    _signal();
  }

  void _onError(Object error) {
    _error ??= error;
    _signal();
  }

  void _onDone() {
    _closed = true;
    _signal();
  }

  void _signal() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Returns the next line (without CRLF), waiting at most until [deadline].
  Future<String> readLine(DateTime deadline) async {
    while (_lines.isEmpty) {
      final error = _error;
      if (error != null) throw _lost(error);
      if (_closed || _destroyed) throw _lost(null);
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw _timeout();
      final wake = _wake = Completer<void>();
      try {
        await wake.future.timeout(remaining);
      } on TimeoutException {
        throw _timeout();
      }
    }
    return _lines.removeFirst();
  }

  /// Whether unread bytes are buffered. After the server accepts STARTTLS
  /// nothing may follow its reply in plain text; anything that does was
  /// injected by someone on the path (CVE-2011-0411 and friends).
  bool get hasBufferedInput => _lines.isNotEmpty || _partial.isNotEmpty;

  /// Sends one command line.
  void writeLine(String line) => write(utf8.encode('$line\r\n'));

  /// Sends raw bytes.
  void write(List<int> bytes) {
    final error = _error;
    if (error != null) throw _lost(error);
    if (_closed || _destroyed) throw _lost(null);
    try {
      _socket.add(bytes);
    } on Object catch (e) {
      throw _lost(e);
    }
  }

  /// Waits until everything written has been handed to the OS.
  Future<void> flush(DateTime deadline) async {
    final remaining = deadline.difference(DateTime.now());
    try {
      await _socket.flush().timeout(remaining > Duration.zero ? remaining : Duration.zero);
    } on TimeoutException {
      throw _timeout();
    } on SmtpException {
      rethrow;
    } on Object catch (e) {
      throw _lost(e);
    }
  }

  /// Starts TLS on the current connection. The caller verifies
  /// [hasBufferedInput] first.
  Future<void> upgrade({
    required SecurityContext? context,
    required bool Function(X509Certificate certificate) onBadCertificate,
  }) async {
    _subscription.pause();
    _socket = await SecureSocket.secure(_socket, host: host, context: context, onBadCertificate: onBadCertificate);
    if (_destroyed) {
      _socket.destroy();
      throw _lost(null);
    }
    _attach();
  }

  /// Closes the write side and waits briefly for the server to close.
  Future<void> close() async {
    if (_destroyed) return;
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Closing is best effort.
    }
    destroy();
  }

  /// Tears the connection down immediately. Pending reads fail.
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _socket.destroy();
    _signal();
  }

  SmtpException _timeout() =>
      SmtpException(SmtpErrorKind.timeout, 'The outgoing mail server $host did not respond in time.');

  SmtpException _lost(Object? cause) {
    if (cause is SmtpException) return cause;
    return SmtpException(
      SmtpErrorKind.connectionLost,
      'The connection to the outgoing mail server $host was interrupted.',
      cause: cause,
    );
  }
}
