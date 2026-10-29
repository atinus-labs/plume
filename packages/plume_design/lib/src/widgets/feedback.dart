import 'package:flutter/material.dart';

import '../motion.dart';
import 'transitions.dart';

/// A number that rolls to its new value: up when it grows, down when it
/// shrinks. A changed count gets noticed without flashing.
class AnimatedCount extends StatefulWidget {
  const AnimatedCount(this.value, {super.key, this.style, this.format});

  final int value;
  final TextStyle? style;

  /// Text for a value; defaults to the plain number.
  final String Function(int value)? format;

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> {
  int _direction = 1;

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _direction = widget.value > oldWidget.value ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.format?.call(widget.value) ?? '${widget.value}',
      key: ValueKey(widget.value),
      // Same-width digits, so the number keeps its width as it rolls.
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: [...?widget.style?.fontFeatures, const FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      softWrap: false,
    );
    if (reduceMotion(context)) return text;
    final size = widget.style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;
    return AnimatedSize(
      duration: Spring.standard.duration,
      curve: Spring.standard.curve,
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: sharedAxis(direction: _direction, distance: size * 0.9),
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, ?current]),
        child: text,
      ),
    );
  }
}

/// Gives [child] a short springy bump when [active] turns on: a physical
/// confirmation for toggles such as starring.
class Pop extends StatefulWidget {
  const Pop({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<Pop> createState() => _PopState();
}

class _PopState extends State<Pop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController.unbounded(vsync: this, value: 1);

  @override
  void didUpdateWidget(Pop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !reduceMotion(context)) {
      _controller.animateWith(Spring.spatialFast.simulate(_controller.value, 1, velocity: 6));
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
        builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      );
}

/// Plays a press on [child] each time [trigger] changes to a new non-null
/// value: it squishes and springs back while a state layer flashes behind
/// it. Shows that something other than a click, like a keyboard shortcut,
/// used this control.
class Press extends StatefulWidget {
  const Press({super.key, required this.trigger, required this.child, this.shape = const CircleBorder()});

  final Object? trigger;
  final ShapeBorder shape;
  final Widget child;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> with TickerProviderStateMixin {
  late final _scale = AnimationController.unbounded(vsync: this, value: 1);
  late final _layer = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void didUpdateWidget(Press oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger == null || widget.trigger == oldWidget.trigger) return;
    // Under reduced motion only the state layer shows.
    if (!reduceMotion(context)) {
      _scale.animateWith(Spring.spatialFast.simulate(_scale.value, 1, velocity: -6));
    }
    _layer.animateWith(Spring.effectsSlow.simulate(1, 0));
  }

  @override
  void dispose() {
    _scale.dispose();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: Listenable.merge([_scale, _layer]),
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(shape: widget.shape, color: color.withValues(alpha: 0.12 * unit(_layer.value))),
              ),
            ),
          ),
          Transform.scale(scale: _scale.value, child: child),
        ],
      ),
      child: widget.child,
    );
  }
}
