import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../shapes.dart';

/// The M3 Expressive loading indicator: a shape that morphs through the
/// expressive shape sequence while rotating.
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({super.key, this.size = 48, this.color, this.contained = false, this.delay = Duration.zero});

  final double size;
  final Color? color;

  /// Shows nothing until loading has taken this long, so quick loads never
  /// flash an indicator.
  final Duration delay;

  /// Draws the indicator on a circular container, for use over content.
  final bool contained;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator> with SingleTickerProviderStateMixin {
  static const _morphMs = 650;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _morphMs * Shapes.loadingSequence.length),
  );
  Timer? _wait;
  late bool _shown = widget.delay == Duration.zero;

  @override
  void initState() {
    super.initState();
    if (_shown) {
      _controller.repeat();
    } else {
      _wait = Timer(widget.delay, () {
        setState(() => _shown = true);
        _controller.repeat();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? (widget.contained ? scheme.onPrimaryContainer : scheme.primary);
    final indicator = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _MorphPainter(_controller, color),
      ),
    );
    if (!_shown) return SizedBox.square(dimension: widget.size);
    return Semantics(
      label: 'Loading',
      child: SizedBox.square(
        dimension: widget.size,
        child: widget.contained
            ? DecoratedBox(
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: Padding(padding: EdgeInsets.all(widget.size * 0.16), child: indicator),
              )
            : Padding(padding: EdgeInsets.all(widget.size * 0.105), child: indicator),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.animation, this.color) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  static final _curve = Spring.spatialFast.curve;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = Shapes.loadingSequence;
    final t = animation.value * shapes.length;
    final index = t.floor() % shapes.length;
    final local = t - t.floor();
    final from = shapes[index];
    final to = shapes[(index + 1) % shapes.length];
    final p = _curve.transform(math.min(1.0, local / 0.75));

    final radii = Float32List(RadialShape.samples);
    for (var i = 0; i < radii.length; i++) {
      radii[i] = from.radii[i] + (to.radii[i] - from.radii[i]) * p;
    }
    final rotation = animation.value * math.pi * 4 + (index + p) * math.pi / 2;
    final rect = Offset.zero & size;
    final path = _pathFromRadii(radii, rect, rotation);
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  Path _pathFromRadii(Float32List radii, Rect rect, double rotation) {
    final n = radii.length;
    final cx = rect.center.dx, cy = rect.center.dy, r = rect.width / 2;
    Offset at(int i) {
      final a = -math.pi / 2 + 2 * math.pi * i / n + rotation;
      return Offset(cx + radii[i] * r * math.cos(a), cy + radii[i] * r * math.sin(a));
    }

    final path = Path();
    final start = Offset.lerp(at(n - 1), at(0), 0.5)!;
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final p = at(i);
      final mid = Offset.lerp(p, at((i + 1) % n), 0.5)!;
      path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.color != color;
}

/// The M3 Expressive wavy linear progress indicator (indeterminate).
class WavyProgressIndicator extends StatefulWidget {
  const WavyProgressIndicator({super.key, this.height = 10, this.color, this.trackColor});

  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  State<WavyProgressIndicator> createState() => _WavyProgressIndicatorState();
}

class _WavyProgressIndicatorState extends State<WavyProgressIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1750))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavyPainter(
            _controller,
            widget.color ?? scheme.primary,
            widget.trackColor ?? scheme.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter(this.animation, this.color, this.track) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final Color track;

  static const _stroke = 4.0;
  static const _wavelength = 26.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final amp = math.max(0.0, size.height / 2 - _stroke / 2) * 0.8;
    final v = animation.value;

    // Two travelling segments, as in the M3 indeterminate linear indicator.
    final head1 = Easing.standard.transform(unit(v / 0.75));
    final tail1 = Easing.standard.transform(unit((v - 0.25) / 0.75));
    final head2 = Easing.standard.transform(unit((v - 0.45) / 0.55));
    final tail2 = Easing.standard.transform(unit((v - 0.6) / 0.4));

    final active = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    final phase = v * 2 * math.pi * 3;
    final segments = [(tail1 * w, head1 * w), (tail2 * w, head2 * w)];
    // Track pieces between and around segments, separated by gaps.
    final stops = <double>[0];
    for (final s in segments) {
      if (s.$2 - s.$1 < 1) continue;
      stops
        ..add(s.$1 - _gap - _stroke)
        ..add(s.$2 + _gap + _stroke);
    }
    stops.add(w);
    for (var i = 0; i + 1 < stops.length; i += 2) {
      final a = math.max(0.0, stops[i]), b = math.min(w, stops[i + 1]);
      if (b - a > _stroke) canvas.drawLine(Offset(a + _stroke / 2, cy), Offset(b - _stroke / 2, cy), trackPaint);
    }
    for (final s in segments) {
      if (s.$2 - s.$1 < 1) continue;
      final path = Path();
      for (var x = s.$1; x <= s.$2; x += 1.5) {
        final y = cy + amp * math.sin(x / _wavelength * 2 * math.pi - phase);
        if (x == s.$1) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, active);
    }
  }

  @override
  bool shouldRepaint(_WavyPainter old) => old.color != color || old.track != track;
}
