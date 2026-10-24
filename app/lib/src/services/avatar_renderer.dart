import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:plume_design/plume_design.dart';

/// Renders an initials avatar (as in the message list) to raw RGBA bytes,
/// for desktop notifications.
Future<Uint8List> renderAvatarRgba({
  required String name,
  required String key,
  required ColorScheme scheme,
  int size = 96,
}) async {
  final tones = tonalPair(harmonize(colorForKey(key), scheme), Brightness.light);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  canvas.drawPath(Shapes.circle.toPath(rect), Paint()..color = tones.container);
  final painter = TextPainter(
    text: TextSpan(
      text: initialsFor(name),
      style: flexStyle(size: size * 0.4, height: size * 0.4, weight: 600).copyWith(color: tones.onContainer),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, Offset((size - painter.width) / 2, (size - painter.height) / 2));
  return _toRgba(recorder, size, size);
}

/// Renders Plume's tray icon at [size] pixels, with an unread badge.
Future<Uint8List> renderTrayIconRgba({required int size, required int unread, required Color color, required Color onColor, required Color badge}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  final rect = Rect.fromLTWH(s * 0.04, s * 0.04, s * 0.92, s * 0.92);
  canvas.drawPath(Shapes.cookie12.toPath(rect, rotation: math.pi / 12), Paint()..color = color..isAntiAlias = true);

  // Envelope glyph, drawn with paths so it stays crisp at 16–24 px.
  final env = Rect.fromCenter(center: rect.center, width: s * 0.5, height: s * 0.36);
  final stroke = Paint()
    ..color = onColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.4, s * 0.075)
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  canvas.drawRRect(RRect.fromRectAndRadius(env, Radius.circular(s * 0.06)), stroke);
  canvas.drawPath(
    Path()
      ..moveTo(env.left + s * 0.03, env.top + s * 0.04)
      ..lineTo(env.center.dx, env.center.dy + s * 0.02)
      ..lineTo(env.right - s * 0.03, env.top + s * 0.04),
    stroke,
  );

  if (unread > 0) {
    final r = s * 0.2;
    final center = Offset(s - r - s * 0.01, r + s * 0.01);
    canvas.drawCircle(center, r + s * 0.04, Paint()..color = const Color(0x00000000)..blendMode = BlendMode.clear);
    canvas.drawCircle(center, r, Paint()..color = badge..isAntiAlias = true);
    if (size >= 32) {
      final label = unread > 99 ? '99' : '$unread';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: flexStyle(size: r * (label.length > 1 ? 1.05 : 1.3), height: r * 1.3, weight: 700).copyWith(color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }
  return _toRgba(recorder, size, size);
}

Future<Uint8List> _toRgba(ui.PictureRecorder recorder, int w, int h) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
