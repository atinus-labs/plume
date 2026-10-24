import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';

import '../util/backoff.dart';
import '../util/json.dart';
import '../util/mutex.dart';
import 'batch_codec.dart';
import 'gmail_request.dart';
import 'quota.dart';

final Logger _log = Logger('plume.gmail.api');

/// Outcome of one sub-request of a batch.
sealed class BatchOutcome {
  const BatchOutcome();
}

final class BatchSuccess extends BatchOutcome {
  const BatchSuccess(this.json);

  /// Decoded JSON body, or null for empty responses.
  final Object? json;
}

final class BatchFailure extends BatchOutcome {
  const BatchFailure(this.error);

  final MailException error;
}

/// Transport settings for [GmailClient].
final class GmailClientConfig {
  const GmailClientConfig({
    this.baseUrl = 'https://gmail.googleapis.com',
    this.maxRetries = 5,
    this.backoff = const RetryBackoff(),
    this.requestTimeout = const Duration(seconds: 60),
    this.bodyTimeout = const Duration(minutes: 10),
    this.maxRetryAfterWait = const Duration(seconds: 60),
    this.quota = const GmailQuota(),
    this.userAgent = 'Plume/0.1 (gzip)',
  });

  final String baseUrl;

  /// Retries after the first attempt for retryable failures.
  final int maxRetries;
  final RetryBackoff backoff;

  /// Time allowed until response headers arrive (includes the upload).
  final Duration requestTimeout;

  /// Time allowed to read a response body (large attachments).
  final Duration bodyTimeout;

  /// A `Retry-After` longer than this is not waited out in-process; the
  /// call fails with a [TransientException] carrying the delay instead.
  final Duration maxRetryAfterWait;
  final GmailQuota quota;

  /// Google only serves gzip to clients whose user agent contains "gzip".
  final String userAgent;
}

/// Low-level Gmail REST transport: authentication, quota pacing, retries
/// with backoff, batching, and mapping of failures onto core exceptions.
///
/// * 401: [TokenSource.invalidate] and retry once, then [AuthException].
/// * 429, 5xx, `rateLimitExceeded`, `userRateLimitExceeded`: exponential
///   backoff with jitter, honouring `Retry-After`; then [TransientException].
/// * Network failures: retried like 5xx; then [TransientException].
/// * 404: [NotFoundException]. Other 4xx: [PermanentException].
///   403 for missing OAuth scopes: [AuthException].
///
/// Batches are never sent in parallel: one client = one account, and its
/// batches are serialised and paced by a [QuotaLimiter].
final class GmailClient {
  GmailClient({
    required this._tokens,
    http.Client? httpClient,
    this.config = const GmailClientConfig(),
    Random? random,
    Sleep? sleep,
    DateTime Function()? clock,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _random = random ?? Random(),
        _sleep = sleep ?? defaultSleep,
        _clock = clock ?? DateTime.now {
    _limiter = QuotaLimiter(config.quota, clock: _clock, sleep: _sleep);
  }

  final TokenSource _tokens;
  final http.Client _http;
  final bool _ownsHttp;
  final GmailClientConfig config;
  final Random _random;
  final Sleep _sleep;
  final DateTime Function() _clock;
  late final QuotaLimiter _limiter;
  final _batchLock = Mutex();
  bool _closed = false;

  /// Sends one request and returns its decoded JSON body (null if empty).
  Future<Object?> send(GmailRequest request) async {
    var attempt = 0;
    var authRetried = false;
    while (true) {
      _checkOpen();
      await _limiter.acquire(request.cost);
      final token = await _tokens.accessToken();
      final http.Response response;
      try {
        response = await _sendHttp(request, token);
      } on Object catch (e) {
        if (!_isNetworkError(e)) rethrow;
        if (request.idempotent && attempt < config.maxRetries) {
          final delay = config.backoff.delay(attempt++, _random);
          _log.fine('${request.description}: network error (${e.runtimeType}), retrying in $delay');
          await _sleep(delay);
          continue;
        }
        throw TransientException('Network error during ${request.description}', e);
      }
      final status = response.statusCode;
      if (status >= 200 && status < 300) return _decodeBody(response.bodyBytes, request.description);

      final error = GoogleApiError.parse(status, _bodyText(response.bodyBytes));
      if (status == 401) {
        if (!authRetried) {
          authRetried = true;
          _log.fine('${request.description}: 401, refreshing token');
          _tokens.invalidate();
          continue;
        }
        throw AuthException('Gmail rejected the access token', error.message);
      }
      final retryAfter = _parseRetryAfter(response.headers['retry-after']);
      final mayRetry = error.isRetryable && (request.idempotent || error.isRejection);
      if (mayRetry && attempt < config.maxRetries && (retryAfter == null || retryAfter <= config.maxRetryAfterWait)) {
        final delay = _maxDuration(retryAfter, config.backoff.delay(attempt++, _random));
        _log.fine('${request.description}: HTTP $status ${error.reasons.join(',')}, retrying in $delay');
        await _sleep(delay);
        continue;
      }
      throw error.toException(request.description, retryAfter: retryAfter);
    }
  }

  /// Sends [requests] using Gmail's batch endpoint and returns one outcome
  /// per request, in order. Requests are grouped into batches bounded by
  /// [GmailQuota.maxBatchSize] and [GmailQuota.maxBatchUnits]; failed
  /// sub-requests that are retryable are retried in follow-up batches.
  ///
  /// Only systemic failures are thrown (e.g. the batch endpoint itself
  /// rejecting the request); per-request failures become [BatchFailure].
  Future<List<BatchOutcome>> batch(List<GmailRequest> requests) async {
    if (requests.isEmpty) return const [];
    final results = List<BatchOutcome?>.filled(requests.length, null);
    for (final chunk in _chunk(requests)) {
      await _batchLock.run(() => _runBatch(requests, chunk, results));
    }
    return [for (final r in results) r ?? const BatchFailure(TransientException('No response for batch item'))];
  }

  void close() {
    _closed = true;
    if (_ownsHttp) _http.close();
  }

  void _checkOpen() {
    if (_closed) throw const PermanentException('Gmail client is closed');
  }

  Iterable<List<int>> _chunk(List<GmailRequest> requests) sync* {
    var current = <int>[];
    var units = 0;
    for (var i = 0; i < requests.length; i++) {
      final cost = requests[i].cost;
      if (current.isNotEmpty &&
          (current.length >= config.quota.maxBatchSize || units + cost > config.quota.maxBatchUnits)) {
        yield current;
        current = <int>[];
        units = 0;
      }
      current.add(i);
      units += cost;
    }
    if (current.isNotEmpty) yield current;
  }

  Future<void> _runBatch(List<GmailRequest> all, List<int> indices, List<BatchOutcome?> results) async {
    var pending = indices;
    var attempt = 0;
    var authRetried = false;
    while (pending.isNotEmpty) {
      _checkOpen();
      if (pending.length == 1) {
        // A batch of one is just overhead.
        final i = pending.single;
        try {
          results[i] = BatchSuccess(await send(all[i]));
        } on MailException catch (e) {
          results[i] = BatchFailure(e);
        }
        return;
      }

      await _limiter.acquire(pending.fold<int>(0, (sum, i) => sum + all[i].cost));
      final token = await _tokens.accessToken();
      final boundary = 'batch_plume_${_random.nextInt(1 << 32).toRadixString(16)}${_random.nextInt(1 << 32).toRadixString(16)}';
      final body = BatchCodec.encode([for (final i in pending) all[i]], boundary, ids: pending);

      http.Response response;
      try {
        final request = http.Request('POST', Uri.parse('${config.baseUrl}/batch/gmail/v1'))
          ..headers.addAll(_commonHeaders(token))
          ..headers['content-type'] = 'multipart/mixed; boundary=$boundary'
          ..bodyBytes = utf8.encode(body);
        response = await _sendRaw(request);
      } on Object catch (e) {
        if (!_isNetworkError(e)) rethrow;
        if (attempt < config.maxRetries) {
          await _sleep(config.backoff.delay(attempt++, _random));
          continue;
        }
        final error = TransientException('Network error during batch', e);
        for (final i in pending) {
          results[i] = BatchFailure(error);
        }
        return;
      }

      final status = response.statusCode;
      if (status < 200 || status >= 300) {
        final error = GoogleApiError.parse(status, _bodyText(response.bodyBytes));
        if (status == 401 && !authRetried) {
          authRetried = true;
          _tokens.invalidate();
          continue;
        }
        final retryAfter = _parseRetryAfter(response.headers['retry-after']);
        if (error.isRetryable && attempt < config.maxRetries && (retryAfter == null || retryAfter <= config.maxRetryAfterWait)) {
          await _sleep(_maxDuration(retryAfter, config.backoff.delay(attempt++, _random)));
          continue;
        }
        if (status == 401) throw AuthException('Gmail rejected the access token', error.message);
        throw error.toException('batch', retryAfter: retryAfter);
      }

      final List<BatchPart> parts;
      try {
        parts = BatchCodec.decode(response.headers['content-type'], response.bodyBytes);
      } on FormatException catch (e) {
        throw TransientException('Malformed batch response', e);
      }
      final byIndex = <int, BatchPart>{};
      for (var p = 0; p < parts.length; p++) {
        final part = parts[p];
        final index = part.index ?? (p < pending.length ? pending[p] : null);
        if (index != null) byIndex[index] = part;
      }

      final retry = <int>[];
      final unauthorized = <int>[];
      Duration? retryAfter;
      for (final i in pending) {
        final part = byIndex[i];
        if (part == null) {
          retry.add(i);
          continue;
        }
        if (part.status >= 200 && part.status < 300) {
          try {
            results[i] = BatchSuccess(_decodeBody(utf8.encode(part.body), all[i].description));
          } on MailException catch (e) {
            results[i] = BatchFailure(e);
          }
          continue;
        }
        final error = GoogleApiError.parse(part.status, part.body);
        if (part.status == 401) {
          unauthorized.add(i);
        } else if (error.isRetryable && (all[i].idempotent || error.isRejection)) {
          retry.add(i);
          retryAfter = _maxDuration(retryAfter, _parseRetryAfter(part.headers['retry-after']));
          results[i] = BatchFailure(error.toException(all[i].description, retryAfter: retryAfter));
        } else {
          results[i] = BatchFailure(error.toException(all[i].description));
        }
      }

      if (unauthorized.isNotEmpty) {
        if (authRetried) {
          for (final i in unauthorized) {
            results[i] = const BatchFailure(AuthException('Gmail rejected the access token'));
          }
        } else {
          authRetried = true;
          _tokens.invalidate();
          retry.addAll(unauthorized);
        }
      }
      if (retry.isEmpty) return;
      if (attempt >= config.maxRetries || (retryAfter != null && retryAfter > config.maxRetryAfterWait)) {
        for (final i in retry) {
          results[i] ??= BatchFailure(TransientException('Gmail kept rejecting ${all[i].description}', null, retryAfter));
        }
        return;
      }
      _log.fine('batch: retrying ${retry.length} of ${pending.length} items');
      await _sleep(_maxDuration(retryAfter, config.backoff.delay(attempt++, _random)));
      for (final i in retry) {
        results[i] = null;
      }
      retry.sort();
      pending = retry;
    }
  }

  Map<String, String> _commonHeaders(String token) => {
        'authorization': 'Bearer $token',
        'user-agent': config.userAgent,
        'accept-encoding': 'gzip',
        'accept': 'application/json',
      };

  Future<http.Response> _sendHttp(GmailRequest r, String token) {
    final media = r.media;
    final http.Request request;
    if (media != null) {
      final q = r.queryString;
      final uri = Uri.parse('${config.baseUrl}/upload/gmail/v1/users/me/${r.path}?${q.isEmpty ? '' : '$q&'}uploadType=multipart');
      final boundary = 'upload_plume_${_random.nextInt(1 << 32).toRadixString(16)}';
      final bytes = BytesBuilder(copy: false)
        ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'))
        ..add(utf8.encode(jsonEncode(r.body ?? const <String, Object?>{})))
        ..add(utf8.encode('\r\n--$boundary\r\nContent-Type: message/rfc822\r\n\r\n'))
        ..add(media)
        ..add(utf8.encode('\r\n--$boundary--\r\n'));
      request = http.Request(r.method, uri)
        ..headers.addAll(_commonHeaders(token))
        ..headers['content-type'] = 'multipart/related; boundary=$boundary'
        ..bodyBytes = bytes.takeBytes();
    } else {
      final q = r.queryString;
      request = http.Request(r.method, Uri.parse('${config.baseUrl}/gmail/v1/users/me/${r.path}${q.isEmpty ? '' : '?$q'}'))
        ..headers.addAll(_commonHeaders(token));
      if (r.body != null) {
        request
          ..headers['content-type'] = 'application/json; charset=utf-8'
          ..bodyBytes = utf8.encode(jsonEncode(r.body));
      }
    }
    return _sendRaw(request);
  }

  Future<http.Response> _sendRaw(http.Request request) async {
    final streamed = await _http.send(request).timeout(config.requestTimeout);
    return http.Response.fromStream(streamed).timeout(config.bodyTimeout);
  }

  Object? _decodeBody(List<int> bytes, String what) {
    final text = _bodyText(bytes);
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw TransientException('Gmail returned a malformed response to $what', e);
    }
  }

  String _bodyText(List<int> bytes) {
    var data = bytes;
    if (data.length >= 2 && data[0] == 0x1F && data[1] == 0x8B) {
      try {
        data = gzip.decode(data);
      } on FormatException {
        // Not actually gzip; use as is.
      }
    }
    return utf8.decode(data, allowMalformed: true);
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
    try {
      final at = HttpDate.parse(value);
      final diff = at.difference(_clock());
      return diff.isNegative ? Duration.zero : diff;
    } on Object {
      return null;
    }
  }

  static bool _isNetworkError(Object e) => e is IOException || e is http.ClientException || e is TimeoutException;

  static Duration _maxDuration(Duration? a, Duration? b) {
    if (a == null) return b ?? Duration.zero;
    if (b == null) return a;
    return a > b ? a : b;
  }
}

/// A parsed Google API error response.
final class GoogleApiError {
  const GoogleApiError({required this.status, required this.message, this.reasons = const {}, this.statusText});

  final int status;
  final String message;

  /// `errors[].reason` values, e.g. `rateLimitExceeded`.
  final Set<String> reasons;

  /// Canonical status, e.g. `PERMISSION_DENIED`.
  final String? statusText;

  static const _rateLimitReasons = {'rateLimitExceeded', 'userRateLimitExceeded', 'concurrentLimitExceeded'};

  static GoogleApiError parse(int status, String body) {
    String message = 'HTTP $status';
    final reasons = <String>{};
    String? statusText;
    try {
      final json = asJsonMap(jsonDecode(body));
      final error = json?.obj('error');
      if (error != null) {
        message = error.str('message') ?? message;
        statusText = error.str('status');
        for (final e in error.objList('errors')) {
          final reason = e.str('reason');
          if (reason != null) reasons.add(reason);
        }
      } else if (json?.str('error') != null) {
        // OAuth-style {"error": "...", "error_description": "..."}.
        reasons.add(json!.str('error')!);
        message = json.str('error_description') ?? message;
      }
    } on FormatException {
      // Non-JSON error bodies (proxies, HTML error pages).
    }
    return GoogleApiError(status: status, message: message, reasons: reasons, statusText: statusText);
  }

  bool get isRateLimited => status == 429 || (status == 403 && reasons.any(_rateLimitReasons.contains));

  /// Retryable in-process: rate limits and server errors.
  bool get isRetryable => isRateLimited || status >= 500 || (status == 403 && reasons.contains('backendError'));

  /// The server refused the request without processing it, so even a
  /// non-idempotent request can be resent.
  bool get isRejection => isRateLimited;

  bool get _isScopeProblem =>
      status == 403 &&
      (reasons.contains('insufficientPermissions') ||
          reasons.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT') ||
          message.toLowerCase().contains('insufficient authentication scopes'));

  MailException toException(String what, {Duration? retryAfter}) {
    final text = '$what failed: $message';
    if (status == 401 || _isScopeProblem) return AuthException(text);
    if (isRetryable || reasons.contains('dailyLimitExceeded') || reasons.contains('quotaExceeded')) {
      return TransientException(text, null, retryAfter);
    }
    if (status == 404) return NotFoundException(text);
    if (status == 408) return TransientException(text, null, retryAfter);
    return PermanentException(text);
  }

  @override
  String toString() => 'GoogleApiError($status, $message, $reasons)';
}
