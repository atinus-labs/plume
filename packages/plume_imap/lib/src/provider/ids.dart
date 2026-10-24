import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Where a generic-IMAP message lives on the server.
typedef ImapLocation = ({String path, int uidValidity, int uid});

/// Message and thread identity for IMAP accounts.
///
/// **Generic servers.** A message is identified by its folder, the
/// folder's UIDVALIDITY and its UID: `<uidvalidity>.<uid>@<path>`, e.g.
/// `1700000000.42@INBOX` or `5.7@Archive/2026`. The path is the decoded
/// (Unicode) mailbox name and may contain any character; the two numbers
/// before the first `@` are digits, so the id parses unambiguously.
/// Including UIDVALIDITY means a server that renumbers a folder can never
/// make an old id point at a different message. A move gives the message
/// a new id; the provider re-keys stored rows from COPYUID data.
///
/// **Gmail.** Ids are X-GM-MSGID in lower-case hex (the Gmail API's ids),
/// stable across labels and folders. They never contain `@`.
///
/// **Threads.** Gmail uses X-GM-THRID in hex. Generic servers derive the
/// thread from the conversation root's Message-ID (the first References
/// entry, else In-Reply-To, else the message's own Message-ID), which is
/// the same for every message of a conversation in every folder, so a
/// reply filed in Sent joins the received mail in INBOX. The thread id is
/// that root id, lower-cased, in angle brackets (`<abc@example.com>`), so
/// the conversation can be found on the server with a header search even
/// when nothing of it is stored any more. Without any Message-ID, the
/// sender, date and subject are hashed instead (`h:` + 16 hex digits of
/// SHA-256; still folder-independent).
abstract final class ImapIds {
  static String message(String path, int uidValidity, int uid) => '$uidValidity.$uid@$path';

  static final RegExp _pattern = RegExp(r'^(\d+)\.(\d+)@(.*)$', dotAll: true);

  /// Parses a generic message id; null for Gmail ids and garbage.
  static ImapLocation? parse(String id) {
    final m = _pattern.firstMatch(id);
    if (m == null) return null;
    final uv = int.tryParse(m.group(1)!);
    final uid = int.tryParse(m.group(2)!);
    if (uv == null || uid == null || uid < 1) return null;
    return (path: m.group(3)!, uidValidity: uv, uid: uid);
  }

  /// The thread of a generic-IMAP message.
  static String thread({
    String? messageId,
    List<String> references = const [],
    String? inReplyTo,
    required String fallback,
  }) {
    final root = _firstUsable([...references, ?inReplyTo, ?messageId]);
    if (root != null) return '<$root>';
    return 'h:${sha256.convert(utf8.encode(fallback)).toString().substring(0, 16)}';
  }

  /// The root Message-ID of a generic thread id (without brackets), or
  /// null for hashed ids.
  static String? threadRoot(String threadId) =>
      threadId.length > 2 && threadId.startsWith('<') && threadId.endsWith('>')
          ? threadId.substring(1, threadId.length - 1)
          : null;

  static String? _firstUsable(List<String> ids) {
    for (final raw in ids) {
      final n = normalizeMessageId(raw);
      if (n != null) return n;
    }
    return null;
  }

  /// `<Abc@Example.org>` → `abc@example.org`.
  static String? normalizeMessageId(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    if (v.startsWith('<')) v = v.substring(1);
    if (v.endsWith('>')) v = v.substring(0, v.length - 1);
    v = v.trim().toLowerCase();
    return v.isEmpty ? null : v;
  }
}
