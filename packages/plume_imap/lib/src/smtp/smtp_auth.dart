import 'dart:convert';

/// A SASL mechanism for SMTP AUTH (RFC 4954).
///
/// This is the seam for adding sign-in methods: XOAUTH2 would send
/// `user=<email>^Aauth=Bearer <token>^A^A` as its initial response and
/// answer the server's JSON error challenge with an empty response, then
/// let the 535 that follows surface as an auth failure.
abstract interface class SaslMechanism {
  /// The mechanism name as advertised in EHLO, e.g. `PLAIN`.
  String get name;

  /// The initial response sent with the AUTH command, or null to wait for
  /// the server's first challenge.
  List<int>? get initialResponse;

  /// Answers the server challenge (already base64-decoded) at [step]
  /// (0-based). Throws [StateError] when the exchange should be aborted.
  List<int> respond(List<int> challenge, int step);
}

/// RFC 4616 PLAIN: authorization identity (empty), username and password,
/// NUL-separated, in a single round trip. Only ever sent over TLS or to a
/// local bridge.
final class PlainMechanism implements SaslMechanism {
  const PlainMechanism(this.username, this.password);

  final String username;
  final String password;

  @override
  String get name => 'PLAIN';

  @override
  List<int> get initialResponse => utf8.encode('\u0000$username\u0000$password');

  @override
  List<int> respond(List<int> challenge, int step) {
    // A server that ignores the initial response asks with an empty
    // challenge; anything after that is a protocol violation.
    if (step == 0) return initialResponse;
    throw StateError('Unexpected PLAIN challenge');
  }
}

/// The obsolete but ubiquitous LOGIN mechanism: the server prompts for the
/// username, then the password. Prompts vary ("Username:", "User Name"), so
/// they are answered by position rather than by text.
final class LoginMechanism implements SaslMechanism {
  const LoginMechanism(this.username, this.password);

  final String username;
  final String password;

  @override
  String get name => 'LOGIN';

  @override
  List<int>? get initialResponse => null;

  @override
  List<int> respond(List<int> challenge, int step) => switch (step) {
    0 => utf8.encode(username),
    1 => utf8.encode(password),
    _ => throw StateError('Unexpected LOGIN challenge'),
  };
}
