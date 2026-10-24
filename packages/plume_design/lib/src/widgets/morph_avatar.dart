import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../shapes.dart';
import '../theme.dart';
import '../typography.dart';
import 'spring_builder.dart';

/// Deterministic, pleasant hues for people without a photo.
const _hues = [
  Color(0xFF4F6BED), Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFF43A047),
  Color(0xFFF4511E), Color(0xFFE53935), Color(0xFFD81B60), Color(0xFF8E24AA),
  Color(0xFF5E35B1), Color(0xFF3949AB), Color(0xFF00ACC1), Color(0xFFC0CA33),
  Color(0xFFFFB300), Color(0xFF6D4C41),
];

/// A stable colour for [key] (an email address).
Color colorForKey(String key) {
  var h = 0;
  for (final c in key.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _hues[h % _hues.length];
}

String initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return (first + second).toUpperCase();
}

/// An avatar that morphs from a circle into an expressive "cookie" with a
/// check mark when [selected]. Used for multi-select in message lists.
class MorphAvatar extends StatelessWidget {
  const MorphAvatar({
    super.key,
    required this.name,
    required this.colorKey,
    this.image,
    this.selected = false,
    this.size = 40,
    this.onTap,
    this.tooltip,
  });

  final String name;

  /// Key used to pick the fallback colour (usually the email address).
  final String colorKey;
  final ImageProvider? image;
  final bool selected;
  final double size;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = tonalPair(harmonize(colorForKey(colorKey), scheme), scheme.brightness);
    final avatar = SpringBuilder(
      value: selected ? 1 : 0,
      spring: Spring.spatialFast,
      builder: (context, t, _) {
        final clamped = unit(t);
        final shape = RadialShapeBorder(
          RadialShape.lerp(Shapes.circle, Shapes.cookie9, clamped),
          rotation: t * math.pi / 9,
        );
        final background = Color.lerp(tones.container, scheme.primary, clamped)!;
        return SizedBox.square(
          dimension: size,
          child: Material(
            shape: shape,
            color: background,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 1 - clamped,
                  child: image != null
                      ? Image(image: image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initials(theme, tones))
                      : _initials(theme, tones),
                ),
                if (t > 0.01)
                  Center(
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * t,
                      child: Opacity(
                        opacity: clamped,
                        child: Icon(Icons.check_rounded, color: scheme.onPrimary, size: size * 0.55),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    Widget result = avatar;
    if (onTap != null) {
      result = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: avatar),
      );
    }
    if (tooltip != null) result = Tooltip(message: tooltip, child: result);
    return result;
  }

  Widget _initials(ThemeData theme, ({Color container, Color onContainer}) tones) => Center(
        child: Text(
          initialsFor(name),
          style: withWeight(theme.textTheme.titleMedium!, 600).copyWith(
            color: tones.onContainer,
            fontSize: size * 0.4,
            height: 1,
          ),
        ),
      );
}
