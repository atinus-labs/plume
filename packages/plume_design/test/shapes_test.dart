import 'package:flutter_test/flutter_test.dart';
import 'package:plume_design/plume_design.dart';

void main() {
  test('shapes are normalised into the unit square', () {
    for (final s in [Shapes.circle, Shapes.pill, Shapes.pentagon, Shapes.cookie9, Shapes.burst, Shapes.square]) {
      final max = s.radii.reduce((a, b) => a > b ? a : b);
      expect(max, inInclusiveRange(0.99, 1.42), reason: s.name);
      expect(s.radii.every((r) => r > 0.3), isTrue, reason: s.name);
    }
  });

  test('springs settle in a sensible time', () {
    expect(Spring.spatial.duration.inMilliseconds, inInclusiveRange(250, 900));
    expect(Spring.effectsFast.duration.inMilliseconds, lessThan(250));
    expect(Spring.spatial.curve.transform(1), 1);
  });
}
