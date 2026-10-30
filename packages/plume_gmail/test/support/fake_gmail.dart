import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef FakeResponse = ({int status, String body, Map<String, String> headers});

/// An in-memory Gmail backend behind a [MockClient]: REST endpoints and the
/// batch endpoint, with request logging and failure injection.
///
/// It parses batch requests with its own code, independently of the
/// production codec.
class FakeGmail {
  FakeGmail({this.email = 'me@example.com'});

  final String email;
  final labels = <String, Map<String, Object?>>{};
  final messages = <String, Map<String, Object?>>{};
  final attachments = <String, List<int>>{};

  /// draft id → message id.
  final drafts = <String, String>{};
  String historyId = '5000';
  final history = <Map<String, Object?>>[];
  bool historyExpired = false;
  int historyPageSize = 500;

  /// Every handled request as `METHOD path?query`; batch items are
  /// prefixed with `batch:`.
  final log = <String>[];
  final batchSizes = <int>[];

  /// JSON bodies received, keyed by `METHOD path`.
  final bodies = <String, List<Object?>>{};

  /// Status codes to answer before handling normally, by `METHOD path`.
  final failures = <String, List<int>>{};

  /// Like [failures], but the request is applied first and only the
  /// response is replaced (a "lost response").
  final failuresAfterApplying = <String, List<int>>{};
  final rejectedTokens = <String>{};
  bool reverseBatchParts = false;

  /// Raw MIME of messages sent or saved as drafts.
  final rawMessages = <String, String>{};
  int _next = 1;

  late final MockClient client = MockClient(_handle);

  void addMessage(Map<String, Object?> m) => messages[m['id']! as String] = m;

  void addLabel(Map<String, Object?> l) => labels[l['id']! as String] = l;

  void addSystemLabels() {
    for (final id in [
      'INBOX', 'SENT', 'DRAFT', 'TRASH', 'SPAM', 'IMPORTANT', 'STARRED', 'UNREAD', 'CHAT', //
      'CATEGORY_PERSONAL', 'CATEGORY_SOCIAL', 'CATEGORY_PROMOTIONS', 'CATEGORY_UPDATES', 'CATEGORY_FORUMS',
    ]) {
      addLabel({'id': id, 'name': id, 'type': 'system'});
    }
  }

  List<String> labelsOf(String messageId) => ((messages[messageId]!['labelIds'] as List?) ?? const []).cast<String>();

  void setLabels(String messageId, Iterable<String> labelIds) => messages[messageId]!['labelIds'] = labelIds.toList();

  /// Requests (not batch items) whose log line starts with [prefix].
  List<String> requestsMatching(String prefix) => log.where((l) => l.startsWith(prefix)).toList();

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    final auth = request.headers['authorization'] ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    if (path == '/batch/gmail/v1') return _batch(request, token);
    final upload = path.startsWith('/upload/gmail/v1/users/me/');
    final rel = path.substring((upload ? '/upload/gmail/v1/users/me/' : '/gmail/v1/users/me/').length);
    log.add('${upload ? 'upload:' : ''}${request.method} $rel${request.url.hasQuery ? '?${request.url.query}' : ''}');
    var body = request.body;
    if (upload) body = _uploadToJson(request);
    final r = _dispatch(request.method, rel, request.url.queryParametersAll, body, token);
    return http.Response.bytes(utf8.encode(r.body), r.status,
        headers: {'content-type': 'application/json; charset=UTF-8', ...r.headers});
  }

  /// Converts a multipart/related media upload into the JSON body the
  /// non-upload endpoint would receive.
  String _uploadToJson(http.Request request) {
    final ct = request.headers['content-type']!;
    final boundary = RegExp(r'boundary=([^;]+)').firstMatch(ct)!.group(1)!;
    final text = latin1.decode(request.bodyBytes);
    final sections = text.split('--$boundary');
    final meta = sections[1].substring(sections[1].indexOf('\r\n\r\n') + 4).trim();
    final media = sections[2].substring(sections[2].indexOf('\r\n\r\n') + 4);
    final raw = latin1.encode(media.substring(0, media.length - 2));
    final json = (jsonDecode(meta) as Map).cast<String, Object?>();
    final encoded = base64Url.encode(raw);
    if (json.containsKey('message')) {
      (json['message']! as Map)['raw'] = encoded;
    } else {
      json['raw'] = encoded;
    }
    return jsonEncode(json);
  }

  Future<http.Response> _batch(http.Request request, String token) async {
    final ct = request.headers['content-type']!;
    final boundary = RegExp(r'boundary=("?)([^";]+)\1').firstMatch(ct)!.group(2)!;
    final parts = request.body.split('--$boundary').skip(1).where((p) => !p.startsWith('--')).toList();
    batchSizes.add(parts.length);
    const rb = 'batch_fake_RESPONSE';
    final out = <String>[];
    for (final raw in parts) {
      final p = raw.startsWith('\r\n') ? raw.substring(2) : raw;
      final outerEnd = p.indexOf('\r\n\r\n');
      final contentId = RegExp(r'Content-ID: <([^>]+)>').firstMatch(p.substring(0, outerEnd))!.group(1)!;
      final inner = p.substring(outerEnd + 4);
      final lineEnd = inner.indexOf('\r\n');
      final requestLine = inner.substring(0, lineEnd).split(' ');
      final rest = inner.substring(lineEnd + 2);
      final subBody = rest.startsWith('\r\n') ? rest.substring(2).trim() : rest.substring(rest.indexOf('\r\n\r\n') + 4).trim();
      final uri = Uri.parse('https://gmail.googleapis.com${requestLine[1]}');
      final rel = uri.path.substring('/gmail/v1/users/me/'.length);
      log.add('batch:${requestLine[0]} $rel${uri.hasQuery ? '?${uri.query}' : ''}');
      final r = _dispatch(requestLine[0], rel, uri.queryParametersAll, subBody, token);
      final sb = StringBuffer()
        ..write('Content-Type: application/http\r\nContent-ID: <response-$contentId>\r\n\r\n')
        ..write('HTTP/1.1 ${r.status} ${r.status == 200 ? 'OK' : 'Error'}\r\n')
        ..write('Content-Type: application/json; charset=UTF-8\r\n');
      r.headers.forEach((k, v) => sb.write('$k: $v\r\n'));
      sb.write('\r\n${r.body}\r\n');
      out.add(sb.toString());
    }
    final ordered = reverseBatchParts ? out.reversed : out;
    final body = '${ordered.map((p) => '--$rb\r\n$p').join()}--$rb--\r\n';
    return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'multipart/mixed; boundary=$rb'});
  }

  FakeResponse _dispatch(String method, String rel, Map<String, List<String>> query, String body, String token) {
    if (rejectedTokens.contains(token)) return _error(401, 'Invalid Credentials', 'authError');
    final key = '$method $rel';
    if (body.isNotEmpty) bodies.putIfAbsent(key, () => []).add(jsonDecode(body));
    final queued = failures[key];
    if (queued != null && queued.isNotEmpty) {
      final status = queued.removeAt(0);
      return switch (status) {
        429 => _error(429, 'Too many requests', 'rateLimitExceeded', headers: {'retry-after': '1'}),
        403 => _error(403, 'User rate limit exceeded', 'userRateLimitExceeded'),
        _ => _error(status, 'Injected failure', 'backendError'),
      };
    }
    try {
      final result = _route(method, rel.split('/'), query, body.isEmpty ? null : jsonDecode(body));
      final after = failuresAfterApplying[key];
      if (after != null && after.isNotEmpty) return _error(after.removeAt(0), 'Lost response', 'backendError');
      return result;
    } on _NotFound {
      return _error(404, 'Requested entity was not found.', 'notFound');
    }
  }

  FakeResponse _ok(Object? json) => (status: 200, body: json == null ? '' : jsonEncode(json), headers: const {});

  FakeResponse _error(int status, String message, String reason, {Map<String, String> headers = const {}}) => (
        status: status,
        body: jsonEncode({
          'error': {
            'code': status,
            'message': message,
            'errors': [
              {'message': message, 'domain': 'global', 'reason': reason},
            ],
          },
        }),
        headers: headers,
      );

  FakeResponse _route(String method, List<String> seg, Map<String, List<String>> q, Object? json) {
    final body = json is Map ? json.cast<String, Object?>() : const <String, Object?>{};
    String? one(String k) => q[k]?.first;
    switch ((method, seg)) {
      case ('GET', ['profile']):
        return _ok({'emailAddress': email, 'historyId': historyId, 'messagesTotal': messages.length});
      case ('GET', ['labels']):
        return _ok({'labels': labels.values.toList()});
      case ('GET', ['labels', final id]):
        return _ok(_labelWithCounts(id));
      case ('GET', ['threads']):
        return _ok(_listThreads(q));
      case ('GET', ['threads', final id]):
        final msgs = _threadMessages(id);
        if (msgs.isEmpty) throw _NotFound();
        return _ok({
          'id': id,
          'historyId': historyId,
          'messages': [for (final m in msgs) _format(m, one('format') ?? 'full', q['metadataHeaders'] ?? const [])],
        });
      case ('DELETE', ['threads', final id]):
        final msgs = _threadMessages(id);
        if (msgs.isEmpty) throw _NotFound();
        for (final m in msgs) {
          messages.remove(m['id']);
        }
        return _ok(null);
      case ('POST', ['threads', final id, final action]):
        final msgs = _threadMessages(id);
        if (msgs.isEmpty) throw _NotFound();
        for (final m in msgs) {
          _applyAction(m['id']! as String, action, body);
        }
        return _ok({'id': id});
      case ('GET', ['messages']):
        final query = one('q') ?? '';
        final wanted = query.startsWith('rfc822msgid:') ? query.substring(12) : null;
        final hits = [
          for (final e in rawMessages.entries)
            if (wanted != null && e.value.contains('Message-ID: <$wanted>') && messages.containsKey(e.key)) {'id': e.key},
        ];
        return _ok({'messages': hits, 'resultSizeEstimate': hits.length});
      case ('POST', ['messages', 'batchModify']):
        for (final id in (body['ids']! as List).cast<String>()) {
          if (messages.containsKey(id)) _applyAction(id, 'modify', body);
        }
        return _ok(null);
      case ('POST', ['messages', 'batchDelete']):
        for (final id in (body['ids']! as List).cast<String>()) {
          messages.remove(id);
        }
        return _ok(null);
      case ('POST', ['messages', 'send']):
        return _ok(_storeRaw(body, ['SENT']));
      case ('GET', ['messages', final id]):
        final m = messages[id] ?? (throw _NotFound());
        return _ok(_format(m, one('format') ?? 'full', q['metadataHeaders'] ?? const []));
      case ('POST', ['messages', final id, final action]):
        if (!messages.containsKey(id)) throw _NotFound();
        _applyAction(id, action, body);
        return _ok({'id': id});
      case ('GET', ['messages', final id, 'attachments', final aid]):
        if (!messages.containsKey(id)) throw _NotFound();
        final bytes = attachments[aid] ?? (throw _NotFound());
        return _ok({'size': bytes.length, 'data': base64Url.encode(bytes)});
      case ('GET', ['history']):
        if (historyExpired) throw _NotFound();
        final start = int.parse(one('startHistoryId')!);
        final records = [for (final h in history) if (int.parse(h['id']! as String) > start) h];
        final offset = int.tryParse(one('pageToken') ?? '') ?? 0;
        final page = records.skip(offset).take(historyPageSize).toList();
        final more = offset + page.length < records.length;
        return _ok({
          if (page.isNotEmpty) 'history': page,
          'historyId': historyId,
          if (more) 'nextPageToken': '${offset + page.length}',
        });
      case ('GET', ['drafts']):
        final all = [
          for (final e in drafts.entries) {'id': e.key, 'message': {'id': e.value, 'threadId': messages[e.value]?['threadId']}},
        ];
        final size = int.tryParse(one('maxResults') ?? '') ?? 100;
        final offset = int.tryParse(one('pageToken') ?? '') ?? 0;
        final page = all.skip(offset).take(size).toList();
        return _ok({
          'drafts': page,
          if (offset + page.length < all.length) 'nextPageToken': '${offset + page.length}',
        });
      case ('POST', ['drafts']):
        final message = (body['message']! as Map).cast<String, Object?>();
        final stored = _storeRaw(message, ['DRAFT']);
        final draftId = 'draft-${_next++}';
        drafts[draftId] = stored['id']! as String;
        return _ok({'id': draftId, 'message': stored});
      case ('PUT', ['drafts', final id]):
        if (!drafts.containsKey(id)) throw _NotFound();
        messages.remove(drafts[id]);
        final stored = _storeRaw((body['message']! as Map).cast<String, Object?>(), ['DRAFT']);
        drafts[id] = stored['id']! as String;
        return _ok({'id': id, 'message': stored});
      case ('POST', ['drafts', 'send']):
        final id = body['id']! as String;
        if (!drafts.containsKey(id)) throw _NotFound();
        messages.remove(drafts.remove(id));
        return _ok(_storeRaw((body['message']! as Map).cast<String, Object?>(), ['SENT']));
      case ('DELETE', ['drafts', final id]):
        if (!drafts.containsKey(id)) throw _NotFound();
        messages.remove(drafts.remove(id));
        return _ok(null);
      default:
        return _error(400, 'Unsupported fake route $method ${seg.join('/')}', 'badRequest');
    }
  }

  Map<String, Object?> _storeRaw(Map<String, Object?> body, List<String> labelIds) {
    final raw = utf8.decode(base64Url.decode(base64Url.normalize(body['raw']! as String)));
    final id = 'new-${_next++}';
    final threadId = (body['threadId'] as String?) ?? 'thread-$id';
    rawMessages[id] = raw;
    messages[id] = {
      'id': id,
      'threadId': threadId,
      'labelIds': labelIds,
      'snippet': '',
      'internalDate': '1700000999000',
      'payload': {'mimeType': 'text/plain', 'headers': <Object?>[], 'body': {'size': 0}},
    };
    return {'id': id, 'threadId': threadId, 'labelIds': labelIds};
  }

  void _applyAction(String id, String action, Map<String, Object?> body) {
    final labels = labelsOf(id).toSet();
    switch (action) {
      case 'modify':
        labels
          ..addAll(((body['addLabelIds'] as List?) ?? const []).cast<String>())
          ..removeAll(((body['removeLabelIds'] as List?) ?? const []).cast<String>());
      case 'trash':
        labels
          ..add('TRASH')
          ..remove('INBOX');
      case 'untrash':
        labels.remove('TRASH');
    }
    setLabels(id, labels);
  }

  List<Map<String, Object?>> _threadMessages(String threadId) {
    final list = messages.values.where((m) => m['threadId'] == threadId).toList()
      ..sort((a, b) => int.parse(a['internalDate']! as String).compareTo(int.parse(b['internalDate']! as String)));
    return list;
  }

  Map<String, Object?> _listThreads(Map<String, List<String>> q) {
    final labelIds = q['labelIds'] ?? const [];
    var text = q['q']?.first ?? '';
    final includeSpamTrash = q['includeSpamTrash']?.first == 'true';
    final excludeSpamTrash = text.contains('-in:spam') || text.contains('-in:trash');
    text = text.replaceAll('-in:spam', '').replaceAll('-in:trash', '').trim().toLowerCase();
    final byThread = <String, List<Map<String, Object?>>>{};
    for (final m in messages.values) {
      byThread.putIfAbsent(m['threadId']! as String, () => []).add(m);
    }
    bool spamOrTrash(Map<String, Object?> m) {
      final l = (m['labelIds']! as List).cast<String>();
      return l.contains('SPAM') || l.contains('TRASH');
    }

    final matching = <(String, int)>[];
    for (final e in byThread.entries) {
      final msgs = e.value;
      if (labelIds.isNotEmpty &&
          !msgs.any((m) => labelIds.every((l) => (m['labelIds']! as List).contains(l)))) {
        continue;
      }
      final explicitSpamTrash = labelIds.contains('SPAM') || labelIds.contains('TRASH');
      if ((excludeSpamTrash || (!includeSpamTrash && !explicitSpamTrash)) && msgs.every(spamOrTrash)) continue;
      if (text.isNotEmpty &&
          !msgs.any((m) => _subject(m).toLowerCase().contains(text))) {
        continue;
      }
      final latest = msgs.map((m) => int.parse(m['internalDate']! as String)).reduce((a, b) => a > b ? a : b);
      matching.add((e.key, latest));
    }
    matching.sort((a, b) => b.$2.compareTo(a.$2));
    final offset = int.tryParse(q['pageToken']?.first ?? '') ?? 0;
    final max = int.tryParse(q['maxResults']?.first ?? '') ?? 100;
    final page = matching.skip(offset).take(max).toList();
    final more = offset + page.length < matching.length;
    return {
      'threads': [for (final t in page) {'id': t.$1, 'historyId': historyId, 'snippet': ''}],
      'resultSizeEstimate': matching.length,
      if (more) 'nextPageToken': '${offset + page.length}',
    };
  }

  static String _subject(Map<String, Object?> m) {
    final headers = (((m['payload'] as Map?)?['headers'] as List?) ?? const []).cast<Map<String, Object?>>();
    return headers.firstWhere((h) => (h['name']! as String).toLowerCase() == 'subject',
        orElse: () => {'value': ''})['value']! as String;
  }

  Map<String, Object?> _labelWithCounts(String id) {
    final label = labels[id] ?? (throw _NotFound());
    final threads = <String>{};
    final unread = <String>{};
    var messagesTotal = 0;
    for (final m in messages.values) {
      final l = (m['labelIds']! as List).cast<String>();
      if (!l.contains(id)) continue;
      messagesTotal++;
      threads.add(m['threadId']! as String);
      if (l.contains('UNREAD')) unread.add(m['threadId']! as String);
    }
    return {
      ...label,
      'messagesTotal': messagesTotal,
      'threadsTotal': threads.length,
      'threadsUnread': unread.length,
    };
  }

  Map<String, Object?> _format(Map<String, Object?> m, String format, List<String> metadataHeaders) {
    final minimal = {
      for (final k in ['id', 'threadId', 'labelIds', 'snippet', 'historyId', 'internalDate', 'sizeEstimate'])
        if (m.containsKey(k)) k: m[k],
    };
    if (format == 'minimal') return minimal;
    if (format == 'full') return m;
    final payload = (m['payload']! as Map).cast<String, Object?>();
    final wanted = metadataHeaders.map((h) => h.toLowerCase()).toSet();
    final headers = ((payload['headers'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .where((h) => wanted.isEmpty || wanted.contains((h['name']! as String).toLowerCase()))
        .toList();
    return {
      ...minimal,
      'payload': {
        'partId': '',
        'mimeType': payload['mimeType'],
        'filename': '',
        'headers': headers,
        'body': {'size': 0},
      },
    };
  }
}

class _NotFound implements Exception {}

/// A history record JSON.
Map<String, Object?> historyRecord(
  String id, {
  List<Map<String, Object?>> added = const [],
  List<Map<String, Object?>> deleted = const [],
  List<(Map<String, Object?>, List<String>)> labelsAdded = const [],
  List<(Map<String, Object?>, List<String>)> labelsRemoved = const [],
}) {
  Map<String, Object?> stub(Map<String, Object?> m) =>
      {'id': m['id'], 'threadId': m['threadId'], 'labelIds': m['labelIds']};
  return {
    'id': id,
    'messages': [for (final m in [...added, ...deleted]) stub(m)],
    if (added.isNotEmpty) 'messagesAdded': [for (final m in added) {'message': stub(m)}],
    if (deleted.isNotEmpty) 'messagesDeleted': [for (final m in deleted) {'message': stub(m)}],
    if (labelsAdded.isNotEmpty)
      'labelsAdded': [for (final (m, l) in labelsAdded) {'message': stub(m), 'labelIds': l}],
    if (labelsRemoved.isNotEmpty)
      'labelsRemoved': [for (final (m, l) in labelsRemoved) {'message': stub(m), 'labelIds': l}],
  };
}
