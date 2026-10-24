/// Escapes plain text for a notification body on servers that advertise
/// `body-markup`. The spec's markup is a small XML subset, so only `&`, `<`
/// and `>` are significant in text content.
String escapeNotificationMarkup(String text) {
  if (!text.contains(RegExp('[&<>]'))) return text;
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x26: // &
        buffer.write('&amp;');
      case 0x3C: // <
        buffer.write('&lt;');
      case 0x3E: // >
        buffer.write('&gt;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

final _tag = RegExp(r'<[^>]*>');
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

/// Converts a marked-up body to plain text for servers without `body-markup`:
/// drops tags (keeping `<br>` as a newline) and decodes entities.
String stripNotificationMarkup(String markup) {
  final withBreaks = markup.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  return withBreaks.replaceAll(_tag, '').replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x')
        ? int.tryParse(e.substring(2), radix: 16)
        : int.tryParse(e.substring(1));
    if (code == null || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  });
}
