import 'dart:convert';
import 'dart:typed_data';

import 'imap_exception.dart';

/// A parsed IMAP data item (RFC 3501 section 4).
sealed class ImapValue {
  const ImapValue();

  /// The value as text: atom text, decoded string, or null for NIL and
  /// lists.
  String? get text => null;

  /// The value as a number (atoms only), else null.
  int? get asInt => null;

  /// The items of a list, else empty.
  List<ImapValue> get items => const [];

  bool get isNil => false;
}

/// An atom, number, flag (`\Seen`) or section key (`BODY[1.2]<0>`).
final class ImapAtom extends ImapValue {
  const ImapAtom(this.value);

  final String value;

  @override
  String get text => value;

  @override
  int? get asInt => int.tryParse(value);

  @override
  String toString() => value;
}

/// A quoted string or literal. [bytes] are exactly what the server sent.
final class ImapString extends ImapValue {
  const ImapString(this.bytes, {this.isLiteral = false});

  final Uint8List bytes;
  final bool isLiteral;

  /// UTF-8 when the bytes are valid UTF-8 (RFC 6855 servers and raw 8-bit
  /// headers), Latin-1 otherwise, so that nothing is lost.
  @override
  String get text => decodeImapText(bytes);

  @override
  int? get asInt => int.tryParse(latin1.decode(bytes));

  @override
  String toString() => isLiteral ? '{${bytes.length}}' : '"$text"';
}

/// `NIL`.
final class ImapNil extends ImapValue {
  const ImapNil();

  @override
  bool get isNil => true;

  @override
  String toString() => 'NIL';
}

/// A parenthesized list.
final class ImapList extends ImapValue {
  const ImapList(this.items);

  @override
  final List<ImapValue> items;

  @override
  String toString() => '(${items.join(' ')})';
}

/// Decodes protocol text bytes: UTF-8 if valid, else Latin-1.
String decodeImapText(List<int> bytes) {
  var ascii = true;
  for (final b in bytes) {
    if (b >= 0x80) {
      ascii = false;
      break;
    }
  }
  if (ascii) return String.fromCharCodes(bytes);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// A `[CODE args]` response code.
final class ResponseCode {
  const ResponseCode(this.name, this.args);

  /// Upper-cased name, e.g. `UIDVALIDITY`.
  final String name;

  /// The raw text after the name (may be empty).
  final String args;

  /// [args] as a number (`[UIDNEXT 4392]`).
  int? get number => int.tryParse(args.trim());

  /// [args] split on spaces (`[APPENDUID 38505 3955]`).
  List<String> get words => args.trim().isEmpty ? const [] : args.trim().split(RegExp(r'\s+'));

  @override
  String toString() => args.isEmpty ? '[$name]' : '[$name $args]';
}

enum ImapResponseKind { tagged, untagged, continuation }

/// One complete server response.
final class ImapResponse {
  const ImapResponse({
    required this.kind,
    this.tag,
    this.status,
    this.code,
    this.text = '',
    this.number,
    this.type = '',
    this.data = const [],
  });

  final ImapResponseKind kind;

  /// The tag of a tagged response.
  final String? tag;

  /// `OK`, `NO`, `BAD`, `BYE` or `PREAUTH` for status responses, else null.
  final String? status;
  final ResponseCode? code;

  /// Human-readable text of a status response, or the text of a
  /// continuation request.
  final String text;

  /// The leading number of `* 12 EXISTS` / `* 3 FETCH (...)`.
  final int? number;

  /// Upper-cased response type for untagged data: `EXISTS`, `FETCH`,
  /// `LIST`, `CAPABILITY`... For status responses it equals [status].
  final String type;

  /// The values after the type.
  final List<ImapValue> data;

  bool get isTagged => kind == ImapResponseKind.tagged;
  bool get isUntagged => kind == ImapResponseKind.untagged;
  bool get isContinuation => kind == ImapResponseKind.continuation;
  bool get isOk => status == 'OK';

  @override
  String toString() => switch (kind) {
        ImapResponseKind.continuation => '+ $text',
        ImapResponseKind.tagged => '$tag $status ${code ?? ''}$text',
        ImapResponseKind.untagged => status != null
            ? '* $status ${code ?? ''}$text'
            : '* ${number == null ? '' : '$number '}$type ${data.join(' ')}',
      };
}

/// A server response split at its literals: `lines[i]` is followed by
/// `literals[i]`; the last line has no literal after it.
final class RawResponse {
  const RawResponse(this.lines, this.literals);

  final List<String> lines;
  final List<Uint8List> literals;
}

/// Incremental framer for IMAP server output (RFC 3501 sections 4.3, 7).
///
/// Bytes arrive in arbitrary chunks. A response is a CRLF-terminated line,
/// except that a line ending in a literal marker `{n}` (or `{n+}`) is
/// followed by exactly n raw bytes and then the rest of the response.
/// Literal bytes are never interpreted as protocol text. Line length and
/// literal size are bounded so a hostile server cannot exhaust memory.
final class ImapResponseReader {
  ImapResponseReader({this.maxLineLength = 16 << 20, this.maxLiteralSize = 256 << 20});

  final int maxLineLength;
  final int maxLiteralSize;

  final BytesBuilder _line = BytesBuilder(copy: false);
  final List<String> _lines = [];
  final List<Uint8List> _literals = [];
  BytesBuilder? _literal;
  int _literalRemaining = 0;
  int _textLength = 0;

  static final RegExp _literalMarker = RegExp(r'~?\{(\d{1,10})\+?\}$');

  /// Bytes received so far for the response being assembled (for
  /// progress-based timeouts and diagnostics).
  int get pendingBytes => _line.length + _textLength + (_literal?.length ?? 0);

  /// Feeds [chunk] and returns the responses it completed, in order.
  /// Throws [ImapProtocolException] on oversized lines or literals.
  List<RawResponse> add(List<int> chunk) {
    final out = <RawResponse>[];
    var i = 0;
    while (i < chunk.length) {
      if (_literalRemaining > 0) {
        final take = (chunk.length - i) < _literalRemaining ? chunk.length - i : _literalRemaining;
        _literal!.add(chunk is Uint8List ? Uint8List.sublistView(chunk, i, i + take) : chunk.sublist(i, i + take));
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
        _line.add(chunk is Uint8List ? Uint8List.sublistView(chunk, i) : chunk.sublist(i));
        _checkLength();
        break;
      }
      _line.add(chunk is Uint8List ? Uint8List.sublistView(chunk, i, lf) : chunk.sublist(i, lf));
      i = lf + 1;
      _checkLength();
      var bytes = _line.takeBytes();
      if (bytes.isNotEmpty && bytes.last == 0x0D) bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      final segment = latin1.decode(bytes);
      _lines.add(segment);
      _textLength += segment.length;
      final marker = _literalMarker.firstMatch(segment);
      if (marker != null) {
        final size = int.parse(marker.group(1)!);
        if (size > maxLiteralSize) throw ImapProtocolException('Literal of $size bytes exceeds the limit');
        if (size > 0) {
          _literalRemaining = size;
          _literal = BytesBuilder(copy: true);
        } else {
          _literals.add(Uint8List(0));
        }
        continue; // The response continues after the literal.
      }
      out.add(RawResponse(List.unmodifiable(_lines), List.unmodifiable(_literals)));
      _lines.clear();
      _literals.clear();
      _textLength = 0;
    }
    return out;
  }

  void _checkLength() {
    if (_line.length + _textLength > maxLineLength) {
      throw ImapProtocolException('Response line exceeds $maxLineLength bytes');
    }
  }
}

/// Parses framed responses into [ImapResponse]s. Lenient: unexpected
/// characters become part of atoms rather than failing the response.
final class ImapParser {
  ImapParser._(this._raw);

  final RawResponse _raw;
  int _line = 0;
  int _pos = 0;

  String get _s => _raw.lines[_line];

  static ImapResponse parse(RawResponse raw) => ImapParser._(raw)._response();

  ImapResponse _response() {
    final first = _s;
    if (first.startsWith('+')) {
      _pos = first.length > 1 && first[1] == ' ' ? 2 : 1;
      return ImapResponse(kind: ImapResponseKind.continuation, text: _restOfLine());
    }
    if (first.startsWith('* ')) {
      _pos = 2;
      final head = _word();
      final n = int.tryParse(head);
      if (n != null) {
        final type = _word().toUpperCase();
        return ImapResponse(kind: ImapResponseKind.untagged, number: n, type: type, data: _values());
      }
      final type = head.toUpperCase();
      if (_statusWords.contains(type)) return _status(ImapResponseKind.untagged, null, type);
      return ImapResponse(kind: ImapResponseKind.untagged, type: type, data: _values());
    }
    final tag = _word();
    final status = _word().toUpperCase();
    if (tag.isEmpty || !_statusWords.contains(status)) {
      throw ImapProtocolException('Unparseable response "${_preview(first)}"');
    }
    return _status(ImapResponseKind.tagged, tag, status);
  }

  static const _statusWords = {'OK', 'NO', 'BAD', 'BYE', 'PREAUTH'};

  ImapResponse _status(ImapResponseKind kind, String? tag, String status) {
    _skipSpaces();
    ResponseCode? code;
    final s = _s;
    if (_pos < s.length && s[_pos] == '[') {
      final close = _matchingBracket(s, _pos);
      final inner = s.substring(_pos + 1, close < 0 ? s.length : close);
      final space = inner.indexOf(' ');
      code = ResponseCode(
        (space < 0 ? inner : inner.substring(0, space)).toUpperCase(),
        space < 0 ? '' : inner.substring(space + 1),
      );
      _pos = close < 0 ? s.length : close + 1;
      _skipSpaces();
    }
    return ImapResponse(kind: kind, tag: tag, status: status, code: code, text: _restOfLine(), type: status);
  }

  /// Index of the `]` closing the `[` at [open], skipping nested brackets
  /// and quoted strings; -1 if unterminated.
  static int _matchingBracket(String s, int open) {
    var depth = 0;
    var quoted = false;
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (quoted) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          quoted = false;
        }
        continue;
      }
      if (c == '"') {
        quoted = true;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The rest of the response as text (literals inlined as text).
  String _restOfLine() {
    final sb = StringBuffer(_lineText(_s.substring(_pos.clamp(0, _s.length))));
    while (_line < _raw.literals.length && _line + 1 < _raw.lines.length) {
      sb.write(decodeImapText(_raw.literals[_line]));
      _line++;
      sb.write(_lineText(_s));
    }
    _pos = _s.length;
    return sb.toString();
  }

  /// Line text was decoded as Latin-1 by the reader; re-decode 8-bit text
  /// as UTF-8 when it is valid UTF-8.
  static String _lineText(String latin) => decodeImapText(latin1.encode(latin));

  String _word() {
    _skipSpaces();
    final s = _s;
    final start = _pos;
    while (_pos < s.length && s.codeUnitAt(_pos) != 0x20) {
      _pos++;
    }
    return s.substring(start, _pos);
  }

  void _skipSpaces() {
    final s = _s;
    while (_pos < s.length && s.codeUnitAt(_pos) == 0x20) {
      _pos++;
    }
  }

  bool get _atLineEnd => _pos >= _s.length;

  /// Values until the end of the response.
  List<ImapValue> _values() {
    final out = <ImapValue>[];
    while (true) {
      _skipSpaces();
      if (_atLineEnd) {
        if (!_continueAfterLiteralMarker()) break;
        continue;
      }
      final v = _value();
      if (v != null) out.add(v);
    }
    return out;
  }

  /// At the end of a line that ended in a literal marker that was not
  /// consumed (should not happen), moves on to the next line.
  bool _continueAfterLiteralMarker() {
    if (_line + 1 >= _raw.lines.length) return false;
    _line++;
    _pos = 0;
    return true;
  }

  /// Parses one value; returns null for a stray `)` (skipped).
  ImapValue? _value() {
    final s = _s;
    final c = s.codeUnitAt(_pos);
    switch (c) {
      case 0x28: // (
        _pos++;
        final items = <ImapValue>[];
        while (true) {
          _skipSpaces();
          if (_atLineEnd) {
            if (!_continueAfterLiteralMarker()) return ImapList(items); // Unterminated: lenient.
            continue;
          }
          if (_s.codeUnitAt(_pos) == 0x29) {
            _pos++;
            return ImapList(items);
          }
          final v = _value();
          if (v != null) items.add(v);
        }
      case 0x29: // ) without (
        _pos++;
        return null;
      case 0x22: // "
        return _quoted();
      case 0x7B: // {
      case 0x7E: // ~{ (literal8)
        final literal = _literal();
        if (literal != null) return literal;
        return _atom();
      default:
        return _atom();
    }
  }

  ImapString _quoted() {
    final s = _s;
    _pos++; // opening quote
    final bytes = <int>[];
    while (_pos < s.length) {
      final c = s.codeUnitAt(_pos);
      if (c == 0x5C && _pos + 1 < s.length) {
        bytes.add(s.codeUnitAt(_pos + 1));
        _pos += 2;
        continue;
      }
      if (c == 0x22) {
        _pos++;
        break;
      }
      bytes.add(c);
      _pos++;
    }
    return ImapString(Uint8List.fromList(bytes));
  }

  /// A literal marker must end the current line; its bytes are the next
  /// literal, and parsing continues on the next line.
  ImapString? _literal() {
    final s = _s;
    final m = RegExp(r'~?\{(\d+)\+?\}$').matchAsPrefix(s, _pos);
    if (m == null || m.end != s.length || _line >= _raw.literals.length) return null;
    final bytes = _raw.literals[_line];
    _line++;
    _pos = 0;
    return ImapString(bytes, isLiteral: true);
  }

  /// An atom, extended with a bracketed section and partial origin for
  /// FETCH keys like `BODY[HEADER.FIELDS (DATE FROM)]<0>`.
  ImapValue _atom() {
    final s = _s;
    final start = _pos;
    while (_pos < s.length) {
      final c = s.codeUnitAt(_pos);
      if (c == 0x5B) {
        // [ section ]
        final close = _matchingBracket(s, _pos);
        _pos = close < 0 ? s.length : close + 1;
        continue;
      }
      if (c == 0x20 || c == 0x28 || c == 0x29 || c == 0x22 || c == 0x7B) break;
      _pos++;
    }
    if (_pos == start) {
      // A lone special character: consume it so parsing advances.
      _pos++;
      return ImapAtom(s.substring(start, _pos));
    }
    final word = s.substring(start, _pos);
    if (word.length == 3 && word.toUpperCase() == 'NIL') return const ImapNil();
    return ImapAtom(word);
  }

  static String _preview(String s) => s.length > 80 ? '${s.substring(0, 80)}...' : s;
}
