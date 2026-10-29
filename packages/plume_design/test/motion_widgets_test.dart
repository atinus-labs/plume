import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume_design/plume_design.dart';

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
      ),
    );

void main() {
  testWidgets('Presence collapses a leaving row and ignores taps on it', (tester) async {
    var taps = 0;
    Widget row(bool present) => _host(Presence(
          present: present,
          child: GestureDetector(onTap: () => taps++, child: const SizedBox(width: 100, height: 60)),
        ));
    await tester.pumpWidget(row(true));
    expect(tester.getSize(find.byType(Presence)).height, 60);

    await tester.pumpWidget(row(false));
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getSize(find.byType(Presence)).height;
    expect(mid, inExclusiveRange(0, 60));
    await tester.tap(find.byType(Presence), warnIfMissed: false);
    expect(taps, 0);

    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Presence)).height, 0);
  });

  testWidgets('Presence grows an arriving row open', (tester) async {
    await tester.pumpWidget(_host(const Presence(appear: true, child: SizedBox(width: 100, height: 60))));
    expect(tester.getSize(find.byType(Presence)).height, 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Presence)).height, 60);
  });

  testWidgets('AnimatedCount settles on the new value', (tester) async {
    await tester.pumpWidget(_host(const AnimatedCount(3, format: _new)));
    await tester.pumpWidget(_host(const AnimatedCount(4, format: _new)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('3 new'), findsOneWidget, reason: 'rolling out');
    expect(find.text('4 new'), findsOneWidget, reason: 'rolling in');
    await tester.pumpAndSettle();
    expect(find.text('3 new'), findsNothing);
    expect(find.text('4 new'), findsOneWidget);
  });

  testWidgets('reduced motion skips travel', (tester) async {
    Widget spring(double v) => _host(
          SpringBuilder(value: v, builder: (context, t, _) => Text('$t')),
          reduce: true,
        );
    await tester.pumpWidget(spring(0));
    await tester.pumpWidget(spring(1));
    expect(find.text('1.0'), findsOneWidget);

    await tester.pumpWidget(_host(const AnimatedCount(1), reduce: true));
    await tester.pumpWidget(_host(const AnimatedCount(2), reduce: true));
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });
}

String _new(int n) => '$n new';
