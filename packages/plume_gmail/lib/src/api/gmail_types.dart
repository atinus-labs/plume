/// Typed views over the Gmail REST API JSON resources Plume uses.
///
/// Only the fields Plume needs are modelled. Parsing is lenient: missing
/// optional fields become defaults rather than errors, because the API omits
/// empty fields.
library;

import '../util/json.dart';

final class GmailHeader {
  const GmailHeader(this.name, this.value);

  final String name;
  final String value;

  Map<String, Object?> toJson() => {'name': name, 'value': value};
}

final class GmailPartBody {
  const GmailPartBody({this.attachmentId, this.size = 0, this.data});

  /// Set when the part's content must be fetched with attachments.get.
  final String? attachmentId;

  /// Decoded size in bytes.
  final int size;

  /// base64url content, present for small parts in `format=full`.
  final String? data;

  static GmailPartBody fromJson(JsonMap? j) => j == null
      ? const GmailPartBody()
      : GmailPartBody(attachmentId: j.str('attachmentId'), size: j.integer('size') ?? 0, data: j.str('data'));

  Map<String, Object?> toJson() => {
        if (attachmentId != null) 'attachmentId': attachmentId,
        'size': size,
        if (data != null) 'data': data,
      };
}

/// A MIME part as returned by Gmail. Gmail has already undone the
/// Content-Transfer-Encoding; [body] data is in the part's original charset.
final class GmailMessagePart {
  const GmailMessagePart({
    this.partId = '',
    required this.mimeType,
    this.filename = '',
    this.headers = const [],
    this.body = const GmailPartBody(),
    this.parts = const [],
  });

  final String partId;
  final String mimeType;
  final String filename;
  final List<GmailHeader> headers;
  final GmailPartBody body;
  final List<GmailMessagePart> parts;

  /// The first header named [name], case-insensitively.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final h in headers) {
      if (h.name.toLowerCase() == lower) return h.value;
    }
    return null;
  }

  bool get isMultipart => mimeType.toLowerCase().startsWith('multipart/');

  static GmailMessagePart fromJson(JsonMap j) => GmailMessagePart(
        partId: j.str('partId') ?? '',
        mimeType: j.str('mimeType') ?? 'application/octet-stream',
        filename: j.str('filename') ?? '',
        headers: [
          for (final h in j.objList('headers')) GmailHeader(h.str('name') ?? '', h.str('value') ?? ''),
        ],
        body: GmailPartBody.fromJson(j.obj('body')),
        parts: [for (final p in j.objList('parts')) GmailMessagePart.fromJson(p)],
      );

  Map<String, Object?> toJson() => {
        'partId': partId,
        'mimeType': mimeType,
        'filename': filename,
        'headers': [for (final h in headers) h.toJson()],
        'body': body.toJson(),
        if (parts.isNotEmpty) 'parts': [for (final p in parts) p.toJson()],
      };
}

final class GmailMessage {
  const GmailMessage({
    required this.id,
    this.threadId = '',
    this.labelIds = const [],
    this.snippet = '',
    this.historyId,
    this.internalDate,
    this.sizeEstimate = 0,
    this.payload,
    this.raw,
  });

  final String id;
  final String threadId;
  final List<String> labelIds;
  final String snippet;
  final String? historyId;

  /// Milliseconds since the epoch at which Gmail received the message.
  final int? internalDate;
  final int sizeEstimate;
  final GmailMessagePart? payload;
  final String? raw;

  static GmailMessage fromJson(JsonMap j) => GmailMessage(
        id: j.str('id') ?? '',
        threadId: j.str('threadId') ?? '',
        labelIds: j.strList('labelIds'),
        snippet: j.str('snippet') ?? '',
        historyId: j.str('historyId'),
        internalDate: j.integer('internalDate'),
        sizeEstimate: j.integer('sizeEstimate') ?? 0,
        payload: j.obj('payload') == null ? null : GmailMessagePart.fromJson(j.obj('payload')!),
        raw: j.str('raw'),
      );
}

final class GmailThread {
  const GmailThread({required this.id, this.historyId, this.snippet = '', this.messages = const []});

  final String id;
  final String? historyId;
  final String snippet;
  final List<GmailMessage> messages;

  static GmailThread fromJson(JsonMap j) => GmailThread(
        id: j.str('id') ?? '',
        historyId: j.str('historyId'),
        snippet: j.str('snippet') ?? '',
        messages: [for (final m in j.objList('messages')) GmailMessage.fromJson(m)],
      );
}

/// An entry of threads.list.
final class GmailThreadRef {
  const GmailThreadRef(this.id, {this.historyId});

  final String id;
  final String? historyId;
}

final class GmailThreadPage {
  const GmailThreadPage({required this.threads, this.nextPageToken, this.resultSizeEstimate});

  final List<GmailThreadRef> threads;
  final String? nextPageToken;
  final int? resultSizeEstimate;

  static GmailThreadPage fromJson(JsonMap j) => GmailThreadPage(
        threads: [
          for (final t in j.objList('threads'))
            if (t.str('id') != null) GmailThreadRef(t.str('id')!, historyId: t.str('historyId')),
        ],
        nextPageToken: _nonEmpty(j.str('nextPageToken')),
        resultSizeEstimate: j.integer('resultSizeEstimate'),
      );
}

final class GmailLabel {
  const GmailLabel({
    required this.id,
    required this.name,
    this.type = 'user',
    this.threadsTotal,
    this.threadsUnread,
    this.messagesTotal,
    this.messagesUnread,
    this.backgroundColor,
    this.textColor,
    this.labelListVisibility,
    this.messageListVisibility,
  });

  final String id;
  final String name;

  /// `system` or `user`.
  final String type;
  final int? threadsTotal;
  final int? threadsUnread;
  final int? messagesTotal;
  final int? messagesUnread;

  /// `#rrggbb`.
  final String? backgroundColor;
  final String? textColor;

  /// `labelShow`, `labelShowIfUnread` or `labelHide`.
  final String? labelListVisibility;
  final String? messageListVisibility;

  bool get isSystem => type == 'system';

  static GmailLabel fromJson(JsonMap j) => GmailLabel(
        id: j.str('id') ?? '',
        name: j.str('name') ?? '',
        type: j.str('type') ?? 'user',
        threadsTotal: j.integer('threadsTotal'),
        threadsUnread: j.integer('threadsUnread'),
        messagesTotal: j.integer('messagesTotal'),
        messagesUnread: j.integer('messagesUnread'),
        backgroundColor: j.obj('color')?.str('backgroundColor'),
        textColor: j.obj('color')?.str('textColor'),
        labelListVisibility: j.str('labelListVisibility'),
        messageListVisibility: j.str('messageListVisibility'),
      );
}

final class GmailProfile {
  const GmailProfile({required this.emailAddress, required this.historyId, this.messagesTotal, this.threadsTotal});

  final String emailAddress;
  final String historyId;
  final int? messagesTotal;
  final int? threadsTotal;

  static GmailProfile fromJson(JsonMap j) => GmailProfile(
        emailAddress: j.str('emailAddress') ?? '',
        historyId: j.str('historyId') ?? '',
        messagesTotal: j.integer('messagesTotal'),
        threadsTotal: j.integer('threadsTotal'),
      );
}

/// A labelsAdded / labelsRemoved history entry.
final class GmailLabelChange {
  const GmailLabelChange(this.message, this.labelIds);

  /// Minimal message (id, threadId, current labelIds).
  final GmailMessage message;
  final List<String> labelIds;
}

final class GmailHistoryRecord {
  const GmailHistoryRecord({
    required this.id,
    this.messagesAdded = const [],
    this.messagesDeleted = const [],
    this.labelsAdded = const [],
    this.labelsRemoved = const [],
  });

  final String id;
  final List<GmailMessage> messagesAdded;
  final List<GmailMessage> messagesDeleted;
  final List<GmailLabelChange> labelsAdded;
  final List<GmailLabelChange> labelsRemoved;

  static GmailHistoryRecord fromJson(JsonMap j) {
    List<GmailMessage> msgs(String key) => [
          for (final e in j.objList(key))
            if (e.obj('message') != null) GmailMessage.fromJson(e.obj('message')!),
        ];
    List<GmailLabelChange> changes(String key) => [
          for (final e in j.objList(key))
            if (e.obj('message') != null) GmailLabelChange(GmailMessage.fromJson(e.obj('message')!), e.strList('labelIds')),
        ];
    return GmailHistoryRecord(
      id: j.str('id') ?? '',
      messagesAdded: msgs('messagesAdded'),
      messagesDeleted: msgs('messagesDeleted'),
      labelsAdded: changes('labelsAdded'),
      labelsRemoved: changes('labelsRemoved'),
    );
  }
}

final class GmailHistoryPage {
  const GmailHistoryPage({required this.history, this.nextPageToken, this.historyId});

  final List<GmailHistoryRecord> history;
  final String? nextPageToken;

  /// The mailbox's current history id.
  final String? historyId;

  static GmailHistoryPage fromJson(JsonMap j) => GmailHistoryPage(
        history: [for (final h in j.objList('history')) GmailHistoryRecord.fromJson(h)],
        nextPageToken: _nonEmpty(j.str('nextPageToken')),
        historyId: j.str('historyId'),
      );
}

final class GmailDraft {
  const GmailDraft({required this.id, this.message});

  final String id;
  final GmailMessage? message;

  static GmailDraft fromJson(JsonMap j) => GmailDraft(
        id: j.str('id') ?? '',
        message: j.obj('message') == null ? null : GmailMessage.fromJson(j.obj('message')!),
      );
}

final class GmailDraftPage {
  const GmailDraftPage({required this.drafts, this.nextPageToken});

  final List<GmailDraft> drafts;
  final String? nextPageToken;

  static GmailDraftPage fromJson(JsonMap j) => GmailDraftPage(
        drafts: [for (final d in j.objList('drafts')) GmailDraft.fromJson(d)],
        nextPageToken: _nonEmpty(j.str('nextPageToken')),
      );
}

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
