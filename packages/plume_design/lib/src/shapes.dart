import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart';

/// A closed shape that is star-shaped around its centre, stored as its
/// radius at evenly spaced angles.
///
/// Any two radial shapes morph cleanly by interpolating radii, which is how
/// the M3 Expressive shape morphs (loading indicator, avatar selection,
/// toggles) are drawn without a polygon-matching library.
final class RadialShape {
  RadialShape._(this.radii, this.name);

  /// Radii in the unit square, starting at the top and going clockwise.
  final Float32List radii;
  final String name;

  static const samples = 192;

  /// Builds a shape from a polar function `r(θ)`. Normalised to fit the unit
  /// square afterwards.
  factory RadialShape.polar(String name, double Function(double theta) r) {
    final out = Float32List(samples);
    for (var i = 0; i < samples; i++) {
      out[i] = r(_angle(i)).toDouble();
    }
    return RadialShape._(_fit(out), name);
  }

  /// Builds a shape from a signed distance function (negative inside) by
  /// casting rays from the centre.
  factory RadialShape.sdf(String name, double Function(double x, double y) sdf) {
    final out = Float32List(samples);
    for (var i = 0; i < samples; i++) {
      final a = _angle(i);
      final dx = math.cos(a), dy = math.sin(a);
      var lo = 0.0, hi = 2.0;
      for (var k = 0; k < 28; k++) {
        final mid = (lo + hi) / 2;
        if (sdf(dx * mid, dy * mid) < 0) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      out[i] = lo;
    }
    return RadialShape._(_fit(out), name);
  }

  static double _angle(int i) => -math.pi / 2 + 2 * math.pi * i / samples;

  /// Scales radii so the shape touches the unit square on its largest axis.
  static Float32List _fit(Float32List r) {
    var maxX = 0.0, maxY = 0.0;
    for (var i = 0; i < samples; i++) {
      final a = _angle(i);
      maxX = math.max(maxX, (r[i] * math.cos(a)).abs());
      maxY = math.max(maxY, (r[i] * math.sin(a)).abs());
    }
    final s = 1 / math.max(maxX, maxY);
    for (var i = 0; i < samples; i++) {
      r[i] *= s;
    }
    return r;
  }

  static RadialShape lerp(RadialShape a, RadialShape b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final out = Float32List(samples);
    for (var i = 0; i < samples; i++) {
      out[i] = a.radii[i] + (b.radii[i] - a.radii[i]) * t;
    }
    return RadialShape._(out, '${a.name}→${b.name}');
  }

  /// The shape scaled into [rect], rotated by [rotation] radians.
  Path toPath(Rect rect, {double rotation = 0}) {
    final cx = rect.center.dx, cy = rect.center.dy;
    final hw = rect.width / 2, hh = rect.height / 2;
    final path = Path();
    final points = List<Offset>.generate(samples, (i) {
      final a = _angle(i) + rotation;
      return Offset(cx + radii[i] * hw * math.cos(a), cy + radii[i] * hh * math.sin(a));
    });
    // Quadratic segments through midpoints keep the outline smooth even
    // where neighbouring samples change direction sharply.
    final first = Offset.lerp(points.last, points.first, 0.5)!;
    path.moveTo(first.dx, first.dy);
    for (var i = 0; i < samples; i++) {
      final p = points[i];
      final next = points[(i + 1) % samples];
      final mid = Offset.lerp(p, next, 0.5)!;
      path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }
}

double _sgnPow(double v, double p) => v.sign * math.pow(v.abs(), p).toDouble();

double _roundedPolygonSdf(double x, double y, int n, double radius, double rounding) {
  // Inigo Quilez's regular polygon SDF, shrunk then offset to round corners.
  final r = radius - rounding;
  final an = math.pi / n;
  final acsX = math.cos(an), acsY = math.sin(an);
  var bn = (math.atan2(x, y) % (2 * an)) - an;
  if (bn < -an) bn += 2 * an;
  final len = math.sqrt(x * x + y * y);
  var px = len * math.cos(bn);
  var py = (len * math.sin(bn)).abs();
  px -= r * acsX;
  py -= r * acsY;
  py += (-py).clamp(0.0, r * acsY);
  final d = math.sqrt(px * px + py * py) * px.sign;
  return d - rounding;
}

double _roundedBoxSdf(double x, double y, double hw, double hh, double r) {
  final qx = x.abs() - hw + r, qy = y.abs() - hh + r;
  final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
  return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
}

/// The M3 Expressive shape library (approximations of `MaterialShapes`).
abstract final class Shapes {
  static final circle = RadialShape.polar('circle', (_) => 1);
  static final square = RadialShape.sdf('square', (x, y) => _roundedBoxSdf(x, y, 0.8, 0.8, 0.24));
  static final pill = RadialShape.sdf('pill', (x, y) => _roundedBoxSdf(x, y, 1, 0.52, 0.52));
  static final oval = RadialShape.polar('oval', (a) {
    const ax = 1.0, by = 0.72;
    return ax * by / math.sqrt(math.pow(by * math.cos(a), 2) + math.pow(ax * math.sin(a), 2));
  });
  static final diamond =
      RadialShape.sdf('diamond', (x, y) => _roundedPolygonSdf(x * 1.15, y * 0.9, 4, 0.95, 0.16));
  static final pentagon = RadialShape.sdf('pentagon', (x, y) => _roundedPolygonSdf(x, -y, 5, 0.95, 0.2));
  static final gem = RadialShape.sdf('gem', (x, y) => _roundedPolygonSdf(x * 1.05, y * 0.95, 6, 0.95, 0.18));
  static final triangle = RadialShape.sdf('triangle', (x, y) => _roundedPolygonSdf(x, -y + 0.2, 3, 0.95, 0.22));

  static RadialShape cookie(int n, double depth) =>
      RadialShape.polar('cookie$n', (a) => 1 + depth * math.cos(n * a));
  static final cookie4 = cookie(4, 0.1);
  static final cookie6 = cookie(6, 0.075);
  static final cookie7 = cookie(7, 0.07);
  static final cookie9 = cookie(9, 0.06);
  static final cookie12 = cookie(12, 0.045);

  static final clover4 = RadialShape.polar('clover4', (a) => 0.72 + 0.28 * math.pow(math.cos(2 * a).abs(), 0.6));
  static final clover8 = RadialShape.polar('clover8', (a) => 0.8 + 0.2 * math.pow(math.cos(4 * a).abs(), 0.7));

  static final sunny = RadialShape.polar('sunny', (a) => 1 + 0.07 * _sgnPow(math.cos(8 * a), 0.75));
  static final verySunny = RadialShape.polar('verySunny', (a) => 1 + 0.13 * _sgnPow(math.cos(8 * a), 0.7));
  static final softBurst = RadialShape.polar('softBurst', (a) => 1 + 0.1 * _sgnPow(math.cos(10 * a), 0.8));
  static final burst = RadialShape.polar('burst', (a) => 1 + 0.17 * _sgnPow(math.cos(12 * a), 0.45));
  static final flower = RadialShape.polar('flower', (a) => 0.7 + 0.3 * math.pow(math.cos(4 * a).abs(), 0.45));
  static final puffy = RadialShape.polar('puffy', (a) => 0.84 + 0.16 * math.pow(math.cos(3 * a).abs(), 0.35));

  /// Shapes used by the morphing loading indicator, in M3 order.
  static final loadingSequence = [softBurst, cookie9, pentagon, pill, sunny, cookie4, oval];
}

/// A [ShapeBorder] that draws a [RadialShape] and morphs when lerped with
/// another [RadialShapeBorder] or a [CircleBorder].
final class RadialShapeBorder extends OutlinedBorder {
  const RadialShapeBorder(this.shape, {this.rotation = 0, super.side});

  final RadialShape shape;
  final double rotation;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shape.toPath(rect.deflate(side.width), rotation: rotation);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => shape.toPath(rect, rotation: rotation);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(shape.toPath(rect.deflate(side.width / 2), rotation: rotation), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => RadialShapeBorder(shape, rotation: rotation, side: side.scale(t));

  @override
  RadialShapeBorder copyWith({BorderSide? side}) => RadialShapeBorder(shape, rotation: rotation, side: side ?? this.side);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    final from = _asRadial(a);
    if (from == null) return super.lerpFrom(a, t);
    return RadialShapeBorder(
      RadialShape.lerp(from.shape, shape, t),
      rotation: from.rotation + (rotation - from.rotation) * t,
      side: BorderSide.lerp(from.side, side, t),
    );
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    final to = _asRadial(b);
    if (to == null) return super.lerpTo(b, t);
    return RadialShapeBorder(
      RadialShape.lerp(shape, to.shape, t),
      rotation: rotation + (to.rotation - rotation) * t,
      side: BorderSide.lerp(side, to.side, t),
    );
  }

  static RadialShapeBorder? _asRadial(ShapeBorder? b) => switch (b) {
        RadialShapeBorder() => b,
        CircleBorder(:final side) => RadialShapeBorder(Shapes.circle, side: side),
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is RadialShapeBorder && identical(other.shape, shape) && other.rotation == rotation && other.side == side;

  @override
  int get hashCode => Object.hash(shape, rotation, side);
}
