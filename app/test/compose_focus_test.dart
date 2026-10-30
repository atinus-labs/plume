import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/compose/compose_panel.dart';
import 'package:plume/src/ui/compose/recipient_field.dart';

import 'support/demo_app.dart';

void main() {
  /// Whether the focused control is inside [finder].
  bool focusedIn(Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null && find.descendant(of: finder, matching: find.byWidget(focused.widget)).evaluate().isNotEmpty;
  }

  bool bodyFocused(WidgetTester t) =>
      FocusManager.instance.primaryFocus == t.widget<QuillEditor>(find.byType(QuillEditor)).focusNode;

  for (final (name, size) in [('docked', const Size(1600, 1000)), ('full window', const Size(412, 900))]) {
    testWidgets('Tab moves through a $name compose window in order', (t) async {
      final app = await DemoApp.start(t, size: size);
      app.ref.read(composeProvider.notifier).newMessage();
      await app.settle();
      final subject = find.widgetWithText(TextField, 'Subject');

      final to = find.descendant(of: find.byType(RecipientField).first, matching: find.byType(TextField));
      await t.enterText(to, 'am');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(find.text('Cc  Bcc'), findsOneWidget);
      expect(focusedIn(find.widgetWithText(TextButton, 'Cc  Bcc')), isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(focusedIn(subject), isTrue);

      await t.enterText(subject, 'sadfkusadhf');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      // From Subject, Tab goes on to the message.
      expect(bodyFocused(t), isTrue, reason: 'focus went to ${FocusManager.instance.primaryFocus}');

      // And back.
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(focusedIn(subject), isTrue);
      expect(focusedIn(find.byType(ComposePanel)), isTrue);
    });
  }
}
