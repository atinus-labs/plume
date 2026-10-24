import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart' show decodeBase64Lenient;

import '../util/json.dart';
import 'google_tokens.dart';
import 'loopback_receiver.dart';
import 'oauth_pages.dart';

final Logger _log = Logger('plume.gmail.oauth');

/// OAuth client settings for a Google "Desktop app" client.
///
/// Desktop client secrets are not confidential (RFC 8252 section 8.5);
/// Google still requires them at the token endpoint. PKCE provides the
/// actual protection of the authorization code.
final class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    this.scopes = defaultScopes,
    this.authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth',
    this.tokenEndpoint = 'https://oauth2.googleapis.com/token',
    this.revocationEndpoint = 'https://oauth2.googleapis.com/revoke',
    this.userInfoEndpoint = 'https://openidconnect.googleapis.com/v1/userinfo',
  });

  /// Full mail access; required for IMAP (used for push) and permanent
  /// deletion.
  static const mailScope = 'https://mail.google.com/';
  static const defaultScopes = [mailScope, 'openid', 'email', 'profile'];

  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String revocationEndpoint;
  final String userInfoEndpoint;
}

/// Google OAuth 2.0 for installed apps: loopback redirect + PKCE (S256) +
/// `state`, offline access, refresh and revocation.
final class GoogleOAuth {
  GoogleOAuth(this.config, {http.Client? httpClient, Random? random, DateTime Function()? clock})
      : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final GoogleOAuthConfig config;
  final http.Client _http;
  final bool _ownsHttp;
  final Random _random;
  final DateTime Function() _clock;

  /// Runs the interactive sign-in.
  ///
  /// Starts a loopback server on a free port, calls [openBrowser] with the
  /// consent URL, waits for the redirect, exchanges the code and identifies
  /// the user. The browser tab gets a small success or failure page.
  ///
  /// Throws [GoogleSignInException] when the flow is cancelled (via
  /// [cancel]), times out, is denied, or lacks the Gmail scope;
  /// [AuthException] for `invalid_grant` and similar token endpoint
  /// rejections; [TransientException] for network failures.
  Future<GoogleTokens> signIn({
    required Future<void> Function(Uri url) openBrowser,
    String? loginHint,
    Duration timeout = const Duration(minutes: 5),
    Future<void>? cancel,
  }) async {
    final pkce = Pkce.generate(_random);
    final state = randomUrlSafeToken(_random, 24);
    final receiver = await LoopbackReceiver.start(expectedState: state);
    try {
      final url = authorizationUrl(
        redirectUri: receiver.redirectUri,
        codeChallenge: pkce.challenge,
        state: state,
        loginHint: loginHint,
      );
      final callbackFuture = receiver.waitForCallback(timeout: timeout, cancel: cancel);
      try {
        await openBrowser(url);
      } on Object catch (e) {
        throw GoogleSignInException(SignInFailure.failed, 'Could not open the browser: $e');
      }
      final callback = await callbackFuture;
      try {
        final tokens = await exchangeCode(
          code: callback.code,
          codeVerifier: pkce.verifier,
          redirectUri: receiver.redirectUri,
        );
        final missing = config.scopes.where((s) => s.startsWith('https://') && !tokens.hasScope(s)).toList();
        if (missing.isNotEmpty) {
          throw const GoogleSignInException(
            SignInFailure.missingScopes,
            'Plume needs permission to read, compose and send your Gmail. '
            'Please sign in again and allow access.',
          );
        }
        await callback.respond(successPage(email: tokens.email));
        _log.info('Signed in a Google account');
        return tokens;
      } on Object catch (e) {
        await callback.respond(failurePage(reason: _describe(e)));
        rethrow;
      }
    } finally {
      await receiver.close();
    }
  }

  /// The consent URL. Public for tests and for apps that present it
  /// themselves.
  Uri authorizationUrl({
    required Uri redirectUri,
    required String codeChallenge,
    required String state,
    String? loginHint,
  }) =>
      Uri.parse(config.authorizationEndpoint).replace(queryParameters: {
        'client_id': config.clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'scope': config.scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
        if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
      });

  /// Exchanges an authorization code for tokens and identifies the user.
  Future<GoogleTokens> exchangeCode({
    required String code,
    required String codeVerifier,
    required Uri redirectUri,
  }) async {
    final json = await _tokenRequest({
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri.toString(),
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
    });
    final accessToken = json.str('access_token');
    final refreshToken = json.str('refresh_token');
    if (accessToken == null) throw const PermanentException('Google returned no access token');
    if (refreshToken == null) {
      throw const AuthException('Google returned no refresh token; sign in again to grant offline access');
    }
    var identity = _identityFromIdToken(json.str('id_token'));
    if (identity?.email == null) identity = await _userInfo(accessToken);
    final email = identity?.email;
    if (email == null || email.isEmpty) throw const AuthException('Could not determine the Google account email');
    return GoogleTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: _expiry(json),
      email: email,
      name: identity?.name,
      picture: identity?.picture,
      subject: identity?.subject,
      scopes: _scopes(json) ?? config.scopes,
    );
  }

  /// Obtains a new access token. `invalid_grant` (revoked or expired
  /// refresh token) is an [AuthException].
  Future<GoogleTokens> refresh(GoogleTokens tokens) async {
    final json = await _tokenRequest({
      'grant_type': 'refresh_token',
      'refresh_token': tokens.refreshToken,
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
    });
    final accessToken = json.str('access_token');
    if (accessToken == null) throw const TransientException('Google returned no access token');
    final identity = _identityFromIdToken(json.str('id_token'));
    return tokens.copyWith(
      accessToken: accessToken,
      refreshToken: json.str('refresh_token'),
      expiry: _expiry(json),
      name: identity?.name,
      picture: identity?.picture,
      scopes: _scopes(json),
    );
  }

  /// Revokes the grant (refresh token, and with it all access tokens).
  /// Already-revoked tokens are not an error.
  Future<void> revoke(GoogleTokens tokens) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(config.revocationEndpoint),
            headers: {'content-type': 'application/x-www-form-urlencoded'},
            body: {'token': tokens.refreshToken.isNotEmpty ? tokens.refreshToken : tokens.accessToken},
          )
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      if (_isNetworkError(e)) throw TransientException('Could not reach Google to revoke access', e);
      rethrow;
    }
    if (response.statusCode == 200) return;
    final error = _errorCode(response.body);
    if (response.statusCode == 400 && (error == 'invalid_token' || error == 'invalid_request')) return;
    if (response.statusCode >= 500 || response.statusCode == 429) {
      throw TransientException('Revocation failed (HTTP ${response.statusCode})');
    }
    throw PermanentException('Revocation failed (HTTP ${response.statusCode}${error == null ? '' : ', $error'})');
  }

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<JsonMap> _tokenRequest(Map<String, String> form) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(config.tokenEndpoint),
            headers: {'content-type': 'application/x-www-form-urlencoded', 'accept': 'application/json'},
            body: form,
          )
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      if (_isNetworkError(e)) throw TransientException('Could not reach Google', e);
      rethrow;
    }
    JsonMap? json;
    try {
      json = asJsonMap(jsonDecode(response.body));
    } on FormatException {
      json = null;
    }
    if (response.statusCode == 200 && json != null) return json;

    final error = json?.str('error');
    final description = json?.str('error_description');
    final text = 'Google token endpoint: ${error ?? 'HTTP ${response.statusCode}'}'
        '${description == null ? '' : ' ($description)'}';
    const authErrors = {'invalid_grant', 'invalid_client', 'unauthorized_client', 'access_denied', 'invalid_scope'};
    if (error != null && authErrors.contains(error)) throw AuthException(text);
    if (response.statusCode == 401) throw AuthException(text);
    if (response.statusCode == 429 || response.statusCode >= 500) {
      final retry = int.tryParse(response.headers['retry-after'] ?? '');
      throw TransientException(text, null, retry == null ? null : Duration(seconds: retry));
    }
    throw PermanentException(text);
  }

  DateTime _expiry(JsonMap json) => _clock().toUtc().add(Duration(seconds: json.integer('expires_in') ?? 3600));

  static List<String>? _scopes(JsonMap json) {
    final scope = json.str('scope');
    if (scope == null || scope.trim().isEmpty) return null;
    return scope.split(' ').where((s) => s.isNotEmpty).toList();
  }

  /// Reads identity claims from the ID token. The token comes straight
  /// from Google's token endpoint over TLS, so per OpenID Connect Core
  /// 3.1.3.7 the TLS server validation stands in for signature checks;
  /// audience and issuer are still verified.
  _Identity? _identityFromIdToken(String? idToken) {
    if (idToken == null) return null;
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    final payload = decodeBase64Lenient(parts[1]);
    if (payload == null) return null;
    final JsonMap? claims;
    try {
      claims = asJsonMap(jsonDecode(utf8.decode(payload)));
    } on FormatException {
      return null;
    }
    if (claims == null) return null;
    final aud = claims['aud'];
    final audienceOk = aud == config.clientId || (aud is List && aud.contains(config.clientId));
    final iss = claims.str('iss');
    final issuerOk = iss == 'https://accounts.google.com' || iss == 'accounts.google.com';
    if (!audienceOk || !issuerOk) {
      _log.warning('Ignoring an ID token with unexpected audience or issuer');
      return null;
    }
    return _Identity(
      email: claims.str('email'),
      name: claims.str('name'),
      picture: claims.str('picture'),
      subject: claims.str('sub'),
    );
  }

  Future<_Identity?> _userInfo(String accessToken) async {
    try {
      final response = await _http.get(Uri.parse(config.userInfoEndpoint), headers: {
        'authorization': 'Bearer $accessToken',
        'accept': 'application/json',
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final json = asJsonMap(jsonDecode(response.body));
      if (json == null) return null;
      return _Identity(
        email: json.str('email'),
        name: json.str('name'),
        picture: json.str('picture'),
        subject: json.str('sub'),
      );
    } on Object catch (e) {
      if (_isNetworkError(e) || e is FormatException) return null;
      rethrow;
    }
  }

  static String? _errorCode(String body) {
    try {
      return asJsonMap(jsonDecode(body))?.str('error');
    } on FormatException {
      return null;
    }
  }

  static bool _isNetworkError(Object e) => e is IOException || e is http.ClientException || e is TimeoutException;

  static String _describe(Object e) => switch (e) {
        GoogleSignInException(:final message) => message,
        AuthException() => 'Google did not accept the sign-in. Please try again.',
        TransientException() => 'Plume could not reach Google. Check your connection and try again.',
        _ => 'Something went wrong while finishing sign-in.',
      };
}

final class _Identity {
  const _Identity({this.email, this.name, this.picture, this.subject});

  final String? email;
  final String? name;
  final String? picture;
  final String? subject;
}
