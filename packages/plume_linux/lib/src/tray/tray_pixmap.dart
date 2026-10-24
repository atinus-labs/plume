import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../pixels.dart';

/// One StatusNotifierItem icon size: ARGB32 pixels in network byte order
/// (`A R G B` per pixel), as carried by `IconPixmap a(iiay)`.
///
/// Provide several sizes (e.g. 16, 22, 24, 32, 48, 64) so hosts can pick a
/// crisp one; build them with [TrayPixmap.fromRgba] from
/// `Image.toByteData(format: ImageByteFormat.rawRgba)`.
class TrayPixmap {
  TrayPixmap({
    required this.width,
    required this.height,
    required this.argb32,
  }) {
    if (width <= 0 || height <= 0 || argb32.length != width * height * 4) {
      throw ArgumentError(
        'Expected ${width}x$height ARGB32 (${width * height * 4} bytes), '
        'got ${argb32.length} bytes',
      );
    }
  }

  /// Converts RGBA bytes to ARGB32 big-endian. Flutter's `rawRgba` output is
  /// premultiplied; pass `premultiplied: false` for straight-alpha input.
  factory TrayPixmap.fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    bool premultiplied = true,
  }) {
    if (rgba.length != width * height * 4) {
      throw ArgumentError(
        'Expected ${width}x$height RGBA (${width * height * 4} bytes), '
        'got ${rgba.length} bytes',
      );
    }
    return TrayPixmap(
      width: width,
      height: height,
      argb32: rgbaToArgb32BigEndian(rgba, premultiplied: premultiplied),
    );
  }

  final int width;
  final int height;

  /// `A R G B` bytes per pixel, row-major, no padding.
  final Uint8List argb32;

  static final signature = DBusSignature('(iiay)');

  /// The `(iiay)` struct.
  DBusStruct toDBus() =>
      DBusStruct([DBusInt32(width), DBusInt32(height), DBusArray.byte(argb32)]);

  /// The `a(iiay)` array for a list of sizes.
  static DBusArray listToDBus(Iterable<TrayPixmap> pixmaps) =>
      DBusArray(signature, pixmaps.map((p) => p.toDBus()));
}
