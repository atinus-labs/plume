import 'package:flutter/widgets.dart';

import '../motion.dart';
import 'transitions.dart';

/// Animates a double towards [value] with a spring, preserving velocity when
/// the target changes mid-flight. This is the building block for the
/// interruptible M3 Expressive motion used across the app.
class SpringBuilder extends StatefulWidget {
  const SpringBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.spring = Spring.spatial,
    this.child,
  });

  final double value;
  final Spring spring;
  final ValueWidgetBuilder<double> builder;
  final Widget? child;

  @override
  State<SpringBuilder> createState() => _SpringBuilderState();
}

class _SpringBuilderState extends State<SpringBuilder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(vsync: this, value: widget.value);

  @override
  void didUpdateWidget(SpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    if (reduceMotion(context)) {
      _controller.value = widget.value;
    } else {
      _controller.animateWith(widget.spring.simulate(_controller.value, widget.value, velocity: _controller.velocity));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => widget.builder(context, _controller.value, child),
        child: widget.child,
      );
}
