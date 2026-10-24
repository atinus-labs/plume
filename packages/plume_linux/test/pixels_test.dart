import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:plume_linux/src/pixels.dart';
import 'package:test/test.dart';

void main() {
  group('TrayPixmap.fromRgba', () {
    test('reorders RGBA to big-endian ARGB', () {
      final rgba = Uint8List.fromList([
        0x11, 0x22, 0x33, 0xFF, // opaque
        0xAA, 0xBB, 0xCC, 0xFF,
      ]);
      final p = TrayPixmap.fromRgba(rgba, 2, 1);
      expect(p.argb32, [0xFF, 0x11, 0x22, 0x33, 0xFF, 0xAA, 0xBB, 0xCC]);
      expect(p.width, 2);
      expect(p.height, 1);
    });

    test('un-premultiplies translucent pixels by default', () {
      // 50% red, premultiplied: (128, 0, 0, 128) -> straight (255, 0, 0, 128).
      final rgba = Uint8List.fromList([128, 0, 0, 128, 10, 20, 30, 0]);
      expect(TrayPixmap.fromRgba(rgba, 2, 1).argb32, [
        128, 255, 0, 0, // ARGB
        0, 0, 0, 0, // fully transparent -> transparent black
      ]);
    });

    test('keeps straight alpha when premultiplied is false', () {
      final rgba = Uint8List.fromList([128, 0, 0, 128]);
      expect(TrayPixmap.fromRgba(rgba, 1, 1, premultiplied: false).argb32, [
        128,
        128,
        0,
        0,
      ]);
    });

    test('rejects mismatched sizes', () {
      expect(
        () => TrayPixmap.fromRgba(Uint8List(12), 2, 2),
        throwsArgumentError,
      );
      expect(
        () => TrayPixmap(width: 1, height: 1, argb32: Uint8List(3)),
        throwsArgumentError,
      );
    });

    test('serialises to a(iiay)', () {
      final p = TrayPixmap.fromRgba(Uint8List(16), 2, 2);
      final list = TrayPixmap.listToDBus([p, p]);
      expect(list.signature, DBusSignature('a(iiay)'));
      final first = list.children.first.asStruct();
      expect(first[0], const DBusInt32(2));
      expect(first[1], const DBusInt32(2));
      expect(first[2].asByteArray().length, 16);
    });
  });

  group('unpremultiplyRgba', () {
    test('handles alpha extremes and rounding', () {
      final out = unpremultiplyRgba(
        Uint8List.fromList([
          255, 255, 255, 255, //
          1, 1, 1, 1, // tiny alpha -> full channel
          64, 32, 0, 128,
        ]),
      );
      expect(out.sublist(0, 4), [255, 255, 255, 255]);
      expect(out.sublist(4, 8), [255, 255, 255, 1]);
      expect(out.sublist(8, 12), [128, 64, 0, 128]);
    });

    test('rejects lengths that are not a multiple of 4', () {
      expect(() => unpremultiplyRgba(Uint8List(5)), throwsArgumentError);
    });
  });

  group('NotificationImageData', () {
    test('encodes (iiibiiay) with rowstride and straight alpha', () {
      final img = NotificationImageData(
        Uint8List.fromList([128, 0, 0, 128, 1, 2, 3, 255]),
        width: 2,
        height: 1,
      );
      final v = img.toDBus();
      expect(v.signature, DBusSignature('(iiibiiay)'));
      final c = v.children;
      expect(c[0], const DBusInt32(2)); // width
      expect(c[1], const DBusInt32(1)); // height
      expect(c[2], const DBusInt32(8)); // rowstride
      expect(c[3], const DBusBoolean(true)); // has alpha
      expect(c[4], const DBusInt32(8)); // bits per sample
      expect(c[5], const DBusInt32(4)); // channels
      expect(c[6].asByteArray().toList(), [255, 0, 0, 128, 1, 2, 3, 255]);
    });

    test('validates dimensions', () {
      expect(
        () => NotificationImageData(Uint8List(4), width: 2, height: 2),
        throwsArgumentError,
      );
    });
  });
}
