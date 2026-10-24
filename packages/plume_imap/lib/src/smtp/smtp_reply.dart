/// One SMTP server reply (RFC 5321 section 4.2), possibly spanning several
/// lines, e.g.
///
/// ```text
/// 534-5.7.9 Application-specific password required. Learn more at
/// 534 5.7.9  https://support.google.com/mail/?p=InvalidSecondFactor
/// ```
final class SmtpReply {
  const SmtpReply(this.code, this.lines);

  /// The three-digit reply code.
  final int code;

  /// The text of each line, without the code and separator.
  final List<String> lines;

  static final RegExp _enhanced = RegExp(r'^([245]\.\d{1,3}\.\d{1,3})(?:\s+|$)');

  /// The RFC 3463 enhanced status code (`5.7.9`) from the first line, when
  /// the server sends them.
  String? get enhancedCode => lines.isEmpty ? null : _enhanced.firstMatch(lines.first)?.group(1);

  /// The human-readable text: all lines joined, with the enhanced status
  /// codes removed. This is what the user gets to see.
  String get message => lines.map((l) => l.replaceFirst(_enhanced, '').trim()).where((l) => l.isNotEmpty).join(' ');

  /// 2xx and 3xx: the command was accepted (3xx asks for more input).
  bool get isPositive => code >= 200 && code < 400;

  /// 4xx: try again later.
  bool get isTransient => code >= 400 && code < 500;

  /// 5xx: retrying the same thing will fail again.
  bool get isPermanent => code >= 500;

  @override
  String toString() => '$code ${lines.join(' / ')}';
}

/// Accumulates reply lines until a complete [SmtpReply] is available.
final class SmtpReplyParser {
  final List<String> _lines = [];
  int? _code;

  static final RegExp _line = RegExp(r'^(\d{3})([ -]|$)(.*)$');

  /// Most servers send a handful of lines; anything beyond this is not an
  /// SMTP server (or a hostile one).
  static const maxLines = 1000;

  /// Adds one line (without CRLF). Returns the reply when [line] was its
  /// last line, null when more lines follow. Throws [FormatException] when
  /// [line] is not an SMTP reply line.
  SmtpReply? add(String line) {
    final match = _line.firstMatch(line);
    if (match == null) throw FormatException('Not an SMTP reply', line);
    final code = int.parse(match.group(1)!);
    // RFC 5321 requires the same code on every line; trust the last one if
    // a server disagrees with itself.
    _code = code;
    _lines.add(match.group(3)!);
    if (match.group(2) == '-') {
      if (_lines.length >= maxLines) throw FormatException('SMTP reply too long', line);
      return null;
    }
    final reply = SmtpReply(_code!, List.unmodifiable(_lines));
    _lines.clear();
    _code = null;
    return reply;
  }

  /// True when part of a multi-line reply has been read.
  bool get isPartial => _lines.isNotEmpty;
}
