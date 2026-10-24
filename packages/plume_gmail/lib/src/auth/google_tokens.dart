import '../util/json.dart';

/// OAuth credentials and identity for one Google account.
///
/// Serialise with [toJson] and keep the result in the platform secret
/// store; it contains the long-lived refresh token. [toString] never
/// includes token values.
final class GoogleTokens {
  const GoogleTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
    required this.email,
    this.name,
    this.picture,
    this.subject,
    this.scopes = const [],
  });

  final String accessToken;
  final String refreshToken;

  /// When [accessToken] expires (UTC).
  final DateTime expiry;

  final String email;
  final String? name;

  /// Avatar URL.
  final String? picture;

  /// Google's stable account id (`sub`), unaffected by email changes.
  final String? subject;

  /// Scopes the user actually granted (they may decline some).
  final List<String> scopes;

  bool hasScope(String scope) => scopes.contains(scope);

  /// Whether the access token expires within [margin] of [now].
  bool expiresWithin(Duration margin, DateTime now) => !now.toUtc().add(margin).isBefore(expiry);

  GoogleTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? email,
    String? name,
    String? picture,
    String? subject,
    List<String>? scopes,
  }) =>
      GoogleTokens(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiry: expiry ?? this.expiry,
        email: email ?? this.email,
        name: name ?? this.name,
        picture: picture ?? this.picture,
        subject: subject ?? this.subject,
        scopes: scopes ?? this.scopes,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiry': expiry.toUtc().toIso8601String(),
        'email': email,
        if (name != null) 'name': name,
        if (picture != null) 'picture': picture,
        if (subject != null) 'subject': subject,
        'scopes': scopes,
      };

  /// Throws [FormatException] when required fields are missing.
  static GoogleTokens fromJson(Map<String, Object?> json) {
    String req(String key) => json.str(key) ?? (throw FormatException('GoogleTokens: missing "$key"'));
    final expiry = DateTime.tryParse(req('expiry'));
    if (expiry == null) throw const FormatException('GoogleTokens: invalid "expiry"');
    return GoogleTokens(
      accessToken: req('accessToken'),
      refreshToken: req('refreshToken'),
      expiry: expiry.toUtc(),
      email: req('email'),
      name: json.str('name'),
      picture: json.str('picture'),
      subject: json.str('subject'),
      scopes: json.strList('scopes'),
    );
  }

  @override
  String toString() => 'GoogleTokens($email, expires ${expiry.toIso8601String()})';
}
