import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/ui/actions.dart';
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

  testWidgets('a new message starts in To, and Esc closes it straight away', (t) async {
    final app = await DemoApp.start(t);
    app.ref.read(composeProvider.notifier).newMessage();
    await app.settle();
    expect(focusedIn(find.byType(RecipientField).first), isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await app.settle();
    expect(find.byType(ComposePanel), findsNothing);
  });

  testWidgets('Esc in the message closes the window, keeping the draft', (t) async {
    final app = await DemoApp.start(t);
    app.ref.read(composeProvider.notifier).newMessage();
    await app.settle();
    await t.enterText(find.widgetWithText(TextField, 'Subject'), 'Lunch');
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(bodyFocused(t), isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await app.settle();
    expect(find.byType(ComposePanel), findsNothing);
    expect(find.text('Draft saved'), findsOneWidget);
  });

  testWidgets('a reply starts in the message, and Esc closes it', (t) async {
    final app = await DemoApp.start(t);
    openThread(app.ref, app.ref.read(visibleThreadsProvider).value!.first);
    await app.settle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await app.settle();
    expect(find.byType(ComposePanel), findsOneWidget);
    expect(bodyFocused(t), isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await app.settle();
    expect(find.byType(ComposePanel), findsNothing);
  });
}
