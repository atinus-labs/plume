import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';

import '../util/gmail_data.dart';
import '../util/json.dart';
import 'gmail_client.dart';
import 'gmail_request.dart';
import 'gmail_types.dart';

/// Message/thread representations accepted by the Gmail API.
enum GmailFormat { minimal, metadata, full, raw }

/// Result of one item of a batched call.
final class BatchResult<T> {
  const BatchResult.ok(T this.value) : error = null;
  const BatchResult.failed(MailException this.error) : value = null;

  final T? value;
  final MailException? error;

  bool get isOk => error == null;
}

/// Thin typed client over `https://gmail.googleapis.com/gmail/v1/users/me`.
///
/// Every method maps onto one documented endpoint; quota costs are declared
/// per call so the [GmailClient] can pace them.
final class GmailApi {
  GmailApi(this.client);

  final GmailClient client;

  /// Headers requested with `format=metadata`.
  static const metadataHeaders = [
    'From',
    'To',
    'Cc',
    'Bcc',
    'Reply-To',
    'Subject',
    'Date',
    'Message-ID',
    'In-Reply-To',
    'References',
    'List-Unsubscribe',
  ];

  /// Raw messages above this size go through the `/upload` endpoint, whose
  /// limit is 35 MB instead of the ~5 MB request limit.
  static const uploadThreshold = 3 * 1024 * 1024;

  // Profile and labels -----------------------------------------------------

  Future<GmailProfile> getProfile() async =>
      GmailProfile.fromJson(_obj(await client.send(const GmailRequest('GET', 'profile', cost: 1))));

  Future<List<GmailLabel>> listLabels() async {
    final json = _obj(await client.send(const GmailRequest('GET', 'labels', cost: 1)));
    return [for (final l in json.objList('labels')) GmailLabel.fromJson(l)];
  }

  /// labels.get for each id (labels.list does not include counts).
  Future<List<BatchResult<GmailLabel>>> getLabels(List<String> ids) =>
      _batch([for (final id in ids) GmailRequest('GET', 'labels/${_seg(id)}', cost: 1)], GmailLabel.fromJson);

  // Threads ----------------------------------------------------------------

  Future<GmailThreadPage> listThreads({
    List<String> labelIds = const [],
    String? query,
    String? pageToken,
    int maxResults = 100,
    bool includeSpamTrash = false,
  }) async {
    final json = _obj(await client.send(GmailRequest('GET', 'threads', cost: 10, query: {
      'maxResults': '${maxResults.clamp(1, 500)}',
      if (labelIds.isNotEmpty) 'labelIds': labelIds,
      if (query != null && query.isNotEmpty) 'q': query,
      'pageToken': ?pageToken,
      if (includeSpamTrash) 'includeSpamTrash': 'true',
    })));
    return GmailThreadPage.fromJson(json);
  }

  static GmailRequest threadGetRequest(String id, {GmailFormat format = GmailFormat.metadata}) =>
      GmailRequest('GET', 'threads/${_seg(id)}', cost: 10, query: _formatQuery(format));

  Future<GmailThread> getThread(String id, {GmailFormat format = GmailFormat.metadata}) async =>
      GmailThread.fromJson(_obj(await client.send(threadGetRequest(id, format: format))));

  Future<List<BatchResult<GmailThread>>> getThreads(List<String> ids, {GmailFormat format = GmailFormat.metadata}) =>
      _batch([for (final id in ids) threadGetRequest(id, format: format)], GmailThread.fromJson);

  /// threads.modify for each thread.
  Future<void> modifyThreads(List<String> ids, {Set<String> add = const {}, Set<String> remove = const {}}) =>
      _batchVoid([
        for (final id in ids)
          GmailRequest('POST', 'threads/${_seg(id)}/modify', cost: 10, body: {
            if (add.isNotEmpty) 'addLabelIds': add.toList(),
            if (remove.isNotEmpty) 'removeLabelIds': remove.toList(),
          }),
      ]);

  Future<void> trashThreads(List<String> ids) =>
      _batchVoid([for (final id in ids) GmailRequest('POST', 'threads/${_seg(id)}/trash', cost: 10)]);

  Future<void> untrashThreads(List<String> ids) =>
      _batchVoid([for (final id in ids) GmailRequest('POST', 'threads/${_seg(id)}/untrash', cost: 10)]);

  Future<void> deleteThreads(List<String> ids) =>
      _batchVoid([for (final id in ids) GmailRequest('DELETE', 'threads/${_seg(id)}', cost: 20)]);

  // Messages ---------------------------------------------------------------

  static GmailRequest messageGetRequest(String id, {GmailFormat format = GmailFormat.metadata}) =>
      GmailRequest('GET', 'messages/${_seg(id)}', cost: 5, query: _formatQuery(format));

  Future<GmailMessage> getMessage(String id, {GmailFormat format = GmailFormat.metadata}) async =>
      GmailMessage.fromJson(_obj(await client.send(messageGetRequest(id, format: format))));

  Future<List<BatchResult<GmailMessage>>> getMessages(List<String> ids, {GmailFormat format = GmailFormat.metadata}) =>
      _batch([for (final id in ids) messageGetRequest(id, format: format)], GmailMessage.fromJson);

  /// messages.list returning ids only (used to find a sent message by its
  /// Message-ID after an ambiguous send failure).
  Future<List<String>> listMessageIds({String? query, int maxResults = 10, bool includeSpamTrash = false}) async {
    final json = _obj(await client.send(GmailRequest('GET', 'messages', cost: 5, query: {
      'maxResults': '$maxResults',
      'q': ?query,
      if (includeSpamTrash) 'includeSpamTrash': 'true',
    })));
    return [for (final m in json.objList('messages')) ?m.str('id')];
  }

  /// messages.batchModify, chunked to Gmail's 1000-id limit.
  Future<void> batchModifyMessages(List<String> ids, {Set<String> add = const {}, Set<String> remove = const {}}) async {
    if (add.isEmpty && remove.isEmpty) return;
    for (var i = 0; i < ids.length; i += 1000) {
      final chunk = ids.sublist(i, i + 1000 > ids.length ? ids.length : i + 1000);
      await client.send(GmailRequest('POST', 'messages/batchModify', cost: 50, body: {
        'ids': chunk,
        if (add.isNotEmpty) 'addLabelIds': add.toList(),
        if (remove.isNotEmpty) 'removeLabelIds': remove.toList(),
      }));
    }
  }

  /// messages.batchDelete (permanent), chunked to 1000 ids.
  Future<void> batchDeleteMessages(List<String> ids) async {
    for (var i = 0; i < ids.length; i += 1000) {
      final chunk = ids.sublist(i, i + 1000 > ids.length ? ids.length : i + 1000);
      await client.send(GmailRequest('POST', 'messages/batchDelete', cost: 50, body: {'ids': chunk}));
    }
  }

  Future<void> trashMessages(List<String> ids) =>
      _batchVoid([for (final id in ids) GmailRequest('POST', 'messages/${_seg(id)}/trash', cost: 5)]);

  Future<void> untrashMessages(List<String> ids) =>
      _batchVoid([for (final id in ids) GmailRequest('POST', 'messages/${_seg(id)}/untrash', cost: 5)]);

  /// messages.send. Returns the sent message (id, threadId, labelIds).
  Future<GmailMessage> sendMessage(List<int> raw, {String? threadId}) async {
    final GmailRequest request;
    if (raw.length > uploadThreshold) {
      request = GmailRequest('POST', 'messages/send',
          cost: 100, media: raw, idempotent: false, body: {'threadId': ?threadId});
    } else {
      request = GmailRequest('POST', 'messages/send',
          cost: 100, idempotent: false, body: {'raw': encodeGmailData(raw), 'threadId': ?threadId});
    }
    return GmailMessage.fromJson(_obj(await client.send(request)));
  }

  Future<Uint8List> getAttachment(String messageId, String attachmentId) async {
    final json = _obj(await client.send(
        GmailRequest('GET', 'messages/${_seg(messageId)}/attachments/${_seg(attachmentId)}', cost: 5)));
    return decodeGmailData(json.str('data') ?? '');
  }

  // History ----------------------------------------------------------------

  /// One page of history.list. A 404 means [startHistoryId] is too old and
  /// is reported as [SyncCursorExpiredException].
  Future<GmailHistoryPage> listHistory({required String startHistoryId, String? pageToken, int maxResults = 500}) async {
    try {
      final json = _obj(await client.send(GmailRequest('GET', 'history', cost: 2, query: {
        'startHistoryId': startHistoryId,
        'maxResults': '${maxResults.clamp(1, 500)}',
        'pageToken': ?pageToken,
      })));
      return GmailHistoryPage.fromJson(json);
    } on NotFoundException catch (e) {
      throw SyncCursorExpiredException('Gmail history $startHistoryId is no longer available', e);
    }
  }

  // Drafts -----------------------------------------------------------------

  Future<GmailDraft> createDraft(List<int> raw, {String? threadId}) async => GmailDraft.fromJson(_obj(await client.send(
      _draftRequest('POST', 'drafts', raw, threadId: threadId, cost: 10))));

  Future<GmailDraft> updateDraft(String draftId, List<int> raw, {String? threadId}) async =>
      GmailDraft.fromJson(_obj(await client.send(
          _draftRequest('PUT', 'drafts/${_seg(draftId)}', raw, draftId: draftId, threadId: threadId, cost: 15))));

  /// drafts.send with the latest content of the draft.
  Future<GmailMessage> sendDraft(String draftId, List<int> raw, {String? threadId}) async =>
      GmailMessage.fromJson(_obj(await client.send(_draftRequest('POST', 'drafts/send', raw,
          draftId: draftId, threadId: threadId, cost: 100, idempotent: false))));

  Future<void> deleteDraft(String draftId) async {
    await client.send(GmailRequest('DELETE', 'drafts/${_seg(draftId)}', cost: 10));
  }

  Future<GmailDraftPage> listDrafts({String? pageToken, int maxResults = 100}) async =>
      GmailDraftPage.fromJson(_obj(await client.send(GmailRequest('GET', 'drafts', cost: 5, query: {
        'maxResults': '$maxResults',
        'pageToken': ?pageToken,
      }))));

  GmailRequest _draftRequest(String method, String path, List<int> raw,
      {String? draftId, String? threadId, required int cost, bool idempotent = true}) {
    final message = <String, Object?>{'threadId': ?threadId};
    if (raw.length > uploadThreshold) {
      return GmailRequest(method, path,
          cost: cost, media: raw, idempotent: idempotent, body: {'id': ?draftId, 'message': message});
    }
    message['raw'] = encodeGmailData(raw);
    return GmailRequest(method, path,
        cost: cost, idempotent: idempotent, body: {'id': ?draftId, 'message': message});
  }

  // Helpers ----------------------------------------------------------------

  Future<List<BatchResult<T>>> _batch<T>(List<GmailRequest> requests, T Function(JsonMap) parse) async {
    final outcomes = await client.batch(requests);
    return [
      for (final o in outcomes)
        switch (o) {
          BatchSuccess(:final json) => asJsonMap(json) == null
              ? const BatchResult.failed(TransientException('Unexpected empty response'))
              : BatchResult<T>.ok(parse(asJsonMap(json)!)),
          BatchFailure(:final error) => BatchResult<T>.failed(error),
        },
    ];
  }

  /// Runs mutation requests; objects that no longer exist are ignored
  /// (the mutation is moot), other failures are rethrown.
  Future<void> _batchVoid(List<GmailRequest> requests) async {
    final outcomes = await client.batch(requests);
    MailException? first;
    for (final o in outcomes) {
      if (o is BatchFailure && o.error is! NotFoundException) {
        // Prefer surfacing auth problems, then transient ones (retryable).
        if (first == null || o.error is AuthException) first = o.error;
      }
    }
    if (first != null) throw first;
  }

  static Map<String, Object> _formatQuery(GmailFormat format) => {
        'format': format.name,
        if (format == GmailFormat.metadata) 'metadataHeaders': metadataHeaders,
      };

  static String _seg(String id) => Uri.encodeComponent(id);

  static JsonMap _obj(Object? json) =>
      asJsonMap(json) ?? (throw const TransientException('Gmail returned an unexpected response'));
}
