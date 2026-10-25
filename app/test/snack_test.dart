import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume_design/plume_design.dart';

void main() {
  testWidgets('showSnack displays close icon button and closes on tap', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Toast message to close');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Toast message to close'), findsOneWidget);
    final closeButtonFinder = find.byIcon(Icons.close);
    expect(closeButtonFinder, findsOneWidget);

    await tester.tap(closeButtonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Toast message to close'), findsNothing);
  });

  testWidgets('showSnack with action button also provides close button', (tester) async {
    var actionTapped = false;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack(
      'Conversation archived',
      actionLabel: 'Undo',
      onAction: () => actionTapped = true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Conversation archived'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Tapping close dismisses without triggering undo action
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(actionTapped, isFalse);
    expect(find.text('Conversation archived'), findsNothing);
  });

  testWidgets('showSnack allows hiding close icon if explicitly disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('No close button', showCloseIcon: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('No close button'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
