import 'dart:convert';

import 'package:plume_core/plume_core.dart';

import 'addresses.dart';

/// A parsed `mailto:` URI (RFC 6068), as passed by browsers and other apps
/// when Plume is the default mail client.
///
/// Only the fields a compose window can show are kept. Every other header,
/// notably `attach` and `from`, is dropped: a web page must not be able to
/// attach local files or pick the sending identity (RFC 6068 section 7).
final class MailtoLink {
  const MailtoLink({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
  });

  /// Parses [uri], which must use the `mailto` scheme (any case). Returns
  /// null for anything else.
  ///
  /// Lenient where real links are sloppy: unescaped spaces, `mailto://`,
  /// stray `%` signs, invalid UTF-8 and `;` as an address separator are all
  /// accepted. Unlike HTML forms, `+` is a literal plus, not a space.
  static MailtoLink? tryParse(String uri) {
    final trimmed = uri.trim();
    if (trimmed.length < 7 || trimmed.substring(0, 7).toLowerCase() != 'mailto:') return null;
    var rest = trimmed.substring(7);
    if (rest.startsWith('//')) rest = rest.substring(2);
    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);

    final query = rest.indexOf('?');
    final path = query < 0 ? rest : rest.substring(0, query);
    final to = <Address>[..._addresses(_decode(path))];
    final cc = <Address>[];
    final bcc = <Address>[];
    final subject = <String>[];
    final body = <String>[];
    String? inReplyTo;

    if (query >= 0) {
      for (final field in rest.substring(query + 1).split('&')) {
        if (field.isEmpty) continue;
        final eq = field.indexOf('=');
        final name = _decode(eq < 0 ? field : field.substring(0, eq)).trim().toLowerCase();
        final value = eq < 0 ? '' : _decode(field.substring(eq + 1));
        switch (name) {
          case 'to':
            to.addAll(_addresses(value));
          case 'cc':
            cc.addAll(_addresses(value));
          case 'bcc':
            bcc.addAll(_addresses(value));
          case 'subject':
            subject.add(_singleLine(value));
          case 'body':
            body.add(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
          case 'in-reply-to':
            final id = parseMessageIdHeader(value);
            if (id != null) inReplyTo = id;
        }
      }
    }

    return MailtoLink(
      to: _dedupe(to),
      cc: _dedupe(cc),
      bcc: _dedupe(bcc),
      subject: subject.where((s) => s.isNotEmpty).join(' '),
      body: body.join('\n'),
      inReplyTo: inReplyTo,
    );
  }

  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;

  /// Plain text with `\n` line breaks.
  final String body;

  /// The `In-Reply-To` Message-ID, angle brackets included.
  final String? inReplyTo;

  bool get isEmpty => to.isEmpty && cc.isEmpty && bcc.isEmpty && subject.isEmpty && body.isEmpty;

  @override
  String toString() => 'MailtoLink(to: $to, cc: $cc, bcc: $bcc, subject: $subject)';
}

List<Address> _addresses(String value) => parseAddressHeader(value);

List<Address> _dedupe(List<Address> list) {
  final seen = <String>{};
  return [for (final a in list) if (seen.add(a.email.toLowerCase())) a];
}

final _hexPair = RegExp(r'^[0-9A-Fa-f]{2}$');

String _singleLine(String value) => value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

/// Percent-decodes [input] as UTF-8. Malformed escapes are kept literally and
/// invalid UTF-8 becomes U+FFFD instead of failing the whole link.
String _decode(String input) {
  if (!input.contains('%')) return input;
  final bytes = <int>[];
  final out = StringBuffer();
  void flush() {
    if (bytes.isEmpty) return;
    out.write(utf8.decode(bytes, allowMalformed: true));
    bytes.clear();
  }

  for (var i = 0; i < input.length; i++) {
    final ch = input.codeUnitAt(i);
    if (ch == 0x25 && i + 2 < input.length) {
      final hex = input.substring(i + 1, i + 3);
      if (_hexPair.hasMatch(hex)) {
        bytes.add(int.parse(hex, radix: 16));
        i += 2;
        continue;
      }
    }
    flush();
    out.writeCharCode(ch);
  }
  flush();
  return out.toString();
}
