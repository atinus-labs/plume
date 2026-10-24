import 'dart:convert';

/// Health of an account as last observed by the sync engine.
enum AccountStatus {
  ok,

  /// Credentials were rejected or revoked; the user must sign in again.
  needsReauth,

  /// The last sync failed for a transient reason (network, server error).
  degraded,
}

/// A configured mail account. Credentials are never stored here; they live in
/// the platform secret store keyed by [id].
final class Account {
  const Account({
    required this.id,
    required this.provider,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.color,
    this.sortOrder = 0,
    this.status = AccountStatus.ok,
    this.signature,
    this.providerConfig = const {},
  });

  /// Stable local identifier.
  final String id;

  /// Provider kind, e.g. `gmail`. Kept as a string so new providers do not
  /// require a schema change.
  final String provider;
  final String email;
  final String displayName;
  final String? avatarUrl;

  /// ARGB accent used for the account dot in unified views.
  final int color;
  final int sortOrder;
  final AccountStatus status;

  /// Plain-text signature appended to new messages, if any.
  final String? signature;

  /// Non-secret, provider-specific connection settings (e.g. IMAP and SMTP
  /// server addresses). JSON-compatible; only the provider interprets it.
  final Map<String, Object?> providerConfig;

  Account copyWith({
    String? email,
    String? displayName,
    String? avatarUrl,
    int? color,
    int? sortOrder,
    AccountStatus? status,
    String? signature,
    bool clearSignature = false,
    Map<String, Object?>? providerConfig,
  }) =>
      Account(
        id: id,
        provider: provider,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        status: status ?? this.status,
        signature: clearSignature ? null : (signature ?? this.signature),
        providerConfig: providerConfig ?? this.providerConfig,
      );

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.avatarUrl == avatarUrl &&
      other.color == color &&
      other.sortOrder == sortOrder &&
      other.status == status &&
      other.signature == signature &&
      jsonEncode(other.providerConfig) == jsonEncode(providerConfig);

  @override
  int get hashCode =>
      Object.hash(id, email, displayName, avatarUrl, color, sortOrder, status, signature, jsonEncode(providerConfig));
}
