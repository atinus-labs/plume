import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/plume_gmail.dart';
import 'package:plume_gmail/src/auth/loopback_receiver.dart';
import 'package:test/test.dart';

const config = GoogleOAuthConfig(clientId: 'cid.apps.googleusercontent.com', clientSecret: 'shh');
final now = DateTime.utc(2026, 10, 24, 12);

String jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'RS256', 'typ': 'JWT'})}.${part(claims)}.c2lnbmF0dXJl';
}

Map<String, Object?> tokenResponse({
  String scope = 'https://mail.google.com/ openid https://www.googleapis.com/auth/userinfo.email '
      'https://www.googleapis.com/auth/userinfo.profile',
  Map<String, Object?>? claims,
  bool refreshToken = true,
}) =>
    {
      'access_token': 'ya29.access',
      'expires_in': 3599,
      if (refreshToken) 'refresh_token': '1//refresh',
      'scope': scope,
      'token_type': 'Bearer',
      'id_token': jwt(claims ??
          {
            'iss': 'https://accounts.google.com',
            'aud': config.clientId,
            'sub': '1234567890',
            'email': 'zoe@example.com',
            'email_verified': true,
            'name': 'Zoë Example',
            'picture': 'https://lh3.googleusercontent.com/a/zoe',
          }),
    };

/// Plays the browser: follows Google's redirect to the loopback server.
Future<({int status, String body})> browse(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    return (status: response.statusCode, body: await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('PKCE', () {
    test('matches the RFC 7636 test vector', () {
      expect(Pkce.challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('generates 43-character unreserved verifiers', () {
      final a = Pkce.generate(Random.secure());
      final b = Pkce.generate(Random.secure());
      expect(a.verifier, hasLength(43));
      expect(a.verifier, matches(RegExp(r'^[A-Za-z0-9\-_]+$')));
      expect(a.challenge, Pkce.challengeOf(a.verifier));
      expect(a.verifier, isNot(b.verifier));
    });
  });

  group('signIn', () {
    test('runs the loopback flow with PKCE and state, then identifies the user', () async {
      late Uri authUrl;
      Map<String, String>? form;
      final oauth = GoogleOAuth(config, clock: () => now, httpClient: MockClient((req) async {
        expect(req.url.toString(), config.tokenEndpoint);
        form = Uri.splitQueryString(req.body);
        return http.Response(jsonEncode(tokenResponse()), 200);
      }));
      final page = Completer<({int status, String body})>();

      final tokens = await oauth.signIn(
        loginHint: 'zoe@example.com',
        openBrowser: (url) async {
          authUrl = url;
          final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          final notFound = await browse(redirect.replace(path: '/favicon.ico'));
          expect(notFound.status, 404);
          unawaited(browse(redirect.replace(queryParameters: {
            'state': url.queryParameters['state']!,
            'code': '4/0Acode',
            'scope': 'email openid https://mail.google.com/',
          })).then(page.complete));
        },
      );

      // Authorization request.
      expect(authUrl.origin, 'https://accounts.google.com');
      final q = authUrl.queryParameters;
      expect(q['client_id'], config.clientId);
      expect(q['response_type'], 'code');
      expect(q['code_challenge_method'], 'S256');
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
      expect(q['login_hint'], 'zoe@example.com');
      expect(q['scope'], 'https://mail.google.com/ openid email profile');
      expect(q['state'], hasLength(32));
      final redirect = Uri.parse(q['redirect_uri']!);
      expect(redirect.host, '127.0.0.1');
      expect(redirect.port, greaterThan(0));

      // Token request: the verifier matches the challenge sent earlier.
      expect(form!['grant_type'], 'authorization_code');
      expect(form!['code'], '4/0Acode');
      expect(Pkce.challengeOf(form!['code_verifier']!), q['code_challenge']);
      expect(form!['redirect_uri'], q['redirect_uri']);
      expect(form!['client_secret'], 'shh');

      expect(tokens.accessToken, 'ya29.access');
      expect(tokens.refreshToken, '1//refresh');
      expect(tokens.expiry, now.add(const Duration(seconds: 3599)));
      expect(tokens.email, 'zoe@example.com');
      expect(tokens.name, 'Zoë Example');
      expect(tokens.picture, 'https://lh3.googleusercontent.com/a/zoe');
      expect(tokens.subject, '1234567890');
      expect(tokens.hasScope(GoogleOAuthConfig.mailScope), isTrue);

      final shown = await page.future;
      expect(shown.status, 200);
      expect(shown.body, contains('You can close this tab and return to Plume.'));
      expect(shown.body, contains('zoe@example.com'));
      expect(shown.body, contains('prefers-color-scheme: dark'));

      // The loopback server is gone.
      await expectLater(browse(redirect), throwsA(isA<SocketException>()));
    });

    Future<(Object, ({int status, String body}))> failingFlow(
      Map<String, String> Function(Map<String, String> q) params, {
      http.Client? client,
    }) async {
      final oauth = GoogleOAuth(config, httpClient: client ?? MockClient((_) async => fail('no token request')));
      final page = Completer<({int status, String body})>();
      try {
        await oauth.signIn(openBrowser: (url) async {
          final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          unawaited(browse(redirect.replace(queryParameters: params(url.queryParameters))).then(page.complete));
        });
      } on Object catch (e) {
        return (e, await page.future);
      }
      fail('expected sign-in to fail');
    }

    test('rejects a mismatched state', () async {
      final (error, page) = await failingFlow((q) => {'state': 'forged', 'code': 'x'});
      expect(error, isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.stateMismatch));
      expect(page.status, 400);
      expect(page.body, contains('did not match'));
    });

    test('reports a denied consent', () async {
      final (error, page) = await failingFlow((q) => {'state': q['state']!, 'error': 'access_denied'});
      expect(error, isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.accessDenied));
      expect(page.body, contains('Access was not granted.'));
    });

    test('fails when the Gmail scope was unticked', () async {
      final (error, page) = await failingFlow(
        (q) => {'state': q['state']!, 'code': 'c'},
        client: MockClient((_) async => http.Response(jsonEncode(tokenResponse(scope: 'openid email profile')), 200)),
      );
      expect(error, isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.missingScopes));
      expect(page.body, contains('Plume needs permission'));
    });

    test('maps invalid_grant during the exchange to AuthException', () async {
      final (error, page) = await failingFlow(
        (q) => {'state': q['state']!, 'code': 'c'},
        client: MockClient((_) async => http.Response('{"error":"invalid_grant","error_description":"Bad Request"}', 400)),
      );
      expect(error, isA<AuthException>());
      expect(page.body, contains('Sign-in did not complete'));
    });

    test('times out when the browser never comes back', () async {
      final oauth = GoogleOAuth(config, httpClient: MockClient((_) async => fail('unexpected')));
      await expectLater(
        oauth.signIn(openBrowser: (_) async {}, timeout: const Duration(milliseconds: 100)),
        throwsA(isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.timedOut)),
      );
    });

    test('a browser that cannot be opened fails the flow', () async {
      final oauth = GoogleOAuth(config, httpClient: MockClient((_) async => fail('unexpected')));
      await expectLater(
        oauth.signIn(openBrowser: (_) async => throw const ProcessException('xdg-open', [])),
        throwsA(isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.failed)),
      );
    });

    test('cancel future aborts the flow', () async {
      final oauth = GoogleOAuth(config, httpClient: MockClient((_) async => fail('unexpected')));
      final cancel = Completer<void>();
      final flow = oauth.signIn(openBrowser: (_) async {}, cancel: cancel.future);
      cancel.complete();
      await expectLater(flow, throwsA(isA<GoogleSignInException>().having((e) => e.reason, 'reason', SignInFailure.cancelled)));
    });

    test('falls back to userinfo when the id token is unusable', () async {
      var userinfoCalls = 0;
      final client = MockClient((req) async {
        if (req.url.toString() == config.userInfoEndpoint) {
          userinfoCalls++;
          expect(req.headers['authorization'], 'Bearer ya29.access');
          return http.Response(jsonEncode({'sub': '9', 'email': 'zoe@example.com', 'name': 'Zoe'}), 200);
        }
        // An id token for another client must be ignored.
        return http.Response(
            jsonEncode(tokenResponse(claims: {'iss': 'https://accounts.google.com', 'aud': 'someone-else', 'email': 'evil@x'})),
            200);
      });
      final tokens = await GoogleOAuth(config, httpClient: client)
          .exchangeCode(code: 'c', codeVerifier: 'v', redirectUri: Uri.parse('http://127.0.0.1:1'));
      expect(tokens.email, 'zoe@example.com');
      expect(tokens.subject, '9');
      expect(userinfoCalls, 1);
    });
  });

  group('refresh and revoke', () {
    final tokens = GoogleTokens(
      accessToken: 'old',
      refreshToken: '1//refresh',
      expiry: now,
      email: 'zoe@example.com',
      name: 'Zoë',
      scopes: const ['https://mail.google.com/'],
    );

    test('refresh keeps the refresh token and identity', () async {
      final oauth = GoogleOAuth(config, clock: () => now, httpClient: MockClient((req) async {
        final form = Uri.splitQueryString(req.body);
        expect(form['grant_type'], 'refresh_token');
        expect(form['refresh_token'], '1//refresh');
        return http.Response(jsonEncode({'access_token': 'new', 'expires_in': 3600, 'token_type': 'Bearer'}), 200);
      }));
      final fresh = await oauth.refresh(tokens);
      expect(fresh.accessToken, 'new');
      expect(fresh.refreshToken, '1//refresh');
      expect(fresh.expiry, now.add(const Duration(hours: 1)));
      expect(fresh.email, 'zoe@example.com');
      expect(fresh.name, 'Zoë');
      expect(fresh.scopes, tokens.scopes);
    });

    test('maps token endpoint failures', () async {
      Future<Object> error(int status, String body) async {
        try {
          await GoogleOAuth(config, httpClient: MockClient((_) async => http.Response(body, status))).refresh(tokens);
        } on Object catch (e) {
          return e;
        }
        fail('expected failure');
      }

      expect(await error(400, '{"error":"invalid_grant","error_description":"Token has been expired or revoked."}'),
          isA<AuthException>());
      expect(await error(401, '{"error":"invalid_client"}'), isA<AuthException>());
      expect(await error(503, 'unavailable'), isA<TransientException>());
      expect(await error(400, '{"error":"invalid_request"}'), isA<PermanentException>());
      final offline = GoogleOAuth(config, httpClient: MockClient((_) async => throw const SocketException('offline')));
      await expectLater(offline.refresh(tokens), throwsA(isA<TransientException>()));
    });

    test('revoke posts the refresh token; already revoked is fine', () async {
      String? sent;
      var status = 200;
      final oauth = GoogleOAuth(config, httpClient: MockClient((req) async {
        expect(req.url.toString(), config.revocationEndpoint);
        sent = Uri.splitQueryString(req.body)['token'];
        return http.Response(status == 200 ? '' : '{"error":"invalid_token"}', status);
      }));
      await oauth.revoke(tokens);
      expect(sent, '1//refresh');
      status = 400;
      await oauth.revoke(tokens);
    });
  });

  group('GoogleTokens', () {
    test('round-trips through JSON and never prints tokens', () {
      final t = GoogleTokens(
        accessToken: 'secret-access',
        refreshToken: 'secret-refresh',
        expiry: DateTime.utc(2026, 1, 2, 3, 4, 5),
        email: 'zoe@example.com',
        name: 'Zoë',
        picture: 'https://x/p.png',
        subject: '42',
        scopes: const ['https://mail.google.com/', 'openid'],
      );
      final back = GoogleTokens.fromJson((jsonDecode(jsonEncode(t.toJson())) as Map).cast<String, Object?>());
      expect(back.accessToken, t.accessToken);
      expect(back.refreshToken, t.refreshToken);
      expect(back.expiry, t.expiry);
      expect(back.email, t.email);
      expect(back.name, t.name);
      expect(back.picture, t.picture);
      expect(back.subject, t.subject);
      expect(back.scopes, t.scopes);
      expect(t.toString(), isNot(contains('secret')));
      expect(() => GoogleTokens.fromJson({'email': 'x'}), throwsFormatException);
    });
  });

  group('GoogleTokenSource', () {
    late DateTime clock;
    late int refreshCalls;
    late Completer<void>? gate;
    late http.Response Function() respond;

    GoogleOAuth oauth() => GoogleOAuth(config, clock: () => clock, httpClient: MockClient((_) async {
          refreshCalls++;
          await gate?.future;
          return respond();
        }));

    GoogleTokens tokens({required DateTime expiry}) =>
        GoogleTokens(accessToken: 'a0', refreshToken: 'r', expiry: expiry, email: 'zoe@example.com');

    setUp(() {
      clock = now;
      refreshCalls = 0;
      gate = null;
      var n = 0;
      respond = () => http.Response(jsonEncode({'access_token': 'a${++n}', 'expires_in': 3600}), 200);
    });

    test('uses the current token until it nears expiry', () async {
      final source = GoogleTokenSource(oauth(), tokens(expiry: now.add(const Duration(minutes: 30))), clock: () => clock);
      expect(await source.accessToken(), 'a0');
      clock = now.add(const Duration(minutes: 26));
      expect(await source.accessToken(), 'a1');
      expect(refreshCalls, 1);
    });

    test('de-duplicates concurrent refreshes and persists once', () async {
      final persisted = <GoogleTokens>[];
      gate = Completer<void>();
      final source = GoogleTokenSource(oauth(), tokens(expiry: now), onTokensChanged: persisted.add, clock: () => clock);
      final results = Future.wait([for (var i = 0; i < 5; i++) source.accessToken()]);
      await Future<void>.delayed(Duration.zero);
      gate!.complete();
      expect(await results, List.filled(5, 'a1'));
      expect(refreshCalls, 1);
      expect(persisted.single.accessToken, 'a1');
      expect(source.tokens!.accessToken, 'a1');
    });

    test('invalidate forces a refresh', () async {
      final source = GoogleTokenSource(oauth(), tokens(expiry: now.add(const Duration(hours: 1))), clock: () => clock);
      expect(await source.accessToken(), 'a0');
      source.invalidate();
      expect(await source.accessToken(), 'a1');
      expect(await source.accessToken(), 'a1');
      expect(refreshCalls, 1);
    });

    test('a revoked grant fails fast until new tokens are installed', () async {
      respond = () => http.Response('{"error":"invalid_grant"}', 400);
      final source = GoogleTokenSource(oauth(), tokens(expiry: now), clock: () => clock);
      await expectLater(source.accessToken(), throwsA(isA<AuthException>()));
      await expectLater(source.accessToken(), throwsA(isA<AuthException>()));
      expect(refreshCalls, 1);
      source.replaceTokens(tokens(expiry: now.add(const Duration(hours: 1))).copyWith(accessToken: 'signed-in-again'));
      expect(await source.accessToken(), 'signed-in-again');
    });

    test('a failed pre-emptive refresh keeps using a still-valid token', () async {
      respond = () => http.Response('busy', 503);
      final source = GoogleTokenSource(oauth(), tokens(expiry: now.add(const Duration(minutes: 3))), clock: () => clock);
      expect(await source.accessToken(), 'a0');
      source.invalidate();
      await expectLater(source.accessToken(), throwsA(isA<TransientException>()));
    });

    test('deferred sources load stored tokens once, on first use', () async {
      var loads = 0;
      final source = GoogleTokenSource.deferred(oauth(), clock: () => clock, load: () async {
        loads++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return tokens(expiry: now.add(const Duration(hours: 1)));
      });
      expect(source.tokens, isNull);
      expect(await Future.wait([source.accessToken(), source.accessToken()]), ['a0', 'a0']);
      expect(loads, 1);
      expect(refreshCalls, 0);

      final missing = GoogleTokenSource.deferred(oauth(), load: () async => null);
      await expectLater(missing.accessToken(), throwsA(isA<AuthException>()));

      var attempt = 0;
      final flaky = GoogleTokenSource.deferred(oauth(), clock: () => clock, load: () async {
        if (attempt++ == 0) throw const FileSystemException('keyring locked');
        return tokens(expiry: now.add(const Duration(hours: 1)));
      });
      await expectLater(flaky.accessToken(), throwsA(isA<TransientException>()));
      expect(await flaky.accessToken(), 'a0');
    });

    test('persistence failures do not break token delivery', () async {
      final source = GoogleTokenSource(oauth(), tokens(expiry: now),
          onTokensChanged: (_) => throw const FileSystemException('keyring locked'), clock: () => clock);
      expect(await source.accessToken(), 'a1');
    });
  });
}
