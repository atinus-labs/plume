import 'package:flutter/material.dart';

import '../tokens.dart';

/// Corner radii for an item in an M3 Expressive grouped ("connected") list:
/// large outer corners on the ends of the group, small inner corners
/// between items.
BorderRadius groupedRadius(int index, int count, {double outer = Corners.largeIncreased, double inner = Corners.extraSmall}) {
  final top = index == 0 ? outer : inner;
  final bottom = index == count - 1 ? outer : inner;
  return BorderRadius.vertical(top: Radius.circular(top), bottom: Radius.circular(bottom));
}

/// The M3 Expressive floating toolbar: a pill of actions floating above
/// content.
class FloatingToolbar extends StatelessWidget {
  const FloatingToolbar({super.key, required this.children, this.vibrant = false, this.padding = 6});

  final List<Widget> children;

  /// Uses the primary container palette for emphasis.
  final bool vibrant;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = vibrant ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = vibrant ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: IconTheme.merge(
        data: IconThemeData(color: fg),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// A large rounded sheet on the window background (reading pane, settings
/// panes).
class Pane extends StatelessWidget {
  const Pane({super.key, required this.child, this.color, this.radius = Corners.extraLarge});

  final Widget child;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(radius)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
