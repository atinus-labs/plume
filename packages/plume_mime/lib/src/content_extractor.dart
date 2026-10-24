import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';

import 'charset.dart';
import 'header_value.dart';
import 'mime_part.dart';
import 'rfc2047.dart';
import 'text.dart';

/// The displayable content of a message: its body, attachments and the
/// inline resources that came with it.
final class ExtractedContent {
  const ExtractedContent({
    this.html,
    this.text,
    this.inlineParts = const {},
    this.attachments = const [],
    this.unresolvedBodyParts = const [],
  });

  final String? html;
  final String? text;

  /// Inline resources keyed by Content-ID (without angle brackets).
  final Map<String, Uint8List> inlineParts;
  final List<AttachmentInfo> attachments;

  /// Text body parts whose content is not in the tree ([MimePart.data] is
  /// null). Download them and extract again, passing the decoded bytes as
  /// `resolved`, keyed by [MimePart.partId].
  final List<MimePart> unresolvedBodyParts;

  MessageBody toBody() => MessageBody(html: html, text: text, inlineParts: inlineParts);
}

/// Walks a MIME tree and picks the body and attachments.
///
/// * `multipart/alternative`: the last alternative with HTML provides the
///   HTML body, the last with plain text the text body.
/// * `multipart/related`: the root part (the `start` parameter, else the
///   first part) is the body; the other parts are resources.
/// * `multipart/mixed` and others: body parts are concatenated in order and
///   everything else is an attachment.
/// * Text is decoded from the part's charset; `format=flowed` plain text is
///   unwrapped.
/// * A part with a Content-ID referenced from the HTML as `cid:` is marked
///   inline; if its bytes are in the tree, they go into
///   [ExtractedContent.inlineParts].
///
/// [resolved] supplies decoded content for parts whose [MimePart.data] is
/// null, keyed by part id.
ExtractedContent extractContent(MimePart root, {Map<String, List<int>> resolved = const {}}) {
  final walk = _Walk(resolved);
  final segments = walk.segmentsOf(root);
  final hasHtml = segments.any((s) => s.html != null);
  final hasText = segments.any((s) => s.text != null);
  final html = hasHtml ? _joinHtml(segments) : null;
  final text = hasText ? _joinText(segments) : null;

  final htmlLower = html?.toLowerCase();
  final attachments = <AttachmentInfo>[];
  final inline = <String, Uint8List>{};
  for (final a in walk.attachments) {
    final cid = a.contentId;
    final referenced = cid != null && htmlLower != null && htmlLower.contains('cid:${cid.toLowerCase()}');
    attachments.add(AttachmentInfo(
      partId: a.partId,
      providerId: a.handle,
      filename: a.filename,
      mimeType: a.mimeType,
      size: a.size,
      contentId: cid,
      isInline: referenced,
    ));
    if (referenced && a.data != null) inline[cid] = a.data!;
  }
  return ExtractedContent(
    html: html,
    text: text,
    inlineParts: inline,
    attachments: attachments,
    unresolvedBodyParts: walk.unresolved,
  );
}

/// The attachment list of a structure-only tree (no HTML available yet),
/// for message lists. Parts with a Content-ID inside `multipart/related`
/// are assumed to be referenced by the HTML and marked inline, which is
/// what [extractContent] decides for nearly all real mail once the body is
/// known.
List<AttachmentInfo> attachmentsOfStructure(MimePart root) {
  final walk = _Walk(const {});
  walk.segmentsOf(root);
  final relatedIds = <String>{};
  void collect(MimePart p, bool inRelated) {
    if (inRelated && !p.isMultipart) relatedIds.add(p.partId);
    final related = p.mimeType.toLowerCase().trim() == 'multipart/related';
    for (final c in p.parts) {
      collect(c, inRelated || related);
    }
  }

  collect(root, false);
  return [
    for (final a in walk.attachments)
      AttachmentInfo(
        partId: a.partId,
        providerId: a.handle,
        filename: a.filename,
        mimeType: a.mimeType,
        size: a.size,
        contentId: a.contentId,
        isInline: a.contentId != null && relatedIds.contains(a.partId),
      ),
  ];
}

/// The first text body part a reader would show, preferring text/plain
/// (cheaper to turn into a preview) over text/html. Null when the message
/// has no text body.
MimePart? previewPartOf(MimePart root) {
  final walk = _Walk(const {}, collectBodyParts: true);
  walk.segmentsOf(root);
  final bodies = walk.bodyParts;
  return bodies.where((p) => p.mimeType.toLowerCase() == 'text/plain').firstOrNull ?? bodies.firstOrNull;
}

final class _Segment {
  const _Segment({this.html, this.text});

  final String? html;
  final String? text;
}

final class _Attachment {
  _Attachment({
    required this.partId,
    required this.handle,
    required this.filename,
    required this.mimeType,
    required this.size,
    required this.contentId,
    required this.data,
  });

  final String partId;
  final String? handle;
  final String filename;
  final String mimeType;
  final int size;
  final String? contentId;
  final Uint8List? data;
}

final class _Walk {
  _Walk(this.resolved, {this.collectBodyParts = false});

  final Map<String, List<int>> resolved;
  final bool collectBodyParts;
  final attachments = <_Attachment>[];
  final unresolved = <MimePart>[];

  /// Body parts in display order (only with [collectBodyParts]).
  final bodyParts = <MimePart>[];

  List<_Segment> segmentsOf(MimePart part, {int depth = 0}) {
    if (depth > 32) return const []; // Defensive bound on pathological nesting.
    final mime = part.mimeType.toLowerCase().trim();
    if (mime.startsWith('multipart/')) {
      if (part.parts.isEmpty) return const [];
      switch (mime.substring('multipart/'.length)) {
        case 'alternative':
          final alternatives = [for (final c in part.parts) segmentsOf(c, depth: depth + 1)];
          List<_Segment>? htmlAlt;
          List<_Segment>? textAlt;
          for (final segs in alternatives) {
            if (segs.any((s) => s.html != null)) htmlAlt = segs;
            if (segs.any((s) => s.text != null)) textAlt = segs;
          }
          final html = htmlAlt == null ? null : _joinHtml(htmlAlt);
          final text = textAlt == null ? null : _joinText(textAlt);
          if (html == null && text == null) return const [];
          return [_Segment(html: html, text: text)];
        case 'related':
          final start = _stripAngle(HeaderValue.parse(part.header('Content-Type'))['start']);
          var root = 0;
          if (start != null) {
            final i = part.parts.indexWhere((c) => _contentId(c) == start);
            if (i >= 0) root = i;
          }
          final segs = segmentsOf(part.parts[root], depth: depth + 1);
          for (var i = 0; i < part.parts.length; i++) {
            if (i != root) _resourceOrAttachment(part.parts[i], depth + 1);
          }
          return segs;
        case 'signed':
          final segs = segmentsOf(part.parts.first, depth: depth + 1);
          for (final sig in part.parts.skip(1)) {
            _addAttachment(sig);
          }
          return segs;
        default:
          return [for (final c in part.parts) ...segmentsOf(c, depth: depth + 1)];
      }
    }

    if (mime == 'message/rfc822' || mime == 'message/global') {
      if (part.handle != null || part.parts.isEmpty) {
        _addAttachment(part);
        return const [];
      }
      // The source expanded the embedded message without a downloadable
      // handle (Gmail API): show its content inline.
      return [for (final c in part.parts) ...segmentsOf(c, depth: depth + 1)];
    }

    final disposition = HeaderValue.parse(part.header('Content-Disposition'));
    final filename = _declaredFilename(part, disposition);
    final isBodyType = mime == 'text/plain' || mime == 'text/html';
    if (isBodyType && disposition.value != 'attachment' && filename.isEmpty) {
      if (collectBodyParts) bodyParts.add(part);
      final bytes = _dataOf(part);
      if (bytes == null) {
        unresolved.add(part);
        return const [];
      }
      final contentType = HeaderValue.parse(part.header('Content-Type'));
      final decoded = decodeCharset(bytes, contentType['charset']);
      if (mime == 'text/html') return [_Segment(html: decoded)];
      final flowed = contentType['format']?.toLowerCase() == 'flowed';
      return [
        _Segment(text: flowed ? unflowText(decoded, delSp: contentType['delsp']?.toLowerCase() == 'yes') : decoded),
      ];
    }
    _addAttachment(part, disposition: disposition, filename: filename);
    return const [];
  }

  void _resourceOrAttachment(MimePart part, int depth) {
    if (part.isMultipart) {
      // Nested structure inside related: walk it, but its text is not body.
      for (final c in part.parts) {
        _resourceOrAttachment(c, depth + 1);
      }
      return;
    }
    _addAttachment(part);
  }

  /// Decoded bytes of a part: its own data or previously fetched data.
  /// Null when the content must still be fetched.
  Uint8List? _dataOf(MimePart part) {
    final data = part.data;
    if (data != null) return data;
    final fetched = resolved[part.partId];
    return fetched == null ? null : (fetched is Uint8List ? fetched : Uint8List.fromList(fetched));
  }

  void _addAttachment(MimePart part, {HeaderValue? disposition, String? filename}) {
    final disp = disposition ?? HeaderValue.parse(part.header('Content-Disposition'));
    final declared = filename ?? _declaredFilename(part, disp);
    final mime = part.mimeType.toLowerCase().trim();
    final data = part.data;
    attachments.add(_Attachment(
      partId: part.partId,
      handle: part.handle,
      filename: declared.isNotEmpty ? declared : _fallbackFilename(mime),
      mimeType: mime,
      size: part.size > 0 ? part.size : (data?.length ?? 0),
      contentId: _contentId(part),
      data: data,
    ));
  }
}

String _declaredFilename(MimePart part, HeaderValue disposition) {
  final candidates = [
    part.filename,
    disposition['filename'],
    HeaderValue.parse(part.header('Content-Type'))['name'],
  ];
  for (final c in candidates) {
    if (c != null && c.trim().isNotEmpty) {
      // Strip any path a sender put into the name.
      final decoded = decodeHeaderValue(c.trim());
      final slash = decoded.lastIndexOf(RegExp(r'[/\\]'));
      return slash >= 0 ? decoded.substring(slash + 1) : decoded;
    }
  }
  return '';
}

String? _contentId(MimePart part) {
  final raw = part.header('Content-ID') ?? part.header('X-Attachment-Id');
  return _stripAngle(raw);
}

String? _stripAngle(String? raw) {
  if (raw == null) return null;
  var v = raw.trim();
  if (v.startsWith('<') && v.endsWith('>')) v = v.substring(1, v.length - 1).trim();
  return v.isEmpty ? null : v;
}

String _fallbackFilename(String mime) {
  switch (mime) {
    case 'message/rfc822':
    case 'message/global':
      return 'message.eml';
    case 'text/calendar':
      return 'invite.ics';
    case 'application/pgp-signature':
      return 'signature.asc';
    case 'application/pkcs7-signature':
    case 'application/x-pkcs7-signature':
      return 'smime.p7s';
  }
  const known = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/svg+xml': 'svg',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'text/plain': 'txt',
    'text/html': 'html',
    'text/csv': 'csv',
  };
  final ext = known[mime];
  final base = mime.startsWith('image/') ? 'image' : 'attachment';
  return ext == null ? base : '$base.$ext';
}

String _joinHtml(List<_Segment> segments) {
  final parts = <String>[];
  for (final s in segments) {
    if (s.html != null) {
      parts.add(s.html!);
    } else if (s.text != null && s.text!.isNotEmpty) {
      parts.add(textToHtml(s.text!));
    }
  }
  return parts.join('\n');
}

String _joinText(List<_Segment> segments) =>
    [for (final s in segments) ?s.text].where((t) => t.isNotEmpty).join('\n\n');

/// Escapes plain text for embedding in HTML, preserving line breaks.
String textToHtml(String text) {
  final escaped = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  return '<div style="white-space: pre-wrap">$escaped</div>';
}
