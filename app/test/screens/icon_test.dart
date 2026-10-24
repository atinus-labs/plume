// Renders Plume's app icon at every hicolor size.
//
//   PLUME_ICON=1 flutter test test/screens/icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/services/avatar_renderer.dart';
import 'package:plume_design/plume_design.dart';

void main() {
  testWidgets('app icon', skip: Platform.environment['PLUME_ICON'] != '1', (tester) async {
    final scheme = PlumeTheme.build(brightness: Brightness.light).colorScheme;
    for (final size in const [16, 22, 24, 32, 48, 64, 128, 256, 512]) {
      final png = await tester.runAsync(() async {
        final rgba = await renderTrayIconRgba(
            size: size, unread: 0, color: scheme.primary, onColor: scheme.onPrimary, badge: scheme.error);
        final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
        final descriptor = ui.ImageDescriptor.raw(buffer, width: size, height: size, pixelFormat: ui.PixelFormat.rgba8888);
        final codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final file = File('linux/data/icons/hicolor/${size}x$size/apps/org.atinus.plume.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!);
    }
  });
}
