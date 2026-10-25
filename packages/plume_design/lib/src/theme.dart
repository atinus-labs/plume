import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Surfaces of the app layout, which differ between light and dark in a way
/// the plain colour roles do not capture: in light mode panes are brighter
/// than the window background, in dark mode they are lighter than it too
/// but via different tones.
@immutable
final class PlumeSurfaces extends ThemeExtension<PlumeSurfaces> {
  const PlumeSurfaces({
    required this.window,
    required this.pane,
    required this.item,
    required this.itemHover,
    required this.selected,
    required this.onSelected,
    required this.unreadAccent,
  });

  /// Behind everything, including the navigation rail.
  final Color window;

  /// Large rounded sheets (reading pane, dialogs on the window).
  final Color pane;

  /// Rows in grouped lists.
  final Color item;
  final Color itemHover;

  /// The open conversation / active selection.
  final Color selected;
  final Color onSelected;

  /// Unread markers.
  final Color unreadAccent;

  static PlumeSurfaces of(BuildContext context) => Theme.of(context).extension<PlumeSurfaces>()!;

  factory PlumeSurfaces.from(ColorScheme s) {
    final light = s.brightness == Brightness.light;
    return PlumeSurfaces(
      window: light ? s.surfaceContainer : s.surface,
      pane: light ? s.surfaceContainerLowest : s.surfaceContainerLow,
      item: light ? s.surfaceContainerLowest : s.surfaceContainer,
      itemHover: light ? s.surfaceContainerLow : s.surfaceContainerHigh,
      selected: s.secondaryContainer,
      onSelected: s.onSecondaryContainer,
      unreadAccent: s.primary,
    );
  }

  @override
  PlumeSurfaces copyWith() => this;

  @override
  PlumeSurfaces lerp(PlumeSurfaces? other, double t) {
    if (other == null) return this;
    return PlumeSurfaces(
      window: Color.lerp(window, other.window, t)!,
      pane: Color.lerp(pane, other.pane, t)!,
      item: Color.lerp(item, other.item, t)!,
      itemHover: Color.lerp(itemHover, other.itemHover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      onSelected: Color.lerp(onSelected, other.onSelected, t)!,
      unreadAccent: Color.lerp(unreadAccent, other.unreadAccent, t)!,
    );
  }
}

/// Shifts [color] towards the theme's primary hue so that provider label
/// colours and account colours sit comfortably in any dynamic scheme.
Color harmonize(Color color, ColorScheme scheme) =>
    Color(Blend.harmonize(color.toARGB32(), scheme.primary.toARGB32()));

/// Tonal container/on-container pair for an arbitrary colour (account dots,
/// label chips, avatars), adapted to the scheme brightness.
({Color container, Color onContainer}) tonalPair(Color color, Brightness brightness) {
  final hct = Hct.fromInt(color.toARGB32());
  final palette = TonalPalette.of(hct.hue, hct.chroma.clamp(24, 48).toDouble());
  final dark = brightness == Brightness.dark;
  return (
    container: Color(palette.get(dark ? 30 : 90)),
    onContainer: Color(palette.get(dark ? 90 : 20)),
  );
}

/// Builds Plume's Material 3 Expressive theme.
abstract final class PlumeTheme {
  /// The brand seed used when the desktop exposes no accent colour.
  static const defaultSeed = Color(0xFF4C5BD4);

  static ThemeData build({
    required Brightness brightness,
    Color seed = defaultSeed,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
    double contrast = 0,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: variant,
      contrastLevel: contrast,
    );
    return fromScheme(scheme);
  }

  static ThemeData fromScheme(ColorScheme scheme) {
    final text = plumeTextTheme().apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final surfaces = PlumeSurfaces.from(scheme);

    // M3 Expressive buttons morph from round to squarer while pressed.
    WidgetStateProperty<OutlinedBorder> morphing({double rest = Corners.full, double pressed = Corners.medium}) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return RoundedRectangleBorder(borderRadius: Corners.all(pressed));
          return rest >= Corners.full
              ? const StadiumBorder()
              : RoundedRectangleBorder(borderRadius: Corners.all(rest));
        });

    final buttonText = WidgetStatePropertyAll(text.labelLarge);
    const buttonPadding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18));
    const buttonSize = WidgetStatePropertyAll(Size(48, 40));
    final springDuration = Spring.spatialFast.duration;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: surfaces.window,
      canvasColor: surfaces.window,
      extensions: [surfaces],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      // Material Symbols are variable fonts; these are the resting axes.
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24, fill: 0, weight: 400, grade: 0, opticalSize: 24),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      }),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: morphing(),
          textStyle: buttonText,
          padding: buttonPadding,
          minimumSize: buttonSize,
          animationDuration: springDuration,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(shape: morphing(), textStyle: buttonText, padding: buttonPadding, minimumSize: buttonSize),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: morphing(),
          textStyle: buttonText,
          padding: buttonPadding,
          minimumSize: buttonSize,
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(shape: morphing(), textStyle: buttonText, minimumSize: buttonSize),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return RoundedRectangleBorder(borderRadius: Corners.all(Corners.small + 2));
            }
            if (states.contains(WidgetState.selected)) {
              return RoundedRectangleBorder(borderRadius: Corners.all(Corners.medium));
            }
            return const StadiumBorder();
          }),
          animationDuration: springDuration,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        extendedTextStyle: text.titleSmallEmphasized,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaces.pane,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Corners.all(Corners.large))),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6, horizontal: 6)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Corners.all(Corners.medium))),
          minimumSize: const WidgetStatePropertyAll(Size(180, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        textStyle: text.labelLarge,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: Corners.all(Corners.small)),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        elevation: 3,
        width: 420,
        insetPadding: const EdgeInsets.all(16),
        showCloseIcon: true,
        closeIconColor: scheme.onInverseSurface,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.small + 2)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: Corners.all(Corners.large), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: Corners.all(Corners.large), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: Corners.all(Corners.large),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.28),
        selectionHandleColor: scheme.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(scheme.onSurfaceVariant.withValues(alpha: 0.35)),
        crossAxisMargin: 3,
        mainAxisMargin: 6,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? const Icon(Icons.check_rounded, size: 16) : null),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // ignore: deprecated_member_use
        year2023: false,
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
        circularTrackColor: scheme.secondaryContainer,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraSmall + 1)),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        textStyle: text.labelSmall,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(Corners.large)),
        ),
      ),
    );
  }
}
