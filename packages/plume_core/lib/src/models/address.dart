/// An RFC 5322 mailbox: an optional display name plus an email address.
final class Address {
  const Address(this.email, [this.name]);

  final String email;
  final String? name;

  /// The name to show in the UI: the display name when present, otherwise the
  /// local part of the address.
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// A short first-name-ish label for dense participant lists ("Ana, Ben, me").
  String get shortName {
    final full = displayName;
    final space = full.indexOf(' ');
    return space > 0 ? full.substring(0, space) : full;
  }

  /// Header form, quoting the display name when needed.
  String format() {
    final n = name?.trim();
    if (n == null || n.isEmpty) return email;
    final needsQuotes = RegExp(r'[,;:<>@"()\[\]\\.]').hasMatch(n);
    final quoted = needsQuotes ? '"${n.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"' : n;
    return '$quoted <$email>';
  }

  Map<String, Object?> toJson() => {'e': email, if (name != null) 'n': name};

  static Address fromJson(Map<String, Object?> json) =>
      Address(json['e']! as String, json['n'] as String?);

  /// Parses a single header address such as `"Doe, Jane" <jane@x.org>`.
  static Address? tryParse(String input) {
    final list = parseList(input);
    return list.isEmpty ? null : list.first;
  }

  /// Parses an address-list header value (To, Cc, From...). Tolerant of the
  /// malformed input that real mail contains; never throws.
  static List<Address> parseList(String input) {
    final result = <Address>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var inAngle = false;
    var escaped = false;
    void flush() {
      final part = buffer.toString().trim();
      buffer.clear();
      if (part.isEmpty) return;
      final parsed = _parseOne(part);
      if (parsed != null) result.add(parsed);
    }

    for (final ch in input.split('')) {
      if (escaped) {
        buffer.write(ch);
        escaped = false;
        continue;
      }
      if (ch == r'\' && inQuotes) {
        buffer.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '"') inQuotes = !inQuotes;
      if (!inQuotes) {
        if (ch == '<') inAngle = true;
        if (ch == '>') inAngle = false;
        if ((ch == ',' || ch == ';') && !inAngle) {
          flush();
          continue;
        }
      }
      buffer.write(ch);
    }
    flush();
    return result;
  }

  static Address? _parseOne(String part) {
    final lt = part.lastIndexOf('<');
    final gt = part.lastIndexOf('>');
    if (lt >= 0 && gt > lt) {
      final email = part.substring(lt + 1, gt).trim();
      var name = part.substring(0, lt).trim();
      if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      if (email.isEmpty) return null;
      return Address(email, name.isEmpty ? null : name);
    }
    final bare = part.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    if (!bare.contains('@')) return null;
    return Address(bare);
  }

  @override
  bool operator ==(Object other) =>
      other is Address && other.email.toLowerCase() == email.toLowerCase() && other.name == name;

  @override
  int get hashCode => Object.hash(email.toLowerCase(), name);

  @override
  String toString() => format();
}
