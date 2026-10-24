import 'dart:typed_data';

/// Converts premultiplied RGBA (Flutter's `ImageByteFormat.rawRgba`) to
/// straight (non-premultiplied) RGBA, which is what both the notification
/// `image-data` hint and StatusNotifierItem pixmaps expect.
///
/// Returns a new buffer; [rgba] is not modified.
Uint8List unpremultiplyRgba(Uint8List rgba) {
  _checkRgbaLength(rgba.length);
  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    out[i + 3] = a;
    if (a == 255) {
      out[i] = rgba[i];
      out[i + 1] = rgba[i + 1];
      out[i + 2] = rgba[i + 2];
    } else if (a != 0) {
      out[i] = _unpremultiply(rgba[i], a);
      out[i + 1] = _unpremultiply(rgba[i + 1], a);
      out[i + 2] = _unpremultiply(rgba[i + 2], a);
    }
    // a == 0: colour is undefined; leave as transparent black.
  }
  return out;
}

int _unpremultiply(int c, int a) {
  final v = (c * 255 + (a >> 1)) ~/ a;
  return v > 255 ? 255 : v;
}

void _checkRgbaLength(int length) {
  if (length % 4 != 0) {
    throw ArgumentError.value(length, 'rgba.length', 'must be a multiple of 4');
  }
}

/// Converts RGBA pixels to ARGB32 in network (big-endian) byte order, i.e.
/// bytes `A R G B` per pixel, as required by StatusNotifierItem `a(iiay)`.
///
/// When [premultiplied] is true (the default, matching Flutter's
/// `ImageByteFormat.rawRgba`), colour channels are un-premultiplied first.
Uint8List rgbaToArgb32BigEndian(Uint8List rgba, {bool premultiplied = true}) {
  final src = premultiplied ? unpremultiplyRgba(rgba) : rgba;
  _checkRgbaLength(src.length);
  final out = Uint8List(src.length);
  for (var i = 0; i < src.length; i += 4) {
    out[i] = src[i + 3];
    out[i + 1] = src[i];
    out[i + 2] = src[i + 1];
    out[i + 3] = src[i + 2];
  }
  return out;
}
