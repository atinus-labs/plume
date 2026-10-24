import 'package:flutter/material.dart';
import 'package:plume_design/plume_design.dart';

/// A calm, centred empty state with an icon or a custom illustration.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.illustration,
    required this.title,
    this.message,
    this.shape,
    this.action,
  }) : assert((icon == null) != (illustration == null));

  final IconData? icon;
  final Widget? illustration;
  final String title;
  final String? message;
  final RadialShape? shape;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Spring.spatial.duration,
          curve: Spring.spatial.curve,
          builder: (context, t, child) => Opacity(
            opacity: unit(t),
            child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 112,
                child: illustration ?? Material(
                  color: scheme.secondaryContainer,
                  shape: RadialShapeBorder(shape ?? Shapes.cookie9),
                  child: Icon(icon, size: 44, color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(title, style: theme.textTheme.titleLargeEmphasized, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Space.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: Space.xl), action!],
            ],
          ),
        ),
      ),
    );
  }
}
