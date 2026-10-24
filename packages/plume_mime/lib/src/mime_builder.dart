import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';

import 'codecs.dart';
import 'header_value.dart';
import 'rfc2047.dart';
import 'text.dart';

/// An encoded RFC 5322 message.
final class BuiltMessage {
  const BuiltMessage(this.bytes, this.messageId);

  /// The message, 7-bit clean (all non-ASCII content is encoded).
  final Uint8List bytes;

  /// The generated `Message-ID`, with angle brackets.
  final String messageId;

  /// base64url of [bytes] (the Gmail API's `raw` field).
  String get raw => base64Url.encode(bytes);

  @override
  String toString() => utf8.decode(bytes);
}

/// Builds outgoing messages (send and drafts).
///
/// * Headers: Date, From, To, Cc, Bcc, Subject, Message-ID (with the
///   sender's domain), In-Reply-To, References, MIME-Version. Non-ASCII
///   header text and display names use RFC 2047 encoded-words; long
///   headers are folded at 78 columns.
/// * Body: text/plain, plus text/html as multipart/alternative.
/// * Inline images (attachments with a Content-ID, when there is HTML)
///   form a multipart/related with the body; other attachments wrap
///   everything in multipart/mixed.
/// * Text is sent as 7bit when it is ASCII with short lines, otherwise as
///   base64; attachments are base64. Base64 is wrapped at 76 characters.
///
/// Bcc is kept in the output by default: the Gmail API reads it to deliver
/// and strips it from the copies recipients get, and drafts and Sent copies
/// need it to round-trip. Pass `includeBcc: false` for SMTP submission,
/// where the envelope carries the Bcc recipients instead.
final class MimeMessageBuilder {
  MimeMessageBuilder({Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  /// Encodes [message]. [messageId] and [date] default to a new id and the
  /// current time; pass both to build byte-identical variants (with and
  /// without Bcc) of the same message.
  BuiltMessage build(OutgoingMessage message, {String? messageId, DateTime? date, bool includeBcc = true}) {
    final id = messageId ?? generateMessageId(message.from.email);
    final headers = StringBuffer()
      ..write(_fold('Date', [formatRfc5322Date(date ?? _clock())], ' '))
      ..write(_addressHeader('From', [message.from]));
    if (message.to.isNotEmpty) headers.write(_addressHeader('To', message.to));
    if (message.cc.isNotEmpty) headers.write(_addressHeader('Cc', message.cc));
    if (includeBcc && message.bcc.isNotEmpty) headers.write(_addressHeader('Bcc', message.bcc));
    headers
      ..write(_unstructured('Subject', message.subject))
      ..write(_fold('Message-ID', [id], ' '));
    final inReplyTo = message.inReplyTo;
    if (inReplyTo != null && inReplyTo.trim().isNotEmpty) {
      headers.write(_fold('In-Reply-To', [_angle(inReplyTo)], ' '));
    }
    if (message.references.isNotEmpty) {
      headers.write(_fold('References', [for (final r in message.references) _angle(r)], ' '));
    }
    headers.write('MIME-Version: 1.0\r\n');

    final root = _bodyTree(message);
    final out = StringBuffer()
      ..write(headers)
      ..write(_serialize(root));
    return BuiltMessage(Uint8List.fromList(utf8.encode(out.toString())), id);
  }

  /// `<time.random@domain>` using the sender's domain.
  String generateMessageId(String fromEmail) {
    final at = fromEmail.lastIndexOf('@');
    var domain = at >= 0 ? fromEmail.substring(at + 1).toLowerCase() : '';
    domain = domain.replaceAll(RegExp(r'[^a-z0-9.\-]'), '');
    if (domain.isEmpty) domain = 'plume.local';
    final rand = List<int>.generate(10, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '<${_clock().millisecondsSinceEpoch.toRadixString(36)}.$rand@$domain>';
  }

  _Part _bodyTree(OutgoingMessage m) {
    final text = _textPart('text/plain', m.textBody);
    final html = m.htmlBody == null ? null : _textPart('text/html', m.htmlBody!);
    var body = html == null ? text : _Part.multipart('alternative', [text, html], _boundary());

    final inline = html == null ? const <OutgoingAttachment>[] : m.attachments.where((a) => a.contentId != null).toList();
    final regular = m.attachments.where((a) => !inline.contains(a)).toList();
    if (inline.isNotEmpty) {
      body = _Part.multipart('related', [body, for (final a in inline) _attachmentPart(a, inline: true)], _boundary(),
          extraParams: '; type="${html == null ? 'text/plain' : 'multipart/alternative'}"');
    }
    if (regular.isNotEmpty) {
      body = _Part.multipart('mixed', [body, for (final a in regular) _attachmentPart(a, inline: false)], _boundary());
    }
    return body;
  }

  _Part _textPart(String mime, String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', '\r\n');
    final isAscii = normalized.codeUnits.every((c) => c < 0x80);
    final shortLines = normalized.split('\r\n').every((l) => l.length <= 998);
    if (isAscii && shortLines) {
      return _Part.leaf([
        'Content-Type: $mime; charset="UTF-8"',
        'Content-Transfer-Encoding: 7bit',
      ], normalized);
    }
    return _Part.leaf([
      'Content-Type: $mime; charset="UTF-8"',
      'Content-Transfer-Encoding: base64',
    ], encodeBase64Wrapped(utf8.encode(normalized)));
  }

  _Part _attachmentPart(OutgoingAttachment a, {required bool inline}) {
    final mime = a.mimeType.trim().isEmpty ? 'application/octet-stream' : a.mimeType.trim().toLowerCase();
    return _Part.leaf([
      'Content-Type: $mime;\r\n ${encodeHeaderParam('name', a.filename)}',
      'Content-Disposition: ${inline ? 'inline' : 'attachment'};\r\n ${encodeHeaderParam('filename', a.filename)}',
      if (a.contentId != null) 'Content-ID: ${_angle(a.contentId!)}',
      'Content-Transfer-Encoding: base64',
    ], encodeBase64Wrapped(a.bytes));
  }

  String _boundary() {
    final rand = List<int>.generate(12, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // "=_" cannot occur in base64 or quoted-printable output.
    return '=_plume_$rand';
  }

  String _serialize(_Part part) {
    final sb = StringBuffer();
    if (part.children.isEmpty) {
      for (final h in part.headers) {
        sb.write('$h\r\n');
      }
      sb
        ..write('\r\n')
        ..write(part.body)
        ..write('\r\n');
      return sb.toString();
    }
    sb
      ..write('Content-Type: multipart/${part.subtype};\r\n boundary="${part.boundary}"${part.extraParams}\r\n')
      ..write('\r\n');
    for (final child in part.children) {
      sb
        ..write('--${part.boundary}\r\n')
        ..write(_serialize(child));
    }
    sb.write('--${part.boundary}--\r\n');
    return sb.toString();
  }

  /// Address lists fold after commas and, for long entries, between the
  /// display name and the angle-addr.
  String _addressHeader(String name, List<Address> addresses) {
    final tokens = <(String, String)>[];
    for (final a in addresses) {
      final formatted = formatAddress(a);
      final sep = tokens.isEmpty ? '' : ', ';
      final split = formatted.lastIndexOf(' <');
      if (formatted.length > 60 && split > 0) {
        tokens
          ..add((formatted.substring(0, split), sep))
          ..add((formatted.substring(split + 1), ' '));
      } else {
        tokens.add((formatted, sep));
      }
    }
    return _foldTokens(name, tokens);
  }

  String _unstructured(String name, String value) {
    final clean = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (headerNeedsEncoding(clean)) return _fold(name, encodeWords(clean), ' ');
    return _fold(name, clean.split(' '), ' ');
  }

  /// Joins [tokens] with [joiner], folding before a token when the line
  /// would exceed 78 characters.
  static String _fold(String name, List<String> tokens, String joiner) =>
      _foldTokens(name, [for (var i = 0; i < tokens.length; i++) (tokens[i], i == 0 ? '' : joiner)]);

  /// Writes `name: ` and the tokens, each preceded by its separator. When a
  /// token would push the line past 78 characters, the line is folded at
  /// that separator (its trailing whitespace becomes the fold).
  static String _foldTokens(String name, List<(String, String)> tokens) {
    final sb = StringBuffer();
    var line = '$name:';
    var first = true;
    for (final (token, separator) in tokens) {
      if (first) {
        line += ' $token';
        first = false;
        continue;
      }
      if (line.length + separator.length + token.length > 78) {
        sb
          ..write(line)
          ..write(separator.trimRight())
          ..write('\r\n');
        line = ' $token';
      } else {
        line += '$separator$token';
      }
    }
    sb
      ..write(line)
      ..write('\r\n');
    return sb.toString();
  }

  static String _angle(String id) {
    final t = id.trim();
    return t.startsWith('<') ? t : '<$t>';
  }

  /// Formats an address for a header, encoding or quoting the display name.
  static String formatAddress(Address a) {
    final name = a.name?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (name == null || name.isEmpty) return a.email;
    if (headerNeedsEncoding(name)) return '${encodeWords(name).join(' ')} <${a.email}>';
    if (RegExp(r'[()<>\[\]:;@\\,."]').hasMatch(name)) {
      return '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" <${a.email}>';
    }
    return '$name <${a.email}>';
  }
}

final class _Part {
  _Part.leaf(this.headers, this.body)
      : subtype = '',
        children = const [],
        boundary = '',
        extraParams = '';

  _Part.multipart(this.subtype, this.children, this.boundary, {this.extraParams = ''})
      : headers = const [],
        body = '';

  final List<String> headers;
  final String body;
  final String subtype;
  final List<_Part> children;
  final String boundary;
  final String extraParams;
}
