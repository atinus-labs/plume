import 'dart:convert';
import 'dart:typed_data';

/// Decodes standard or URL-safe base64, tolerating missing padding,
/// whitespace, stray characters and non-zero padding bits. Input cut off in
/// the middle of a 4-character group (a partial IMAP fetch) decodes every
/// complete byte. Returns null only if the platform decoder still rejects
/// the cleaned input.
Uint8List? decodeBase64Lenient(String input) {
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2F) {
      buf.writeCharCode(c);
    } else if (c == 0x2D) {
      buf.write('+');
    } else if (c == 0x5F) {
      buf.write('/');
    }
    // '=' padding, whitespace and junk are dropped; padding is re-added.
  }
  final s = buf.toString();
  final rem = s.length % 4;
  final whole = s.length - rem;
  final Uint8List head;
  try {
    head = whole == 0 ? Uint8List(0) : base64.decode(s.substring(0, whole));
  } on FormatException {
    return null;
  }
  if (rem < 2) return head; // A single dangling character carries no byte.
  // A final partial group: 2 characters hold one byte, 3 hold two. Decoded
  // by hand so that non-zero padding bits (sloppy encoders, or input cut
  // off by a partial fetch) do not make the whole input fail.
  var bits = 0;
  for (var i = whole; i < s.length; i++) {
    bits = (bits << 6) | _base64Value(s.codeUnitAt(i));
  }
  final tail = rem == 2 ? [(bits >> 4) & 0xFF] : [(bits >> 10) & 0xFF, (bits >> 2) & 0xFF];
  return Uint8List(head.length + tail.length)
    ..setAll(0, head)
    ..setAll(head.length, tail);
}

int _base64Value(int c) {
  if (c >= 0x41 && c <= 0x5A) return c - 0x41;
  if (c >= 0x61 && c <= 0x7A) return c - 0x61 + 26;
  if (c >= 0x30 && c <= 0x39) return c - 0x30 + 52;
  return c == 0x2B ? 62 : 63;
}

/// Decodes a quoted-printable body (RFC 2045 section 6.7), including soft
/// line breaks. Malformed escapes are kept literally.
Uint8List decodeQuotedPrintable(String input) {
  final out = BytesBuilder(copy: false);
  final n = input.length;
  var i = 0;
  while (i < n) {
    final c = input.codeUnitAt(i);
    if (c == 0x3D /* = */) {
      // Soft line break: "=" followed by optional whitespace and a newline.
      var j = i + 1;
      while (j < n && (input.codeUnitAt(j) == 0x20 || input.codeUnitAt(j) == 0x09)) {
        j++;
      }
      if (j < n && (input.codeUnitAt(j) == 0x0D || input.codeUnitAt(j) == 0x0A)) {
        if (input.codeUnitAt(j) == 0x0D && j + 1 < n && input.codeUnitAt(j + 1) == 0x0A) j++;
        i = j + 1;
        continue;
      }
      if (j >= n) {
        i = n;
        continue;
      }
      if (i + 2 < n) {
        final hi = _hex(input.codeUnitAt(i + 1));
        final lo = _hex(input.codeUnitAt(i + 2));
        if (hi >= 0 && lo >= 0) {
          out.addByte(hi * 16 + lo);
          i += 3;
          continue;
        }
      }
      out.addByte(c);
      i++;
    } else if (c < 0x100) {
      out.addByte(c);
      i++;
    } else {
      out.add(utf8.encode(String.fromCharCode(c)));
      i++;
    }
  }
  return out.takeBytes();
}

/// Q-encoding from RFC 2047: like quoted-printable, but "_" means space.
Uint8List decodeQEncoding(String input) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x5F) {
      out.addByte(0x20);
    } else if (c == 0x3D && i + 2 < input.length) {
      final hi = _hex(input.codeUnitAt(i + 1));
      final lo = _hex(input.codeUnitAt(i + 2));
      if (hi >= 0 && lo >= 0) {
        out.addByte(hi * 16 + lo);
        i += 2;
      } else {
        out.addByte(c);
      }
    } else if (c < 0x100) {
      out.addByte(c);
    } else {
      out.add(utf8.encode(String.fromCharCode(c)));
    }
  }
  return out.takeBytes();
}

/// Undoes a `Content-Transfer-Encoding` ([encoding] is the header value,
/// any case). 7bit, 8bit, binary and unknown encodings return the bytes
/// unchanged. Never throws.
Uint8List decodeTransferEncoding(List<int> bytes, String? encoding) {
  switch ((encoding ?? '').trim().toLowerCase()) {
    case 'base64':
      return decodeBase64Lenient(latin1.decode(bytes, allowInvalid: true)) ?? Uint8List(0);
    case 'quoted-printable':
      return decodeQuotedPrintable(latin1.decode(bytes, allowInvalid: true));
    default:
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
}

/// Base64 with CRLF line breaks every [lineLength] characters (RFC 2045).
String encodeBase64Wrapped(List<int> bytes, {int lineLength = 76}) {
  final encoded = base64.encode(bytes);
  if (encoded.length <= lineLength) return encoded;
  final sb = StringBuffer();
  for (var i = 0; i < encoded.length; i += lineLength) {
    if (i > 0) sb.write('\r\n');
    sb.write(encoded.substring(i, i + lineLength > encoded.length ? encoded.length : i + lineLength));
  }
  return sb.toString();
}

int _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}
