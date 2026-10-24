import 'dart:convert';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';

import 'accounts.dart';
import 'secret_store.dart';

/// Accounts on any IMAP/SMTP server, signed in with a password (often an
/// app password). Server addresses live in `Account.providerConfig`; the
/// password lives in the keyring.
final class ImapConnector implements AccountConnector {
  ImapConnector(this._secrets);

  static const kindId = 'imap';

  final SecretStore _secrets;
  final _sources = <String, PasswordSource>{};

  @override
  String get kind => kindId;

  @override
  String get label => 'Other mail';

  @override
  bool get isConfigured => true;

  @override
  MailProviderFactory get factory => ImapProviderFactory();

  static String _key(String accountId) => 'account.$accountId.imap';

  /// Mail server accounts sign in through a form, see
  /// [AccountsService.addServerAccount].
  @override
  Future<({String email, String name, String? avatarUrl})> signIn(
    String accountId, {
    String? loginHint,
    Future<void>? cancel,
  }) =>
      throw UnsupportedError('Mail server accounts sign in with a form');

  /// Stores [password] for [accountId], replacing any previous one. Running
  /// providers pick it up on their next login.
  Future<void> savePassword(String accountId, String password) async {
    await _secrets.write(_key(accountId), jsonEncode({'password': password}));
    _sources[accountId]?.replace(password);
  }

  @override
  TokenSource tokenSource(Account account) => _sources.putIfAbsent(
        account.id,
        () => PasswordSource(() async {
          final raw = await _secrets.read(_key(account.id));
          if (raw == null) return null;
          return (jsonDecode(raw) as Map<String, Object?>)['password'] as String?;
        }),
      );

  @override
  Future<void> moveCredentials(String fromAccountId, String toAccountId) async {
    final raw = await _secrets.read(_key(fromAccountId));
    if (raw == null) return;
    await _secrets.write(_key(toAccountId), raw);
    await _secrets.delete(_key(fromAccountId));
    _sources.remove(fromAccountId);
    _sources.remove(toAccountId);
  }

  @override
  Future<void> signOut(Account account) async {
    _sources.remove(account.id);
    await _secrets.delete(_key(account.id));
  }
}

/// Hands the stored password to the IMAP provider as its "token".
final class PasswordSource implements TokenSource {
  PasswordSource(this._load);

  final Future<String?> Function() _load;
  String? _password;

  @override
  Future<String> accessToken() async {
    final password = _password ??= await _load();
    if (password == null) throw const AuthException('No password is saved for this account');
    return password;
  }

  /// A rejected password stays wrong until the user enters a new one, so
  /// there is nothing to refresh.
  @override
  void invalidate() {}

  void replace(String password) => _password = password;
}
