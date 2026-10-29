import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/reader/mail_renderer.dart';
import 'package:plume/src/ui/reader/rendered_mail.dart';

void main() {
  late MailRendering rendering;
  String? copied;

  setUp(() => copied = null);

  Future<void> pump(WidgetTester tester, {ValueChanged<Uri>? onOpenLink}) async {
    final tile = await tester.runAsync(() => createTestImage(width: 400, height: 120));
    rendering = MailRendering(
      tiles: [tile!],
      pixelWidth: 400,
      pixelHeight: 120,
      viewportWidth: 400,
      designed: false,
      background: const ui.Color(0xFFFFFFFF),
      runs: const [
        MailTextRun(text: 'Hello ', rect: Rect.fromLTWH(0, 0, 50, 20), separator: '', fontSize: 16, fontWeight: 400, italic: false, families: []),
        MailTextRun(text: 'world', rect: Rect.fromLTWH(50, 0, 45, 20), separator: '', fontSize: 16, fontWeight: 700, italic: false, families: []),
        MailTextRun(text: 'Second', rect: Rect.fromLTWH(0, 40, 60, 20), separator: '\n\n', fontSize: 16, fontWeight: 400, italic: false, families: []),
        MailTextRun(text: 'cell', rect: Rect.fromLTWH(100, 40, 40, 20), separator: '\t', fontSize: 16, fontWeight: 400, italic: false, families: []),
      ],
      links: [
        MailLink(uri: Uri.parse('https://example.com/a'), title: '', rects: const [Rect.fromLTWH(0, 80, 120, 20)]),
      ],
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RenderedMail(rendering: rendering, width: 400, onOpenLink: onOpenLink ?? (_) {}),
        ),
      ),
    ));
  }

  Future<void> copy(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('sizes itself from the rendering', (tester) async {
    await pump(tester);
    expect(tester.getSize(find.byType(RenderedMail)), const Size(400, 120));
  });

  testWidgets('copies a dragged selection across runs', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(const Offset(1, 10), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(const Offset(94, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await copy(tester);
    expect(copied, 'Hello world');
  });

  testWidgets('joins lines and cells with their separators', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(const Offset(1, 10), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(const Offset(139, 50));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await copy(tester);
    expect(copied, 'Hello world\n\nSecond\tcell');
  });

  testWidgets('opens links', (tester) async {
    Uri? opened;
    await pump(tester, onOpenLink: (uri) => opened = uri);
    await tester.tapAt(const Offset(60, 90));
    await tester.pump(const Duration(milliseconds: 600));
    expect(opened, Uri.parse('https://example.com/a'));
  });
}
