import 'package:flutter/material.dart';

import '../../config.dart';

/// Plume's original artwork, preserving its colours and transparent background.
/// With [animate], the mark gently floats unless reduced motion is enabled.
class PlumeLogo extends StatefulWidget {
  const PlumeLogo({super.key, this.size = 64, this.animate = false});

  final double size;
  final bool animate;

  @override
  State<PlumeLogo> createState() => _PlumeLogoState();
}

class _PlumeLogoState extends State<PlumeLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant PlumeLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, -widget.size * 0.025 * Curves.easeInOut.transform(_c.value)),
            child: child,
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
