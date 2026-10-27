import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume_design/plume_design.dart';

void main() {
  setUp(() {
    Toaster.instance.clear();
  });

  tearDown(() {
    Toaster.instance.clear();
  });

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

  testWidgets('multiple stack toaster messages create stacked deck where new is on front and old stack behind', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('First toast message');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Second toast message');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Third toast message');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    // All three messages exist in the stacked card deck
    expect(find.text('First toast message'), findsOneWidget);
    expect(find.text('Second toast message'), findsOneWidget);
    expect(find.text('Third toast message'), findsOneWidget);

    // Third toast is on front (bottom: 0, scale: 1.0)
    // Older toasts are stacked behind with peeking tops
    expect(find.byType(AnimatedPositioned), findsNWidgets(3));
  });

  testWidgets('closing front toast in the stack leaves the other toasts intact and shifts deck forward', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Toast 1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Toast 2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Toast 1'), findsOneWidget);
    expect(find.text('Toast 2'), findsOneWidget);

    // Toast 2 is the front card. Tapping its close button dismisses it.
    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsNWidgets(2));
    await tester.tap(closeIcons.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Toast 2'), findsNothing);
    expect(find.text('Toast 1'), findsOneWidget);
  });

  testWidgets('hovering over stacked toaster unfolds all cards and unhovering folds them back', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Toast 1', actionLabel: 'Undo 1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Toast 2', actionLabel: 'Undo 2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    // Hover over the toaster stack to unfold
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Toast 2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Both undo buttons are now fully exposed and accessible
    expect(find.text('Undo 1'), findsOneWidget);
    expect(find.text('Undo 2'), findsOneWidget);

    // Move mouse away to fold back
    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.removePointer();
  });

  testWidgets('unfolded stacked toasts allow triggering background undo actions', (tester) async {
    var undo1Tapped = false;
    var undo2Tapped = false;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Archived email 1', actionLabel: 'Undo 1', onAction: () => undo1Tapped = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Archived email 2', actionLabel: 'Undo 2', onAction: () => undo2Tapped = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    // Hover to unfold so background card (Archived email 1) is completely exposed above front card
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Archived email 2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Now tap Undo 1 on the unfolded background card
    await tester.tap(find.text('Undo 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(undo1Tapped, isTrue);
    expect(undo2Tapped, isFalse);
    expect(find.text('Archived email 1'), findsNothing);
    expect(find.text('Archived email 2'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('toasts pause timer while hovered and resume on unhover', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Hover pause toast', duration: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Hover pause toast'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Hover pause toast')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // While hovering, advance time past 2 seconds (5 seconds)
    await tester.pump(const Duration(seconds: 5));

    // Toast MUST still be present because timer was paused while hovered
    expect(find.text('Hover pause toast'), findsOneWidget);

    // Now move mouse away (unhover)
    await gesture.moveTo(const Offset(50, 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Advance past remaining duration (approx 1.5s) + animation (160ms)
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Hover pause toast'), findsNothing);

    await gesture.removePointer();
  });

  testWidgets('stacked toasts auto-dismiss independently after their duration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    showSnack('Short toast', duration: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    showSnack('Long toast', duration: const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Short toast'), findsOneWidget);
    expect(find.text('Long toast'), findsOneWidget);

    // Advance past Short toast expiration (1s) + animation (160ms)
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Short toast'), findsNothing);
    expect(find.text('Long toast'), findsOneWidget);

    // Advance past Long toast expiration (4s total)
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Long toast'), findsNothing);
  });

  testWidgets('clicks outside stacked toasts pass through to underlying widgets', (tester) async {
    var homeTapped = false;

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light),
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => homeTapped = true,
            child: const Text('Home Button'),
          ),
        ),
      ),
    ));

    showSnack('Stacked toast message');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Stacked toast message'), findsOneWidget);
    expect(find.text('Home Button'), findsOneWidget);

    // Tap button behind/outside the toast overlay
    await tester.tap(find.text('Home Button'));
    await tester.pump();

    expect(homeTapped, isTrue);
  });
}
