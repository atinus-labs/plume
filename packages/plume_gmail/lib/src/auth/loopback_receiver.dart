import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'oauth_pages.dart';

final Logger _log = Logger('plume.gmail.oauth');

/// Why an interactive sign-in did not produce tokens.
enum SignInFailure {
  /// The app cancelled the flow.
  cancelled,

  /// The browser never came back within the timeout.
  timedOut,

  /// The user declined on Google's consent screen.
  accessDenied,

  /// The redirect carried an unexpected `state` (possible forgery).
  stateMismatch,

  /// The user unticked a required permission (e.g. Gmail access).
  missingScopes,

  /// The browser could not be opened, or Google returned an error.
  failed,
}

/// The interactive sign-in flow ended without tokens. Token endpoint
/// failures are reported as core `MailException`s instead.
final class GoogleSignInException implements Exception {
  const GoogleSignInException(this.reason, this.message);

  final SignInFailure reason;
  final String message;

  @override
  String toString() => 'GoogleSignInException(${reason.name}): $message';
}

/// PKCE (RFC 7636) verifier and S256 challenge.
final class Pkce {
  const Pkce(this.verifier, this.challenge);

  /// A 43-character verifier from 32 random bytes.
  factory Pkce.generate(Random random) {
    final verifier = randomUrlSafeToken(random, 32);
    return Pkce(verifier, challengeOf(verifier));
  }

  final String verifier;
  final String challenge;

  static String challengeOf(String verifier) => _b64NoPad(sha256.convert(ascii.encode(verifier)).bytes);
}

/// Unpadded base64url of [bytes] random bytes.
String randomUrlSafeToken(Random random, int bytes) =>
    _b64NoPad(List<int>.generate(bytes, (_) => random.nextInt(256)));

String _b64NoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// The authorization response received on the loopback redirect. The
/// browser request is held open until [respond] so the page can report the
/// final outcome of the token exchange.
final class LoopbackCallback {
  LoopbackCallback._(this.code, this._request);

  final String code;
  final HttpRequest _request;
  bool _responded = false;

  Future<void> respond(String html, {int status = HttpStatus.ok}) async {
    if (_responded) return;
    _responded = true;
    await _writePage(_request, status, html);
  }
}

/// A one-shot HTTP server on `127.0.0.1:<random port>` that receives the
/// OAuth redirect (RFC 8252 section 7.3) and validates `state`.
final class LoopbackReceiver {
  LoopbackReceiver._(this._server, this._expectedState) {
    _completer.future.ignore(); // Errors are observed by waitForCallback.
    _server.listen(_handle, onError: (Object e) => _log.fine('Loopback server error: $e'));
  }

  static Future<LoopbackReceiver> start({required String expectedState}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    return LoopbackReceiver._(server, expectedState);
  }

  final HttpServer _server;
  final String _expectedState;
  final _completer = Completer<LoopbackCallback>();
  final _pendingWrites = <Future<void>>{};

  Uri get redirectUri => Uri.parse('http://127.0.0.1:${_server.port}');

  /// Completes with the authorization code, or fails with a
  /// [GoogleSignInException] on denial, state mismatch, timeout or cancel.
  Future<LoopbackCallback> waitForCallback({required Duration timeout, Future<void>? cancel}) {
    final timer = Timer(timeout, () {
      _fail(const GoogleSignInException(SignInFailure.timedOut, 'Sign-in timed out.'));
    });
    cancel?.then((_) => _fail(const GoogleSignInException(SignInFailure.cancelled, 'Sign-in was cancelled.'))).ignore();
    return _completer.future.whenComplete(timer.cancel);
  }

  /// Stops listening once in-flight pages have been delivered.
  Future<void> close() async {
    await _server.close();
    if (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList()).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    }
    await _server.close(force: true);
  }

  void _track(Future<void> write) {
    _pendingWrites.add(write);
    write.whenComplete(() => _pendingWrites.remove(write)).ignore();
  }

  void _fail(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }

  void _handle(HttpRequest request) {
    final q = request.uri.queryParameters;
    final isCallback = q.containsKey('code') || q.containsKey('error') || q.containsKey('state');
    if (request.method != 'GET' || request.uri.path != '/' || !isCallback) {
      _track(_writeText(request, HttpStatus.notFound, 'Not found'));
      return;
    }
    if (_completer.isCompleted) {
      _track(_writePage(request, HttpStatus.ok,
          failurePage(reason: 'This sign-in link was already used. Return to Plume to start again.')));
      return;
    }
    final state = q['state'];
    if (state == null || !_constantTimeEquals(state, _expectedState)) {
      _track(_writePage(request, HttpStatus.badRequest,
          failurePage(reason: 'The response from Google did not match this sign-in attempt.')));
      _fail(const GoogleSignInException(SignInFailure.stateMismatch, 'OAuth state mismatch.'));
      return;
    }
    final error = q['error'];
    if (error != null) {
      final denied = error == 'access_denied';
      _track(_writePage(request, HttpStatus.ok,
          failurePage(reason: denied ? 'Access was not granted.' : 'Google reported an error: $error.')));
      _fail(GoogleSignInException(
        denied ? SignInFailure.accessDenied : SignInFailure.failed,
        denied ? 'Access was not granted.' : 'Google reported an error: $error',
      ));
      return;
    }
    final code = q['code'];
    if (code == null || code.isEmpty) {
      _track(_writePage(request, HttpStatus.badRequest, failurePage(reason: 'Google did not return an authorization code.')));
      _fail(const GoogleSignInException(SignInFailure.failed, 'No authorization code in the redirect.'));
      return;
    }
    _completer.complete(LoopbackCallback._(code, request));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

Future<void> _writePage(HttpRequest request, int status, String html) async {
  try {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store')
      ..headers.set('referrer-policy', 'no-referrer')
      ..headers.set('x-content-type-options', 'nosniff')
      ..headers.set('content-security-policy', "default-src 'none'; style-src 'unsafe-inline'")
      ..write(html);
    await request.response.close();
  } on Object catch (e) {
    _log.fine('Could not write the sign-in page: $e');
  }
}

Future<void> _writeText(HttpRequest request, int status, String text) async {
  try {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(text);
    await request.response.close();
  } on Object catch (_) {
    // The browser went away.
  }
}
