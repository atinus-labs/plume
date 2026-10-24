import 'dart:convert';
import 'dart:typed_data';

/// One complete IMAP server response: a line, possibly spanning literals.
final class ImapResponse {
  const ImapResponse(this.text, [this.literals = const []]);

  /// The response text with each literal's bytes omitted (the `{n}` markers
  /// stay in place). Decoded as Latin-1 so that arbitrary bytes are safe.
  final String text;
  final List<Uint8List> literals;

  bool get isUntagged => text.startsWith('* ');
  bool get isContinuation => text.startsWith('+');

  /// The tag of a tagged response (`A1 OK ...` → `A1`), else null.
  String? get tag {
    if (isUntagged || isContinuation) return null;
    final space = text.indexOf(' ');
    return space <= 0 ? null : text.substring(0, space);
  }

  /// The status word: `OK`, `NO`, `BAD`, `BYE`... (upper-cased). For
  /// untagged data responses this is the second token, e.g. a number.
  String? get status {
    final parts = text.split(' ');
    if (parts.length < 2) return null;
    return parts[1].toUpperCase();
  }

  @override
  String toString() => text;
}

/// Thrown when the server sends something the reader refuses to buffer.
final class ImapProtocolException implements Exception {
  const ImapProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ImapProtocolException: $message';
}

/// Incremental parser for IMAP server output (RFC 3501 section 4.3/7).
///
/// Bytes arrive in arbitrary chunks. A response is a CRLF-terminated line,
/// except that a line ending in a literal marker `{n}` (or `{n+}`) is
/// followed by exactly n raw bytes and then the rest of the response. The
/// reader never interprets literal bytes as protocol text, and bounds both
/// line length and literal size so a hostile server cannot exhaust memory.
final class ImapResponseReader {
  ImapResponseReader({this.maxLineLength = 1 << 20, this.maxLiteralSize = 32 << 20});

  final int maxLineLength;
  final int maxLiteralSize;

  final BytesBuilder _line = BytesBuilder(copy: false);
  final StringBuffer _text = StringBuffer();
  final List<Uint8List> _literals = [];
  BytesBuilder? _literal;
  int _literalRemaining = 0;
  int _textLength = 0;

  static final RegExp _literalMarker = RegExp(r'\{(\d{1,10})\+?\}$');

  /// Feeds [chunk] and returns the responses it completed, in order.
  /// Throws [ImapProtocolException] on oversized lines or literals.
  List<ImapResponse> add(List<int> chunk) {
    final out = <ImapResponse>[];
    var i = 0;
    while (i < chunk.length) {
      if (_literalRemaining > 0) {
        final take = (chunk.length - i) < _literalRemaining ? chunk.length - i : _literalRemaining;
        _literal!.add(chunk.sublist(i, i + take));
        _literalRemaining -= take;
        i += take;
        if (_literalRemaining == 0) {
          _literals.add(_literal!.takeBytes());
          _literal = null;
        }
        continue;
      }
      final lf = chunk.indexOf(0x0A, i);
      if (lf < 0) {
        _line.add(chunk.sublist(i));
        _checkLength();
        break;
      }
      _line.add(chunk.sublist(i, lf));
      i = lf + 1;
      _checkLength();
      var bytes = _line.takeBytes();
      if (bytes.isNotEmpty && bytes.last == 0x0D) bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      final segment = latin1.decode(bytes);
      _text.write(segment);
      _textLength += segment.length;
      final marker = _literalMarker.firstMatch(segment);
      if (marker != null) {
        final size = int.parse(marker.group(1)!);
        if (size > maxLiteralSize) throw ImapProtocolException('Literal of $size bytes exceeds the limit');
        if (size > 0) {
          _literalRemaining = size;
          _literal = BytesBuilder(copy: false);
        } else {
          _literals.add(Uint8List(0));
        }
        continue; // The response continues after the literal.
      }
      out.add(ImapResponse(_text.toString(), List.unmodifiable(_literals)));
      _text.clear();
      _textLength = 0;
      _literals.clear();
    }
    return out;
  }

  void _checkLength() {
    if (_line.length + _textLength > maxLineLength) {
      throw ImapProtocolException('Response line exceeds $maxLineLength bytes');
    }
  }
}
