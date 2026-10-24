import 'dart:convert';

import 'package:plume_core/plume_core.dart';

/// base64url of UTF-8 text, as Gmail encodes `body.data`.
String b64(String text) => base64Url.encode(utf8.encode(text));

/// base64url of raw bytes.
String b64Bytes(List<int> bytes) => base64Url.encode(bytes);

Map<String, Object?> header(String name, String value) => {'name': name, 'value': value};

/// A Gmail MIME part JSON.
Map<String, Object?> part(
  String mimeType, {
  String partId = '',
  String filename = '',
  List<Map<String, Object?>> headers = const [],
  String? data,
  String? attachmentId,
  int? size,
  List<Map<String, Object?>> parts = const [],
}) =>
    {
      'partId': partId,
      'mimeType': mimeType,
      'filename': filename,
      'headers': headers,
      'body': {
        'size': size ?? (data == null ? 0 : base64Url.decode(base64Url.normalize(data)).length),
        'data': ?data,
        'attachmentId': ?attachmentId,
      },
      if (parts.isNotEmpty) 'parts': parts,
    };

/// A text part with Content-Type including charset.
Map<String, Object?> textPart(String mime, String text, {String partId = '', String charset = 'UTF-8'}) => part(
      mime,
      partId: partId,
      headers: [header('Content-Type', '$mime; charset="$charset"')],
      data: b64(text),
    );

/// A full Gmail message resource.
Map<String, Object?> gmailMessage({
  required String id,
  required String threadId,
  List<String> labels = const ['INBOX', 'UNREAD'],
  String subject = 'Hello',
  String from = 'Ana Lima <ana@example.com>',
  String to = 'Me <me@example.com>',
  int internalDate = 1700000000000,
  String snippet = 'Hi there',
  List<Map<String, Object?>> extraHeaders = const [],
  Map<String, Object?>? payload,
}) {
  final headers = [
    header('From', from),
    header('To', to),
    header('Subject', subject),
    header('Date', 'Tue, 14 Nov 2023 22:13:20 +0000'),
    header('Message-ID', '<$id@mail.example.com>'),
    ...extraHeaders,
  ];
  final p = Map<String, Object?>.of(payload ?? textPart('text/plain', 'Body of $id'));
  p['headers'] = [...headers, ...((p['headers'] as List?) ?? const []).cast<Map<String, Object?>>()];
  return {
    'id': id,
    'threadId': threadId,
    'labelIds': labels,
    'snippet': snippet,
    'historyId': '1',
    'internalDate': '$internalDate',
    'sizeEstimate': 1234,
    'payload': p,
  };
}

/// A Gmail label resource.
Map<String, Object?> gmailLabel(String id, String name, {String type = 'user', String? color, String? visibility}) => {
      'id': id,
      'name': name,
      'type': type,
      if (color != null) 'color': {'backgroundColor': color, 'textColor': '#ffffff'},
      'labelListVisibility': ?visibility,
    };

const testAccount = Account(
  id: 'acc1',
  provider: 'gmail',
  email: 'me@example.com',
  displayName: 'Me',
  color: 0xFF6750A4,
);
