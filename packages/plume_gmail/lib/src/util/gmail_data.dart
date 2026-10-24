import 'dart:convert';
import 'dart:typed_data';

import 'package:plume_mime/plume_mime.dart';

/// Decodes a Gmail `body.data` / attachment `data` field (base64url).
Uint8List decodeGmailData(String data) => decodeBase64Lenient(data) ?? Uint8List(0);

/// Encodes bytes as base64url, as the Gmail API expects for `raw`.
String encodeGmailData(List<int> bytes) => base64Url.encode(bytes);
