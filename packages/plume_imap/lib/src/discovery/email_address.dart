/// An email address split into the parts discovery works with.
final class EmailAddress {
  const EmailAddress._(this.localPart, this.domain);

  /// The part before the `@`, as typed.
  final String localPart;

  /// The domain, lower case, without a trailing dot.
  final String domain;

  String get address => '$localPart@$domain';

  static final RegExp _label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

  /// Parses [input], or returns null when it is not (yet) a complete
  /// address with a dotted ASCII domain. Internationalized domains are not
  /// supported: they would need IDNA encoding for DNS and HTTP.
  static EmailAddress? tryParse(String input) {
    final s = input.trim();
    final at = s.lastIndexOf('@');
    if (at <= 0 || at == s.length - 1) return null;
    final local = s.substring(0, at);
    if (local.contains(RegExp(r'[\s<>]'))) return null;
    var domain = s.substring(at + 1).toLowerCase();
    if (domain.endsWith('.')) domain = domain.substring(0, domain.length - 1);
    final labels = domain.split('.');
    if (labels.length < 2 || domain.length > 253 || !labels.every(_label.hasMatch)) return null;
    return EmailAddress._(local, domain);
  }

  @override
  String toString() => address;
}
