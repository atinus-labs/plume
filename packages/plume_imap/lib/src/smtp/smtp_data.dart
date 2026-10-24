import 'dart:typed_data';

const _cr = 0x0D;
const _lf = 0x0A;
const _dot = 0x2E;

/// A message prepared for the SMTP DATA command.
final class SmtpPayload {
  const SmtpPayload._(this.bytes, {required this.has8BitBody, required this.has8BitHeaders});

  /// The message with CRLF line endings, dot-stuffed (RFC 5321 section
  /// 4.5.2), and terminated by `CRLF.CRLF`.
  final Uint8List bytes;

  /// The message contains bytes above 0x7F, so the server must accept
  /// 8-bit data (8BITMIME).
  final bool has8BitBody;

  /// The header section contains raw UTF-8 (RFC 6532), which needs
  /// SMTPUTF8.
  final bool has8BitHeaders;

  /// Encodes [message] for DATA.
  ///
  /// Bare CR and bare LF become CRLF (mail servers reject or mangle bare
  /// line feeds, and bare CRs are a smuggling vector), a line starting with
  /// "." gets a second "." so it cannot end the transmission early, and a
  /// final CRLF is added when missing. Works on bytes, which is safe for
  /// UTF-8 because CR, LF and "." never occur inside multi-byte sequences.
  factory SmtpPayload.encode(Uint8List message) {
    // Two passes: measure, then fill, so a large attachment is not copied
    // into a growable list.
    var length = 0;
    var has8Bit = false;
    var headers8Bit = false;
    var inHeaders = true;
    var lineLength = 0;
    _scan(message, (byte) {
      if (byte == null) {
        length += 2;
        if (inHeaders && lineLength == 0) inHeaders = false;
        lineLength = 0;
        return;
      }
      length++;
      lineLength++;
      if (byte >= 0x80) {
        has8Bit = true;
        if (inHeaders) headers8Bit = true;
      }
    });
    final out = Uint8List(length + 3);
    var i = 0;
    _scan(message, (byte) {
      if (byte == null) {
        out[i++] = _cr;
        out[i++] = _lf;
      } else {
        out[i++] = byte;
      }
    });
    out[i++] = _dot;
    out[i++] = _cr;
    out[i++] = _lf;
    return SmtpPayload._(Uint8List.sublistView(out, 0, i), has8BitBody: has8Bit, has8BitHeaders: headers8Bit);
  }

  /// Calls [emit] for every output byte, with null standing for a line
  /// break, after normalizing line endings and dot-stuffing.
  static void _scan(Uint8List data, void Function(int? byte) emit) {
    var lineStart = true;
    for (var i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == _cr) {
        if (i + 1 < data.length && data[i + 1] == _lf) i++;
        emit(null);
        lineStart = true;
      } else if (b == _lf) {
        emit(null);
        lineStart = true;
      } else {
        if (lineStart && b == _dot) emit(_dot);
        emit(b);
        lineStart = false;
      }
    }
    if (!lineStart) emit(null);
  }
}
