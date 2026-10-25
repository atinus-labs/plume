import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/platform/linux/linux_desktop.dart';

void main() {
  group('LinuxDesktop shell accent resolution', () {
    test('parseColor handles standard hex and bare hex', () {
      expect(LinuxDesktop.parseColor('#818994'), const Color(0xFF818994));
      expect(LinuxDesktop.parseColor('818994'), const Color(0xFF818994));
      expect(LinuxDesktop.parseColor('#FF5500'), const Color(0xFFFF5500));
      expect(LinuxDesktop.parseColor('00ff00'), const Color(0xFF00FF00));
    });

    test('parseColor rejects invalid values', () {
      expect(LinuxDesktop.parseColor(''), isNull);
      expect(LinuxDesktop.parseColor('#12'), isNull);
      expect(LinuxDesktop.parseColor('not-hex'), isNull);
      expect(LinuxDesktop.parseColor('#12345678'), isNull);
    });

    test('resolveShellAccentFromDir reads color.txt', () async {
      final tempDir = await Directory.systemTemp.createTemp('plume_accent_test_');
      try {
        final colorTxt = File('${tempDir.path}/color.txt');
        await colorTxt.writeAsString('#4C5BD4\n');

        final color = LinuxDesktop.resolveShellAccentFromDir(tempDir);
        expect(color, const Color(0xFF4C5BD4));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveShellAccentFromDir falls back to colors.json primary', () async {
      final tempDir = await Directory.systemTemp.createTemp('plume_accent_test_');
      try {
        final colorsJson = File('${tempDir.path}/colors.json');
        await colorsJson.writeAsString(jsonEncode({'primary': '#BEC7D4', 'surface': '#131314'}));

        final color = LinuxDesktop.resolveShellAccentFromDir(tempDir);
        expect(color, const Color(0xFFBEC7D4));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveShellAccentFromDir prefers color.txt over colors.json', () async {
      final tempDir = await Directory.systemTemp.createTemp('plume_accent_test_');
      try {
        final colorTxt = File('${tempDir.path}/color.txt');
        await colorTxt.writeAsString('#818994');

        final colorsJson = File('${tempDir.path}/colors.json');
        await colorsJson.writeAsString(jsonEncode({'primary': '#BEC7D4'}));

        final color = LinuxDesktop.resolveShellAccentFromDir(tempDir);
        expect(color, const Color(0xFF818994));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveShellAccentFromDir returns null for empty directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('plume_accent_test_');
      try {
        final color = LinuxDesktop.resolveShellAccentFromDir(tempDir);
        expect(color, isNull);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
