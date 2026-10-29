import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_gmail/src/api/batch_codec.dart';
import 'package:plume_gmail/src/api/gmail_api.dart';
import 'package:plume_gmail/src/api/gmail_client.dart';
import 'package:plume_gmail/src/api/gmail_request.dart';
import 'package:plume_gmail/src/api/quota.dart';
import 'package:test/test.dart';

import 'support/fake_gmail.dart';
import 'support/fake_tokens.dart';
import 'support/fixtures.dart';

void main() {
  late List<Duration> sleeps;
  Future<void> fakeSleep(Duration d) async => sleeps.add(d);

  setUp(() => sleeps = []);

  GmailClient clientFor(http.Client http, FakeTokenSource tokens, {GmailQuota quota = GmailQuota.unlimited}) =>
      GmailClient(
        tokens: tokens,
        httpClient: http,
        config: GmailClientConfig(quota: quota, maxRetries: 3),
        sleep: fakeSleep,
        random: Random(1),
      );

  group('BatchCodec', () {
    test('encodes sub-requests as application/http parts', () {
      final body = BatchCodec.encode([
        GmailApi.threadGetRequest('t1'),
        const GmailRequest('POST', 'threads/t2/modify', cost: 10, body: {
          'removeLabelIds': ['INBOX'],
        }),
      ], 'BOUNDARY', ids: [7, 9]);
      expect(body, startsWith('--BOUNDARY\r\nContent-Type: application/http\r\nContent-ID: <item-7>\r\n\r\n'));
      expect(
          body,
          contains('GET /gmail/v1/users/me/threads/t1?format=metadata&metadataHeaders=From&metadataHeaders=To'
              '&metadataHeaders=Cc&metadataHeaders=Bcc&metadataHeaders=Reply-To&metadataHeaders=Subject'
              '&metadataHeaders=Date&metadataHeaders=Message-ID&metadataHeaders=In-Reply-To'
              '&metadataHeaders=References&metadataHeaders=List-Unsubscribe HTTP/1.1\r\n'));
      expect(body, contains('Content-ID: <item-9>'));
      const json = '{"removeLabelIds":["INBOX"]}';
      expect(
          body,
          contains('POST /gmail/v1/users/me/threads/t2/modify HTTP/1.1\r\n'
              'Content-Type: application/json; charset=UTF-8\r\nContent-Length: ${json.length}\r\n\r\n$json\r\n'));
      expect(body, endsWith('--BOUNDARY--\r\n'));
    });

    test('decodes responses including per-part errors, any order, LF or CRLF', () {
      const response = '''
--batch_abc
Content-Type: application/http
Content-ID: <response-item-2>

HTTP/1.1 429 Too Many Requests
Content-Type: application/json; charset=UTF-8
Retry-After: 3

{"error": {"code": 429, "message": "Too many concurrent requests for user", "errors": [{"reason": "rateLimitExceeded"}]}}
--batch_abc
Content-Type: application/http
Content-ID: <response-item-0>

HTTP/1.1 200 OK
Content-Type: application/json; charset=UTF-8
Vary: Origin

{"id": "t0", "messages": []}
--batch_abc
Content-Type: application/http
Content-ID: <response-item-1>

HTTP/1.1 404 Not Found
Content-Type: application/json; charset=UTF-8

{"error": {"code": 404, "message": "Requested entity was not found."}}
--batch_abc
Content-Type: application/http
Content-ID: <response-item-3>

HTTP/1.1 204 No Content

--batch_abc--
''';
      for (final text in [response, response.replaceAll('\n', '\r\n')]) {
        final parts = BatchCodec.decode('multipart/mixed; boundary=batch_abc', utf8.encode(text));
        expect(parts.map((p) => p.index), [2, 0, 1, 3]);
        expect(parts.map((p) => p.status), [429, 200, 404, 204]);
        expect(parts[0].headers['retry-after'], '3');
        expect(jsonDecode(parts[1].body), {'id': 't0', 'messages': <Object?>[]});
        expect(parts[3].body, isEmpty);
        expect(GoogleApiError.parse(429, parts[0].body).isRetryable, isTrue);
      }
      expect(() => BatchCodec.decode('application/json', utf8.encode('{}')), throwsFormatException);
    });
  });

  group('GmailClient.batch', () {
    test('retries only the rate-limited part, honouring Retry-After', () async {
      final gmail = FakeGmail()
        ..addMessage(gmailMessage(id: 'm1', threadId: 't1'))
        ..addMessage(gmailMessage(id: 'm2', threadId: 't2'))
        ..addMessage(gmailMessage(id: 'm3', threadId: 't3'));
      gmail.failures['GET threads/t2'] = [429];
      final api = GmailApi(clientFor(gmail.client, FakeTokenSource()));

      final results = await api.getThreads(['t1', 't2', 't3', 'missing']);

      expect(results.map((r) => r.isOk), [true, true, true, false]);
      expect(results[1].value!.messages.single.id, 'm2');
      expect(results[3].error, isA<NotFoundException>());
      expect(gmail.batchSizes, [4], reason: 'the single retried item is sent without a batch');
      expect(gmail.log.where((l) => l.contains('threads/t2')), hasLength(2));
      expect(sleeps.single, greaterThanOrEqualTo(const Duration(seconds: 1)), reason: 'Retry-After: 1');
    });

    test('retries several failed parts together in a follow-up batch', () async {
      final gmail = FakeGmail()..reverseBatchParts = true;
      for (var i = 0; i < 6; i++) {
        gmail.addMessage(gmailMessage(id: 'm$i', threadId: 't$i'));
      }
      gmail.failures['GET threads/t1'] = [429];
      gmail.failures['GET threads/t4'] = [503];
      gmail.failures['GET threads/t5'] = [403];
      final api = GmailApi(clientFor(gmail.client, FakeTokenSource()));
      final results = await api.getThreads([for (var i = 0; i < 6; i++) 't$i']);
      expect(results.every((r) => r.isOk), isTrue);
      expect([for (final r in results) r.value!.id], ['t0', 't1', 't2', 't3', 't4', 't5']);
      expect(gmail.batchSizes, [6, 3]);
    });

    test('groups by quota units and batch size', () async {
      final gmail = FakeGmail();
      for (var i = 0; i < 60; i++) {
        gmail.addMessage(gmailMessage(id: 'm$i', threadId: 't$i'));
      }
      final api = GmailApi(clientFor(gmail.client, FakeTokenSource(), quota: const GmailQuota(unitsPerSecond: 1e9, burstUnits: 1e9)));
      await api.getThreads([for (var i = 0; i < 60; i++) 't$i']);
      expect(gmail.batchSizes, [20, 20, 20], reason: 'threads.get is 40 units; 800 units per batch');
      gmail.batchSizes.clear();
      await api.getMessages([for (var i = 0; i < 60; i++) 'm$i']);
      expect(gmail.batchSizes, [40, 20], reason: 'messages.get is 20 units; 800 units per batch');
    });

    test('a 401 in parts invalidates the token once and retries', () async {
      final gmail = FakeGmail()
        ..addMessage(gmailMessage(id: 'm1', threadId: 't1'))
        ..addMessage(gmailMessage(id: 'm2', threadId: 't2'))
        ..rejectedTokens.add('token-1');
      final tokens = FakeTokenSource();
      final results = await GmailApi(clientFor(gmail.client, tokens)).getThreads(['t1', 't2']);
      expect(results.every((r) => r.isOk), isTrue);
      expect(tokens.invalidations, 1);

      gmail.rejectedTokens.addAll(['token-2', 'token-3']);
      final failed = await GmailApi(clientFor(gmail.client, tokens)).getThreads(['t1', 't2']);
      expect(failed.every((r) => r.error is AuthException), isTrue);
      expect(tokens.invalidations, 2);
    });
  });

  group('GmailClient.send', () {
    test('maps statuses onto core exceptions', () async {
      Future<MailException> failWith(int status, Map<String, Object?> body) async {
        final client = clientFor(
            MockClient((_) async => http.Response(jsonEncode(body), status)), FakeTokenSource());
        try {
          await client.send(const GmailRequest('GET', 'profile', cost: 1));
        } on MailException catch (e) {
          return e;
        }
        fail('expected an exception');
      }

      Map<String, Object?> err(String reason, [String message = 'x']) => {
            'error': {
              'code': 0,
              'message': message,
              'errors': [
                {'reason': reason},
              ],
            },
          };
      expect(await failWith(404, err('notFound')), isA<NotFoundException>());
      expect(await failWith(400, err('invalidArgument')), isA<PermanentException>());
      expect(await failWith(403, err('forbidden')), isA<PermanentException>());
      expect(await failWith(403, err('insufficientPermissions', 'Request had insufficient authentication scopes.')),
          isA<AuthException>());
      expect(await failWith(500, err('backendError')), isA<TransientException>());
      expect(await failWith(403, err('userRateLimitExceeded')), isA<TransientException>());
      expect(await failWith(403, err('dailyLimitExceeded')), isA<TransientException>());
      expect(await failWith(429, err('rateLimitExceeded')), isA<TransientException>());
      // 500/429/403-rate-limit were retried with backoff (3 retries each).
      expect(sleeps, hasLength(9));
    });

    test('401 refreshes once; a second 401 is an AuthException', () async {
      final tokens = FakeTokenSource();
      var calls = 0;
      final client = clientFor(MockClient((req) async {
        calls++;
        if (req.headers['authorization'] == 'Bearer token-1') return http.Response('{}', 401);
        return http.Response('{"emailAddress":"me@example.com","historyId":"9"}', 200);
      }), tokens);
      final profile = await GmailApi(client).getProfile();
      expect(profile.historyId, '9');
      expect(tokens.invalidations, 1);
      expect(calls, 2);

      final always401 = clientFor(MockClient((_) async => http.Response('{}', 401)), FakeTokenSource());
      await expectLater(always401.send(const GmailRequest('GET', 'profile', cost: 1)), throwsA(isA<AuthException>()));
    });

    test('network errors are retried, then become TransientException', () async {
      var calls = 0;
      final client = clientFor(MockClient((_) async {
        calls++;
        if (calls < 3) throw const SocketException('connection reset');
        return http.Response('{"historyId":"1"}', 200);
      }), FakeTokenSource());
      expect((await GmailApi(client).getProfile()).historyId, '1');
      expect(sleeps, hasLength(2));
      expect(sleeps[1], greaterThan(sleeps[0] ~/ 2), reason: 'exponential');

      final dead = clientFor(MockClient((_) async => throw http.ClientException('down')), FakeTokenSource());
      await expectLater(dead.send(const GmailRequest('GET', 'profile', cost: 1)), throwsA(isA<TransientException>()));
    });

    test('sending mail is only retried when Gmail rejected it outright', () async {
      var calls = 0;
      final failing = clientFor(MockClient((_) async {
        calls++;
        return http.Response('{"error":{"code":500,"message":"boom"}}', 500);
      }), FakeTokenSource());
      await expectLater(GmailApi(failing).sendMessage(utf8.encode('Subject: x\r\n\r\nhi')), throwsA(isA<TransientException>()));
      expect(calls, 1, reason: 'a 500 after sending is ambiguous');

      calls = 0;
      final limited = clientFor(MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('{"error":{"code":429,"message":"slow down"}}', 429);
        return http.Response('{"id":"sent1","threadId":"t"}', 200);
      }), FakeTokenSource());
      expect((await GmailApi(limited).sendMessage(utf8.encode('x'))).id, 'sent1');
      expect(calls, 2);
    });

    test('a long Retry-After is not waited out in-process', () async {
      final client = clientFor(
          MockClient((_) async => http.Response('{"error":{"code":429,"message":"x"}}', 429, headers: {'retry-after': '3600'})),
          FakeTokenSource());
      try {
        await client.send(const GmailRequest('GET', 'profile', cost: 1));
        fail('expected TransientException');
      } on TransientException catch (e) {
        expect(e.retryAfter, const Duration(hours: 1));
      }
      expect(sleeps, isEmpty);
    });

    test('decodes gzip bodies and sends gzip-friendly headers', () async {
      late http.BaseRequest seen;
      final client = clientFor(MockClient((req) async {
        seen = req;
        return http.Response.bytes(gzip.encode(utf8.encode('{"historyId":"77"}')), 200,
            headers: {'content-encoding': 'gzip'});
      }), FakeTokenSource());
      expect((await GmailApi(client).getProfile()).historyId, '77');
      expect(seen.headers['accept-encoding'], 'gzip');
      expect(seen.headers['user-agent'], contains('gzip'));
      expect(seen.headers['authorization'], 'Bearer token-1');
    });

    test('history 404 means the cursor expired', () async {
      final gmail = FakeGmail()..historyExpired = true;
      final api = GmailApi(clientFor(gmail.client, FakeTokenSource()));
      await expectLater(api.listHistory(startHistoryId: '1'), throwsA(isA<SyncCursorExpiredException>()));
    });

    test('large messages use the media upload endpoint', () async {
      final gmail = FakeGmail();
      final api = GmailApi(clientFor(gmail.client, FakeTokenSource()));
      final raw = utf8.encode('Subject: big\r\nMessage-ID: <big@x>\r\n\r\n${'A' * (GmailApi.uploadThreshold + 10)}');
      final sent = await api.sendMessage(raw, threadId: 'thread-9');
      expect(gmail.log.single, 'upload:POST messages/send?uploadType=multipart');
      expect(sent.threadId, 'thread-9');
      expect(gmail.rawMessages[sent.id], utf8.decode(raw));
    });
  });

  group('QuotaLimiter', () {
    test('lets a burst through, then paces to the sustained rate', () async {
      var now = DateTime.utc(2026);
      final waits = <Duration>[];
      final limiter = QuotaLimiter(
        const GmailQuota(unitsPerSecond: 100, burstUnits: 100),
        clock: () => now,
        sleep: (d) async {
          waits.add(d);
          now = now.add(d);
        },
      );
      await limiter.acquire(100);
      expect(waits, isEmpty);
      await limiter.acquire(100);
      expect(waits.single, const Duration(seconds: 1));
      await limiter.acquire(50);
      expect(waits.last, const Duration(milliseconds: 500));
      now = now.add(const Duration(seconds: 10));
      await limiter.acquire(100);
      expect(waits, hasLength(2), reason: 'idle time refills the budget');
    });
  });
}
