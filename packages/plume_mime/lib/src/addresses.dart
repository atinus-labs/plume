import 'package:plume_core/plume_core.dart';

import 'rfc2047.dart';

/// Parses an address-list header (From, To, Cc...) and decodes RFC 2047
/// display names.
///
/// More tolerant than a strict RFC 5322 parser: decoded headers (the Gmail
/// API, sloppy mailers) contain names with unquoted commas
/// (`Doe, Jane <jane@x.org>`), so a fragment without `@` is joined with the
/// next one. Group syntax (`team: a@x, b@y;`) is flattened and empty
/// groups are dropped.
List<Address> parseAddressHeader(String? raw) {
  if (raw == null) return const [];
  final value = unfoldHeader(raw).trim();
  if (value.isEmpty) return const [];

  final pieces = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var inAngle = false;
  var commentDepth = 0;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if (escaped) {
      buf.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\' && (inQuotes || commentDepth > 0)) {
      buf.write(ch);
      escaped = true;
      continue;
    }
    if (!inQuotes) {
      if (ch == '(') commentDepth++;
      if (ch == ')' && commentDepth > 0) commentDepth--;
    }
    if (commentDepth == 0) {
      if (ch == '"') inQuotes = !inQuotes;
      if (!inQuotes) {
        if (ch == '<') inAngle = true;
        if (ch == '>') inAngle = false;
        if ((ch == ',' || ch == ';') && !inAngle) {
          pieces.add(buf.toString());
          buf.clear();
          continue;
        }
      }
    }
    buf.write(ch);
  }
  pieces.add(buf.toString());

  final result = <Address>[];
  var carry = '';
  final groupPrefix = RegExp(r'^\s*[^"<>@,;:()]+:\s*');
  for (final piece in pieces) {
    var candidate = carry.isEmpty ? piece : '$carry,$piece';
    if (!piece.contains('@')) {
      carry = candidate.trim().isEmpty ? '' : candidate;
      continue;
    }
    carry = '';
    if (!candidate.trimLeft().startsWith('"')) {
      final group = groupPrefix.firstMatch(candidate);
      // Only a group if the colon comes before the address.
      if (group != null && !candidate.substring(0, group.end).contains('<')) {
        candidate = candidate.substring(group.end);
      }
    }
    final parsed = _parseMailbox(candidate.trim());
    if (parsed != null) result.add(parsed);
  }
  return result;
}

/// Parses one mailbox (`Name <addr>`, `"Name" <addr>` or `addr (comment)`).
/// Unlike [Address.tryParse], commas in an unquoted name are kept.
Address? _parseMailbox(String part) {
  final lt = part.lastIndexOf('<');
  final gt = part.lastIndexOf('>');
  String email;
  String? name;
  if (lt >= 0 && gt > lt) {
    email = part.substring(lt + 1, gt).trim();
    name = part.substring(0, lt).trim();
  } else {
    email = part.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final comment = RegExp(r'\((.*?)\)').firstMatch(part)?.group(1)?.trim();
    if (comment != null && comment.isNotEmpty) name = comment;
  }
  if (email.startsWith('mailto:')) email = email.substring(7);
  if (!email.contains('@')) return null;
  if (name != null) {
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.substring(1, name.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    name = decodeHeaderValue(name).trim();
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) name = name.substring(1, name.length - 1).trim();
  }
  return Address(email, name == null || name.isEmpty ? null : name);
}

/// The first `<id>` of a Message-ID / In-Reply-To header, angle brackets
/// included. Falls back to the trimmed value for ids without brackets.
String? parseMessageIdHeader(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'<[^<>\s]+>').firstMatch(raw);
  if (m != null) return m.group(0);
  final t = unfoldHeader(raw).trim();
  return t.isEmpty ? null : t;
}

/// All ids of a References header, in order, angle brackets included.
List<String> parseMessageIdList(String? raw) {
  if (raw == null) return const [];
  final ids = [for (final m in RegExp(r'<[^<>\s]+>').allMatches(raw)) m.group(0)!];
  if (ids.isNotEmpty) return ids;
  return raw.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();
}
