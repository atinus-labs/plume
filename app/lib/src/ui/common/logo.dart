import 'package:flutter/material.dart';
import 'package:plume_design/plume_design.dart';

import '../../config.dart';

/// Plume's original artwork, preserving its colours and transparent background.
/// With [animate], the mark rises gently into place when it appears, then
/// stays still.
class PlumeLogo extends StatefulWidget {
  const PlumeLogo({super.key, this.size = 64, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<PlumeLogo> createState() => _PlumeLogoState();
}

class _PlumeLogoState extends State<PlumeLogo> with SingleTickerProviderStateMixin {
  /// How far the mark still has to rise, as a share of its size.
  late final _rise = AnimationController.unbounded(vsync: this, value: widget.animate ? 1 : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rise.value == 0 || _rise.isAnimating) return;
    if (reduceMotion(context)) {
      _rise.value = 0;
    } else {
      _rise.animateWith(Spring.spatialSlow.simulate(1, 0));
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _rise,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, widget.size * 0.08 * _rise.value),
            child: Opacity(opacity: unit(1 - _rise.value), child: child),
          ),
          child: Image.asset(
            AppConfig.iconAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: AppConfig.appName,
          ),
        ),
      );
}
