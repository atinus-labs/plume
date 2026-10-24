import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'html_text.dart';

/// Maximum number of characters of a body that are full-text indexed.
const maxIndexedBodyChars = 256 * 1024;

/// Maximum number of participants kept per thread.
const maxParticipants = 6;

/// Registers the application-defined SQL functions the store relies on. Runs
/// on every connection (including background readers), inside the isolate
/// that owns the connection, so HTML stripping never blocks the UI isolate.
void registerPlumeFunctions(CommonDatabase db) {
  db.createFunction(
    functionName: 'plume_body_text',
    argumentCount: const AllowedArgumentCount(2),
    deterministic: true,
    function: (args) => bodyIndexText(args[0] as String?, args[1] as String?),
  );
  db.createFunction(
    functionName: 'plume_addr_text',
    argumentCount: const AllowedArgumentCount.any(),
    deterministic: true,
    function: addressIndexText,
  );
  db.createFunction(
    functionName: 'plume_participants',
    argumentCount: const AllowedArgumentCount(1),
    deterministic: true,
    function: (args) => participantsJson(args[0] as String?),
  );
}

/// Text indexed for a body: the HTML part converted to text when present
/// (that is what the user sees), otherwise the plain text part.
String bodyIndexText(String? html, String? plain) {
  if (html != null && html.isNotEmpty) return htmlToText(html, maxLength: maxIndexedBodyChars);
  if (plain == null) return '';
  return plain.length > maxIndexedBodyChars ? plain.substring(0, maxIndexedBodyChars) : plain;
}

/// Names and emails of the JSON-encoded addresses (single objects or lists)
/// in [values], space separated, for the full-text index.
String addressIndexText(List<Object?> values) {
  final out = StringBuffer();
  void add(Object? a) {
    if (a is! Map) return;
    final name = a['n'];
    final email = a['e'];
    if (name is String && name.isNotEmpty) out.write(' $name');
    if (email is String && email.isNotEmpty) out.write(' $email');
  }

  for (final v in values) {
    if (v is! String || v.isEmpty) continue;
    final decoded = jsonDecode(v);
    if (decoded is List) {
      decoded.forEach(add);
    } else {
      add(decoded);
    }
  }
  return out.toString().trim();
}

/// Builds the participants list of a thread from the JSON array of its
/// messages' senders in chronological order (entries may be null).
///
/// Distinct senders in order of first appearance, at most [maxParticipants].
/// When trimmed, the latest sender is kept and placed last. Each sender is
/// shown with the most recent non-empty display name it used.
String participantsJson(String? sendersJson) {
  if (sendersJson == null || sendersJson.isEmpty) return '[]';
  final senders = jsonDecode(sendersJson);
  if (senders is! List) return '[]';
  final order = <String>[];
  final byEmail = <String, Map<String, Object?>>{};
  String? latest;
  for (final s in senders) {
    if (s is! Map) continue;
    final email = s['e'];
    if (email is! String || email.isEmpty) continue;
    final key = email.toLowerCase();
    final name = s['n'];
    final previous = byEmail[key];
    if (previous == null) {
      order.add(key);
      byEmail[key] = {'e': email, if (name is String && name.isNotEmpty) 'n': name};
    } else if (name is String && name.isNotEmpty) {
      previous['n'] = name;
    }
    latest = key;
  }
  final chosen = order.length <= maxParticipants
      ? order
      : [...order.where((e) => e != latest).take(maxParticipants - 1), latest!];
  return jsonEncode([for (final e in chosen) byEmail[e]]);
}
