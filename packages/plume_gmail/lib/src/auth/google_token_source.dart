import 'dart:async';

import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';

import 'google_oauth.dart';
import 'google_tokens.dart';

final Logger _log = Logger('plume.gmail.oauth');

/// A [TokenSource] backed by Google OAuth tokens.
///
/// * Refreshes when the access token is within [refreshMargin] of expiry,
///   or after [invalidate] (a 401 from Gmail).
/// * Concurrent callers share one in-flight refresh.
/// * Reports new tokens through `onTokensChanged` so the app can persist
///   them (persistence errors are logged, not propagated).
/// * After a refresh fails with [AuthException] (revoked access), further
///   calls fail fast with the same error until [replaceTokens] is called
///   with tokens from a new sign-in.
/// * If a refresh fails transiently while the current token is still
///   valid (refresh was only pre-emptive), the current token is used.
final class GoogleTokenSource implements TokenSource {
  /// A source for tokens already in memory (e.g. right after sign-in).
  GoogleTokenSource(
    this._oauth,
    GoogleTokens tokens, {
    this._onTokensChanged,
    this.refreshMargin = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _tokens = tokens,
        _load = null,
        _clock = clock ?? DateTime.now;

  /// A source that reads the stored tokens on first use, for wiring the
  /// engine's synchronous `tokenSourceFor(account)` to an asynchronous
  /// secret store. [load] returning null means the account has no stored
  /// credentials ([AuthException]); a failing [load] is reported as a
  /// [TransientException] and retried on the next call.
  GoogleTokenSource.deferred(
    this._oauth, {
    required Future<GoogleTokens?> Function() this._load,
    this._onTokensChanged,
    this.refreshMargin = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _tokens = null,
        _clock = clock ?? DateTime.now;

  final GoogleOAuth _oauth;
  final FutureOr<void> Function(GoogleTokens tokens)? _onTokensChanged;
  final Future<GoogleTokens?> Function()? _load;
  final Duration refreshMargin;
  final DateTime Function() _clock;

  GoogleTokens? _tokens;
  Future<GoogleTokens>? _loading;
  bool _invalidated = false;
  Future<GoogleTokens>? _inflight;
  AuthException? _failure;

  /// The current tokens, or null while a deferred source has not loaded.
  GoogleTokens? get tokens => _tokens;

  /// Installs tokens from a new sign-in, clearing any auth failure.
  void replaceTokens(GoogleTokens tokens) {
    _tokens = tokens;
    _invalidated = false;
    _failure = null;
  }

  @override
  Future<String> accessToken() async {
    final failure = _failure;
    if (failure != null) throw failure;
    final current = await _current();
    if (!_invalidated && !current.expiresWithin(refreshMargin, _clock())) return current.accessToken;
    final wasInvalidated = _invalidated;
    try {
      return (await _refresh()).accessToken;
    } on TransientException {
      final stillValid = !current.expiresWithin(const Duration(seconds: 30), _clock());
      if (!wasInvalidated && stillValid && identical(current, _tokens)) return current.accessToken;
      rethrow;
    }
  }

  @override
  void invalidate() {
    _invalidated = true;
  }

  Future<GoogleTokens> _current() {
    final tokens = _tokens;
    if (tokens != null) return Future.value(tokens);
    return _loading ??= _loadStored();
  }

  Future<GoogleTokens> _loadStored() async {
    try {
      final loaded = await _load!();
      if (loaded == null) throw const AuthException('No stored Google credentials; sign in again');
      // A sign-in may have installed tokens while loading.
      return _tokens ??= loaded;
    } on MailException {
      _loading = null;
      rethrow;
    } on Object catch (e) {
      _loading = null;
      throw TransientException('Could not read stored Google credentials', e);
    }
  }

  Future<GoogleTokens> _refresh() => _inflight ??= _doRefresh().whenComplete(() => _inflight = null);

  Future<GoogleTokens> _doRefresh() async {
    try {
      final fresh = await _oauth.refresh(await _current());
      _tokens = fresh;
      _invalidated = false;
      _log.fine('Access token refreshed');
      final callback = _onTokensChanged;
      if (callback != null) {
        try {
          await callback(fresh);
        } on Object catch (e, st) {
          _log.warning('Persisting refreshed tokens failed', e, st);
        }
      }
      return fresh;
    } on AuthException catch (e) {
      _failure = e;
      rethrow;
    }
  }
}
