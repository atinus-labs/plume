// Generates platform icons from assets/branding/plume.png and previews the tray.
//
//   PLUME_ICON=1 flutter test test/screens/icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/config.dart';
import 'package:plume/src/services/avatar_renderer.dart';

void main() {
  testWidgets('app icon', skip: Platform.environment['PLUME_ICON'] != '1', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('packages/plume_design/Google Sans Flex')
        ..addFont(rootBundle.load('packages/plume_design/fonts/GoogleSansFlex.ttf'));
      await font.load();
    });

    Future<void> writeIcon(String path, int size, {int unread = 0}) async {
      final png = await tester.runAsync(() async {
        final rgba = await renderTrayIconRgba(size: size, unread: unread, badge: const Color(0xFFE5484D));
        final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
        final descriptor = ui.ImageDescriptor.raw(buffer, width: size, height: size, pixelFormat: ui.PixelFormat.rgba8888);
        final codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        } finally {
          frame.image.dispose();
          codec.dispose();
          descriptor.dispose();
          buffer.dispose();
        }
      });
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!);
    }

    for (final size in const [16, 22, 24, 32, 48, 64, 128, 256, 512]) {
      await writeIcon('linux/data/icons/hicolor/${size}x$size/apps/${AppConfig.appId}.png', size);
    }
    for (final entry in const {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.entries) {
      await writeIcon('android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png', entry.value);
    }
    for (final size in const [22, 32, 48, 64]) {
      for (final unread in const [0, 1, 42, 100]) {
        await writeIcon('build/screens/tray_${size}_$unread.png', size, unread: unread);
      }
    }
  });
}
