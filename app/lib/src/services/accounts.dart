import 'dart:math';

import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart' show MailServerSettings;

import 'imap_connector.dart';

final _log = Logger('plume.accounts');

/// Signs accounts in for one provider kind and supplies their credentials.
abstract interface class AccountConnector {
  /// Provider kind, matching [MailProviderFactory.kind].
  String get kind;

  /// Display name for the "add account" UI.
  String get label;

  /// Whether the connector can sign in right now (e.g. an OAuth client is
  /// configured).
  bool get isConfigured;

  MailProviderFactory get factory;

  /// Runs the interactive sign-in and stores the credentials under
  /// [accountId]. Returns the signed-in identity.
  /// Completing [cancel] aborts a pending interactive sign-in.
  Future<({String email, String name, String? avatarUrl})> signIn(String accountId, {String? loginHint, Future<void>? cancel});

  /// Credentials for an existing account.
  TokenSource tokenSource(Account account);

  /// Moves stored credentials from one account id to another (used when
  /// the user signs in to an account that already exists).
  Future<void> moveCredentials(String fromAccountId, String toAccountId);

  /// Revokes and forgets the credentials of [account]. Best effort.
  Future<void> signOut(Account account);
}

/// Thrown when the user adds an account that is already present.
final class DuplicateAccountException implements Exception {
  const DuplicateAccountException(this.email, {this.existingKind});

  final String email;

  /// Set when the existing account signs in another way (e.g. the address
  /// was added with Google sign-in and is now being added over IMAP). Its
  /// credentials were left untouched.
  final String? existingKind;
}

/// Adds, re-authenticates and removes accounts.
final class AccountsService {
  AccountsService({required this.store, required List<AccountConnector> connectors})
      : _connectors = {for (final c in connectors) c.kind: c};

  final MailStore store;
  final Map<String, AccountConnector> _connectors;

  late MailEngine _engine;

  /// Set once the engine exists (the engine needs our token sources first).
  set engine(MailEngine engine) => _engine = engine;

  Iterable<AccountConnector> get connectors => _connectors.values;
  AccountConnector? connector(String kind) => _connectors[kind];

  List<MailProviderFactory> get factories => [for (final c in _connectors.values) c.factory];

  TokenSource tokenSourceFor(Account account) {
    final connector = _connectors[account.provider];
    if (connector == null) throw StateError('No connector for ${account.provider}');
    return connector.tokenSource(account);
  }

  static const _palette = [0xFF4C5BD4, 0xFF0B8A6E, 0xFFD14D72, 0xFFE07B18, 0xFF7B4CD4, 0xFF1C8AD1, 0xFF8A6E0B];

  /// Signs in a new account of [kind] and adds it.
  Future<Account> add(String kind, {Future<void>? cancel}) async {
    final connector = _connectors[kind]!;
    final existing = await store.accounts();
    final id = _newId();
    final identity = await connector.signIn(id, cancel: cancel);
    final duplicate = existing.where((a) => a.email.toLowerCase() == identity.email.toLowerCase()).firstOrNull;
    if (duplicate != null && duplicate.provider != kind) {
      await connector.signOut(_placeholder(id, kind, identity.email));
      throw DuplicateAccountException(identity.email, existingKind: duplicate.provider);
    }
    if (duplicate != null) {
      // Signing in again just refreshes the existing account's credentials.
      // Revoking the new grant would revoke the existing one too.
      await connector.moveCredentials(id, duplicate.id);
      await store.saveAccount(duplicate.copyWith(status: AccountStatus.ok));
      await _engine.restartAccount(duplicate.id);
      throw DuplicateAccountException(identity.email);
    }
    final account = Account(
      id: id,
      provider: kind,
      email: identity.email,
      displayName: identity.name.isEmpty ? identity.email : identity.name,
      avatarUrl: identity.avatarUrl,
      color: _palette[existing.length % _palette.length],
      sortOrder: existing.length,
    );
    await store.saveAccount(account);
    _log.info('Added ${account.provider} account');
    return account;
  }

  /// Adds an account on a mail server whose settings and password the user
  /// entered and the caller already verified. Adding an address that is
  /// already present updates its settings and password instead.
  Future<Account> addServerAccount({
    required String email,
    required String name,
    required MailServerSettings settings,
    required String password,
  }) async {
    final connector = _imap;
    final existing = await store.accounts();
    final displayName = name.trim().isEmpty ? email : name.trim();
    final duplicate = existing.where((a) => a.email.toLowerCase() == email.toLowerCase()).firstOrNull;
    if (duplicate != null) {
      if (duplicate.provider != connector.kind) {
        throw DuplicateAccountException(email, existingKind: duplicate.provider);
      }
      await updateServerAccount(
        duplicate.copyWith(displayName: displayName),
        settings: settings,
        password: password,
      );
      throw DuplicateAccountException(email);
    }
    final id = _newId();
    await connector.savePassword(id, password);
    final account = Account(
      id: id,
      provider: connector.kind,
      email: email,
      displayName: displayName,
      color: _palette[existing.length % _palette.length],
      sortOrder: existing.length,
      providerConfig: settings.toJson(),
    );
    await store.saveAccount(account);
    _log.info('Added ${account.provider} account');
    return account;
  }

  /// Saves new server settings and/or a new password for a mail server
  /// account and reconnects it.
  Future<void> updateServerAccount(Account account, {MailServerSettings? settings, String? password}) async {
    if (password != null) await _imap.savePassword(account.id, password);
    await store.saveAccount(account.copyWith(
      status: AccountStatus.ok,
      providerConfig: settings?.toJson(),
    ));
    await _engine.restartAccount(account.id);
  }

  ImapConnector get _imap => _connectors[ImapConnector.kindId]! as ImapConnector;

  static Account _placeholder(String id, String kind, String email) =>
      Account(id: id, provider: kind, email: email, displayName: email, color: 0);

  /// Signs an account in again after its credentials were revoked.
  Future<void> reauthenticate(Account account) async {
    final connector = _connectors[account.provider]!;
    final identity = await connector.signIn(account.id, loginHint: account.email);
    if (identity.email.toLowerCase() != account.email.toLowerCase()) {
      throw StateError('Signed in as ${identity.email} instead of ${account.email}');
    }
    await store.saveAccount(account.copyWith(status: AccountStatus.ok, avatarUrl: identity.avatarUrl));
    await _engine.restartAccount(account.id);
  }

  Future<void> remove(Account account) async {
    await store.deleteAccount(account.id);
    try {
      await _connectors[account.provider]?.signOut(account);
    } catch (e) {
      _log.warning('Sign-out failed: $e');
    }
  }

  Future<void> reorder(List<Account> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) await store.saveAccount(ordered[i].copyWith(sortOrder: i));
    }
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}
