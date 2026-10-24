/// One Gmail REST call, independent of how it is sent (alone or in a batch).
final class GmailRequest {
  const GmailRequest(
    this.method,
    this.path, {
    this.query = const {},
    this.body,
    required this.cost,
    this.media,
    this.idempotent = true,
  });

  /// `GET`, `POST`, `PUT` or `DELETE`.
  final String method;

  /// Path relative to `/gmail/v1/users/me/`, e.g. `threads/abc`.
  final String path;

  /// Query parameters. Values are a `String` or a `List<String>` for
  /// repeated parameters such as `metadataHeaders`.
  final Map<String, Object> query;

  /// JSON request body, or the metadata part of a media upload.
  final Object? body;

  /// Gmail quota units this call consumes.
  final int cost;

  /// When set, the request is sent to the `/upload` endpoint as a
  /// `multipart/related` media upload with this `message/rfc822` content.
  final List<int>? media;

  /// Whether the call may be repeated after an ambiguous failure (network
  /// error or 5xx after the request may have been processed). Sending mail
  /// is not idempotent and is only retried when Gmail rejected it outright.
  final bool idempotent;

  /// URL-encoded query string, without the leading `?`.
  String get queryString {
    final parts = <String>[];
    for (final e in query.entries) {
      final key = Uri.encodeQueryComponent(e.key);
      final value = e.value;
      if (value is List<String>) {
        for (final v in value) {
          parts.add('$key=${Uri.encodeQueryComponent(v)}');
        }
      } else {
        parts.add('$key=${Uri.encodeQueryComponent(value.toString())}');
      }
    }
    return parts.join('&');
  }

  /// The URL path and query as used inside a batch body.
  String get relativeUrl {
    final q = queryString;
    return '/gmail/v1/users/me/$path${q.isEmpty ? '' : '?$q'}';
  }

  /// A log-safe description (ids only, never content).
  String get description => '$method $path';

  @override
  String toString() => 'GmailRequest($description)';
}
