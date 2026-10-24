import 'package:flutter/widgets.dart';

/// M3 Expressive corner radius scale.
abstract final class Corners {
  static const none = 0.0;
  static const extraSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const largeIncreased = 20.0;
  static const extraLarge = 28.0;
  static const extraLargeIncreased = 32.0;
  static const extraExtraLarge = 48.0;
  static const full = 1000.0;

  static BorderRadius all(double r) => BorderRadius.all(Radius.circular(r));
}

/// 4dp spacing grid.
abstract final class Space {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Window size classes from the M3 adaptive layout guidance, including the
/// large and extra-large classes added with M3 Expressive.
enum WindowClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static WindowClass of(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    if (width < 1600) return large;
    return extraLarge;
  }

  bool operator >=(WindowClass other) => index >= other.index;
  bool operator <(WindowClass other) => index < other.index;
}
