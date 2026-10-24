/// Parser for the local search syntax, producing an FTS5 expression plus
/// message-level filters.
///
/// Supported:
///  * plain words (all must match; the word being typed is prefix matched),
///  * "quoted phrases",
///  * `from:`, `to:` (to, cc and bcc), `subject:` with a word or a quoted phrase,
///  * `has:attachment`, `is:unread`, `is:read`, `is:starred`/`is:flagged`,
///    `is:draft`,
///  * `in:<role or mailbox name>` (`in:inbox`, `in:sent`, `in:spam`,
///    `in:Work`...), `label:<name>`, `category:<name>`, `in:anywhere`,
///  * `-term` / `-from:x` to exclude matches.
///
/// Unknown `word:value` tokens are searched as text.
final class SearchQuery {
  const SearchQuery._({
    this.match,
    this.exclude,
    this.isRead,
    this.flagged = false,
    this.hasAttachment = false,
    this.draft = false,
    this.mailboxes = const [],
    this.categories = const [],
    this.anywhere = false,
  });

  /// FTS5 expression every result message must match, or null.
  final String? match;

  /// FTS5 expression; messages matching it are excluded.
  final String? exclude;

  /// `is:unread` → false, `is:read` → true.
  final bool? isRead;
  final bool flagged;
  final bool hasAttachment;
  final bool draft;

  /// Lowercased `in:`/`label:` values, roles already normalised
  /// (`spam` → `junk`...).
  final List<String> mailboxes;

  /// Lowercased `category:` values.
  final List<String> categories;

  /// `in:anywhere`: include trash and junk.
  final bool anywhere;

  bool get isEmpty =>
      match == null &&
      exclude == null &&
      isRead == null &&
      !flagged &&
      !hasAttachment &&
      !draft &&
      mailboxes.isEmpty &&
      categories.isEmpty;

  /// Whether trash and junk are searched (explicitly asked for). Otherwise
  /// they are excluded, like in Gmail.
  bool get includesTrashOrJunk => anywhere || mailboxes.any((m) => m == 'trash' || m == 'junk');

  static final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _operator = RegExp(r'([A-Za-z]+):');

  static const _roleAliases = {
    'spam': 'junk',
    'junk': 'junk',
    'trash': 'trash',
    'bin': 'trash',
    'deleted': 'trash',
    'draft': 'drafts',
    'drafts': 'drafts',
    'sent': 'sent',
    'inbox': 'inbox',
    'important': 'important',
    'archive': 'archive',
    'scheduled': 'scheduled',
  };

  static SearchQuery parse(String input) {
    final positives = <String>[];
    final negatives = <String>[];
    bool? isRead;
    var flagged = false;
    var hasAttachment = false;
    var draft = false;
    var anywhere = false;
    final mailboxes = <String>[];
    final categories = <String>[];

    final tokens = _tokenize(input);
    for (var t = 0; t < tokens.length; t++) {
      final token = tokens[t];
      // Prefix-match the token being typed: the last one, when the input does
      // not end with whitespace or a closing quote.
      final prefix = t == tokens.length - 1 && token.touchesEnd && !token.closedQuote;
      String? column;
      switch (token.op) {
        case null:
          break;
        case 'from':
          column = 'sender';
        case 'to' || 'cc' || 'bcc':
          column = 'recipients';
        case 'subject':
          column = 'subject';
        case 'is':
          switch (token.value.toLowerCase()) {
            case 'unread':
              isRead = token.negated;
            case 'read':
              isRead = !token.negated;
            case 'starred' || 'flagged':
              if (!token.negated) flagged = true;
            case 'draft':
              if (!token.negated) draft = true;
          }
          continue;
        case 'has':
          final v = token.value.toLowerCase();
          if (!token.negated && (v == 'attachment' || v == 'attachments')) hasAttachment = true;
          continue;
        case 'in' || 'label':
          final v = token.value.toLowerCase().trim();
          if (token.negated || v.isEmpty) continue;
          if (v == 'anywhere' || v == 'all') {
            anywhere = true;
          } else if (v == 'starred' || v == 'flagged') {
            flagged = true;
          } else {
            mailboxes.add(token.op == 'in' ? (_roleAliases[v] ?? v) : v);
          }
          continue;
        case 'category':
          final v = token.value.toLowerCase().trim();
          if (!token.negated && v.isNotEmpty) categories.add(v == 'personal' ? 'primary' : v);
          continue;
        default:
          // Unknown operator: search the whole token as text.
          final text = '${token.op}:${token.value}';
          final term = _phrase(text, prefix: prefix);
          if (term != null) (token.negated ? negatives : positives).add(term);
          continue;
      }
      final term = _phrase(token.value, prefix: prefix && token.value.length >= 2);
      if (term == null) continue;
      final expr = column == null ? term : '{$column} : $term';
      (token.negated ? negatives : positives).add(expr);
    }

    return SearchQuery._(
      match: positives.isEmpty ? null : positives.join(' '),
      exclude: negatives.isEmpty ? null : negatives.join(' OR '),
      isRead: isRead,
      flagged: flagged,
      hasAttachment: hasAttachment,
      draft: draft,
      mailboxes: mailboxes,
      categories: categories,
      anywhere: anywhere,
    );
  }

  /// An FTS5 string token for [text] (tokenized by the index tokenizer), or
  /// null when it contains nothing searchable.
  static String? _phrase(String text, {required bool prefix}) {
    if (!_wordChar.hasMatch(text)) return null;
    return '"${text.replaceAll('"', '""')}"${prefix ? '*' : ''}';
  }

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    final n = input.length;
    var i = 0;
    bool isSpace(int k) => input.codeUnitAt(k) <= 0x20 || input.codeUnitAt(k) == 0xA0;
    while (i < n) {
      while (i < n && isSpace(i)) {
        i++;
      }
      if (i >= n) break;
      var negated = false;
      if (input.codeUnitAt(i) == 0x2D /* - */ && i + 1 < n && !isSpace(i + 1)) {
        negated = true;
        i++;
      }
      String? op;
      final m = _operator.matchAsPrefix(input, i);
      if (m != null) {
        op = m.group(1)!.toLowerCase();
        i = m.end;
      }
      String value;
      var closedQuote = false;
      if (i < n && input.codeUnitAt(i) == 0x22 /* " */ ) {
        final end = input.indexOf('"', i + 1);
        if (end < 0) {
          value = input.substring(i + 1);
          i = n;
        } else {
          value = input.substring(i + 1, end);
          closedQuote = true;
          i = end + 1;
        }
      } else {
        final start = i;
        while (i < n && !isSpace(i)) {
          i++;
        }
        value = input.substring(start, i);
      }
      tokens.add(_Token(op, value, negated: negated, closedQuote: closedQuote, touchesEnd: i >= n));
    }
    return tokens;
  }
}

final class _Token {
  const _Token(this.op, this.value, {required this.negated, required this.closedQuote, required this.touchesEnd});

  final String? op;
  final String value;
  final bool negated;
  final bool closedQuote;
  final bool touchesEnd;
}
