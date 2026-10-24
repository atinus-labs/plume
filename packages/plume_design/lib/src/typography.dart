import 'package:flutter/material.dart';

/// The bundled variable font (Google Sans Flex, SIL OFL).
const kPlumeFontFamily = 'Google Sans Flex';
const _package = 'plume_design';

/// A text style on Google Sans Flex with explicit variable axes. Flutter does
/// not map [FontWeight] onto the `wght` axis of variable fonts by itself, so
/// weight, optical size and roundness are always set through variations.
TextStyle flexStyle({
  required double size,
  required double height,
  required double weight,
  double letterSpacing = 0,
  double roundness = 0,
  double width = 100,
}) {
  return TextStyle(
    fontFamily: kPlumeFontFamily,
    package: _package,
    fontSize: size,
    height: height / size,
    letterSpacing: letterSpacing,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: [
      FontVariation.weight(weight),
      FontVariation.opticalSize(size.clamp(6, 144)),
      FontVariation('ROND', roundness),
      if (width != 100) FontVariation.width(width),
    ],
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// Returns [style] with a different weight, keeping the other axes.
TextStyle withWeight(TextStyle style, double weight) {
  final variations = [
    for (final v in style.fontVariations ?? const <FontVariation>[])
      if (v.axis != 'wght') v,
    FontVariation.weight(weight),
  ];
  return style.copyWith(
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: variations,
  );
}

/// The M3 type scale on Google Sans Flex. Display and headline roles get a
/// touch of roundness, which is part of the Expressive look; reading text
/// stays neutral.
TextTheme plumeTextTheme() {
  return TextTheme(
    displayLarge: flexStyle(size: 57, height: 64, weight: 400, letterSpacing: -0.25, roundness: 60),
    displayMedium: flexStyle(size: 45, height: 52, weight: 400, roundness: 60),
    displaySmall: flexStyle(size: 36, height: 44, weight: 400, roundness: 60),
    headlineLarge: flexStyle(size: 32, height: 40, weight: 400, roundness: 40),
    headlineMedium: flexStyle(size: 28, height: 36, weight: 400, roundness: 40),
    headlineSmall: flexStyle(size: 24, height: 32, weight: 420, roundness: 30),
    titleLarge: flexStyle(size: 22, height: 28, weight: 450, roundness: 20),
    titleMedium: flexStyle(size: 16, height: 24, weight: 550, letterSpacing: 0.1),
    titleSmall: flexStyle(size: 14, height: 20, weight: 550, letterSpacing: 0.1),
    bodyLarge: flexStyle(size: 16, height: 24, weight: 400, letterSpacing: 0.2),
    bodyMedium: flexStyle(size: 14, height: 20, weight: 400, letterSpacing: 0.15),
    bodySmall: flexStyle(size: 12, height: 16, weight: 400, letterSpacing: 0.3),
    labelLarge: flexStyle(size: 14, height: 20, weight: 550, letterSpacing: 0.1),
    labelMedium: flexStyle(size: 12, height: 16, weight: 550, letterSpacing: 0.4),
    labelSmall: flexStyle(size: 11, height: 16, weight: 550, letterSpacing: 0.4),
  );
}

/// M3 Expressive "emphasized" variants, used for hierarchy (unread mail,
/// selected navigation, headings).
extension EmphasizedText on TextTheme {
  TextStyle get displaySmallEmphasized => withWeight(displaySmall!, 560);
  TextStyle get headlineSmallEmphasized => withWeight(headlineSmall!, 560);
  TextStyle get headlineMediumEmphasized => withWeight(headlineMedium!, 560);
  TextStyle get titleLargeEmphasized => withWeight(titleLarge!, 620);
  TextStyle get titleMediumEmphasized => withWeight(titleMedium!, 700);
  TextStyle get titleSmallEmphasized => withWeight(titleSmall!, 700);
  TextStyle get bodyLargeEmphasized => withWeight(bodyLarge!, 600);
  TextStyle get bodyMediumEmphasized => withWeight(bodyMedium!, 650);
  TextStyle get labelLargeEmphasized => withWeight(labelLarge!, 700);
  TextStyle get labelMediumEmphasized => withWeight(labelMedium!, 700);
}
