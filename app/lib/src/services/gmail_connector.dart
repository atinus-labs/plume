import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/plume_gmail.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'accounts.dart';
import 'secret_store.dart';

final _log = Logger('plume.gmail');

/// Google accounts: OAuth in the system browser, tokens in the keyring.
final class GmailConnector implements AccountConnector {
  GmailConnector(this._secrets);

  final SecretStore _secrets;
  final _sources = <String, GoogleTokenSource>{};
  GoogleOAuth? _oauth;
  String? _oauthClientId;

  @override
  String get kind => 'gmail';

  @override
  String get label => 'Google';

  @override
  bool get isConfigured => GoogleClient.resolve() != null;

  @override
  MailProviderFactory get factory => const GmailProviderFactory();

  /// The OAuth client, recreated if the configured client changed (e.g. the
  /// user imported a client file while Plume was running).
  GoogleOAuth get _client {
    final client = GoogleClient.resolve();
    if (client == null) throw const AuthException('Google sign-in is not set up yet');
    if (_oauth == null || _oauthClientId != client.id) {
      _oauth?.close();
      _oauth = GoogleOAuth(GoogleOAuthConfig(clientId: client.id, clientSecret: client.secret));
      _oauthClientId = client.id;
    }
    return _oauth!;
  }

  static String _key(String accountId) => 'account.$accountId.google';

  @override
  Future<({String email, String name, String? avatarUrl})> signIn(
    String accountId, {
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final tokens = await _client.signIn(
      openBrowser: (url) async {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw const GoogleSignInException(SignInFailure.failed, 'Could not open a web browser');
        }
      },
      loginHint: loginHint,
      cancel: cancel,
    );
    await _secrets.write(_key(accountId), jsonEncode(tokens.toJson()));
    _sources[accountId]?.replaceTokens(tokens);
    return (email: tokens.email, name: tokens.name ?? '', avatarUrl: tokens.picture);
  }

  @override
  TokenSource tokenSource(Account account) => _sources.putIfAbsent(
        account.id,
        () => GoogleTokenSource.deferred(
          _client,
          load: () async {
            final raw = await _secrets.read(_key(account.id));
            return raw == null ? null : GoogleTokens.fromJson(jsonDecode(raw) as Map<String, Object?>);
          },
          onTokensChanged: (t) => _secrets.write(_key(account.id), jsonEncode(t.toJson())),
        ),
      );

  @override
  Future<void> moveCredentials(String fromAccountId, String toAccountId) async {
    final raw = await _secrets.read(_key(fromAccountId));
    if (raw == null) return;
    await _secrets.write(_key(toAccountId), raw);
    await _secrets.delete(_key(fromAccountId));
    _sources.remove(fromAccountId);
    _sources[toAccountId]?.replaceTokens(GoogleTokens.fromJson(jsonDecode(raw) as Map<String, Object?>));
  }

  @override
  Future<void> signOut(Account account) async {
    final raw = await _secrets.read(_key(account.id));
    _sources.remove(account.id);
    await _secrets.delete(_key(account.id));
    if (raw == null) return;
    try {
      await _client.revoke(GoogleTokens.fromJson(jsonDecode(raw) as Map<String, Object?>));
    } catch (e) {
      _log.info('Token revocation failed (the account is removed regardless): $e');
    }
  }
}
