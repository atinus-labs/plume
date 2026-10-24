import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// A Material 3 Expressive motion spring.
///
/// Values follow the M3 Expressive motion scheme (mass 1, stiffness and
/// damping ratio per token). Use [simulate] for interruptible, velocity-
/// preserving animations and [curve] + [duration] where only implicit
/// animations are available.
final class Spring {
  const Spring._(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;

  SpringDescription get description =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: dampingRatio);

  /// A simulation from [from] to [to] starting at [velocity] (units/second).
  SpringSimulation simulate(double from, double to, {double velocity = 0}) => SpringSimulation(
        description,
        from,
        to,
        velocity,
        tolerance: const Tolerance(distance: 0.0005, velocity: 0.01),
      );

  /// Equivalent curve for a 0→1 transition, for implicit animations.
  Curve get curve => _SpringCurve(this);

  /// Time for a 0→1 transition to settle.
  Duration get duration {
    final cached = _durations[this];
    if (cached != null) return cached;
    final sim = simulate(0, 1);
    var t = 0.0;
    const step = 1 / 240;
    var settled = 0.0;
    while (t < 3) {
      final x = sim.x(t);
      if ((x - 1).abs() > 0.002) settled = t;
      t += step;
    }
    final d = Duration(microseconds: ((settled + step) * 1e6).round());
    _durations[this] = d;
    return d;
  }

  static final _durations = <Spring, Duration>{};

  // Expressive spatial springs: overshoot slightly; for position, size,
  // shape. Use for the hero moments.
  static const spatialFast = Spring._(800, 0.6);
  static const spatial = Spring._(380, 0.8);
  static const spatialSlow = Spring._(200, 0.8);

  // Standard spatial springs: no visible bounce; for utilitarian motion.
  static const standardFast = Spring._(1400, 0.9);
  static const standard = Spring._(700, 0.9);
  static const standardSlow = Spring._(300, 0.9);

  // Effects springs: critically damped; for colour and opacity.
  static const effectsFast = Spring._(3800, 1);
  static const effects = Spring._(1600, 1);
  static const effectsSlow = Spring._(800, 1);

  @override
  bool operator ==(Object other) =>
      other is Spring && other.stiffness == stiffness && other.dampingRatio == dampingRatio;

  @override
  int get hashCode => Object.hash(stiffness, dampingRatio);
}

class _SpringCurve extends Curve {
  _SpringCurve(this.spring)
      : _sim = spring.simulate(0, 1),
        _seconds = spring.duration.inMicroseconds / 1e6;

  final Spring spring;
  final SpringSimulation _sim;
  final double _seconds;

  @override
  double transformInternal(double t) => _sim.x(t * _seconds);
}

/// Clamps to [0, 1].
double unit(double v) => math.min(1, math.max(0, v));
