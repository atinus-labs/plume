import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_design/plume_design.dart';

/// Plume's mark: an envelope on an expressive "cookie" shape, in the theme's
/// primary colours. With [animate], the shape slowly morphs and turns.
class PlumeLogo extends StatefulWidget {
  const PlumeLogo({super.key, this.size = 64, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<PlumeLogo> createState() => _PlumeLogoState();
}

class _PlumeLogoState extends State<PlumeLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        final morph = (math.sin(v * 2 * math.pi) + 1) / 2;
        return SizedBox.square(
          dimension: widget.size,
          child: Material(
            color: scheme.primary,
            shape: RadialShapeBorder(RadialShape.lerp(Shapes.cookie12, Shapes.softBurst, morph * 0.6), rotation: v * 2 * math.pi),
            child: Icon(Symbols.mail_rounded, fill: 1, size: widget.size * 0.46, color: scheme.onPrimary),
          ),
        );
      },
    );
  }
}
