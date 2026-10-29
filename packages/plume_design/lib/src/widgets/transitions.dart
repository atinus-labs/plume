import 'package:flutter/material.dart';

import '../motion.dart';

/// Whether the system asks for reduced motion. Spatial motion is skipped
/// then: state still changes, just without travel.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// M3 shared-axis transition for an [AnimatedSwitcher], for content with a
/// spatial or navigational relationship (next conversation, list → detail,
/// neighbouring tab). Both sides travel along [axis] in the direction of
/// navigation; the new side starts fading in just before the old one is
/// gone, so the switch never shows an empty frame.
///
/// [direction] is 1 when moving towards the end of the axis (down, right)
/// and -1 when moving back.
AnimatedSwitcherTransitionBuilder sharedAxis({Axis axis = Axis.vertical, int direction = 1, double distance = 30}) =>
    (child, animation) => DualTransitionBuilder(
          animation: animation,
          forwardBuilder: (context, a, child) =>
              _AxisFade(animation: a, axis: axis, from: distance * direction, to: 0, incoming: true, child: child),
          reverseBuilder: (context, a, child) =>
              _AxisFade(animation: a, axis: axis, from: 0, to: -distance * direction, incoming: false, child: child),
          child: child,
        );

/// M3 fade-through for an [AnimatedSwitcher], for content without a spatial
/// relationship: the old content fades out quickly as the new one fades in,
/// settling from a slightly smaller scale.
Widget fadeThrough(Widget child, Animation<double> animation) => DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, a, child) =>
          _AxisFade(animation: a, axis: Axis.vertical, from: 0, to: 0, incoming: true, scaleFrom: 0.96, child: child),
      reverseBuilder: (context, a, child) =>
          _AxisFade(animation: a, axis: Axis.vertical, from: 0, to: 0, incoming: false, child: child),
      child: child,
    );

/// Duration for [sharedAxis] and [fadeThrough] switches.
const kSwitchDuration = Duration(milliseconds: 300);

class _AxisFade extends AnimatedWidget {
  const _AxisFade({
    required Animation<double> animation,
    required this.axis,
    required this.from,
    required this.to,
    required this.incoming,
    required this.child,
    this.scaleFrom = 1,
  }) : super(listenable: animation);

  final Axis axis;
  final double from;
  final double to;
  final bool incoming;
  final double scaleFrom;
  final Widget? child;

  // The two overlap briefly, so a switch never passes through an empty frame.
  static const _fadeIn = Interval(0.2, 0.9, curve: Curves.easeOut);
  static const _fadeOut = Interval(0, 0.35, curve: Curves.easeIn);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    final still = reduceMotion(context);
    final travel = incoming ? Easing.emphasizedDecelerate.transform(t) : Easing.emphasizedAccelerate.transform(t);
    final d = still ? 0.0 : from + (to - from) * travel;
    final opacity = incoming ? _fadeIn.transform(t) : 1 - _fadeOut.transform(t);
    final scale = still ? 1.0 : scaleFrom + (1 - scaleFrom) * travel;
    Widget result = child ?? const SizedBox.shrink();
    if (scale != 1) result = Transform.scale(scale: scale, child: result);
    if (d != 0) result = Transform.translate(offset: axis == Axis.vertical ? Offset(0, d) : Offset(d, 0), child: result);
    return Opacity(opacity: opacity, child: result);
  }
}

/// Plays a short entrance whenever [token] changes: the new content fades in
/// while travelling [offset] back into place. Used where the old content
/// cannot stay around to cross-fade (it owns a scroll position).
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.token, required this.child, this.offset = Offset.zero});

  final Object? token;

  /// Where the content starts, relative to its resting place.
  final Offset offset;
  final Widget child;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: kSwitchDuration, value: 1);
  Offset _from = Offset.zero;

  @override
  void didUpdateWidget(Entrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token != oldWidget.token && !reduceMotion(context)) {
      _from = widget.offset;
      _controller.forward(from: 0);
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
        builder: (context, child) {
          final t = _controller.value;
          if (t >= 1) return child!;
          final travel = Easing.emphasizedDecelerate.transform(t);
          return Opacity(
            opacity: const Interval(0, 0.7, curve: Curves.easeOut).transform(t),
            child: Transform.translate(offset: _from * (1 - travel), child: child),
          );
        },
        child: widget.child,
      );
}

/// Animates a row into and out of a list. An arriving row opens a gap and
/// then fades in; a leaving row fades first and then lets the gap close, so
/// the eye can follow where things went.
class Presence extends StatefulWidget {
  const Presence({super.key, required this.child, this.present = true, this.appear = false});

  final Widget child;

  /// False animates the row out. It stays non-interactive while leaving.
  final bool present;

  /// Animate in on first build: a row that just arrived.
  final bool appear;

  /// How long a leaving row needs before its owner can drop it.
  static Duration get exitDuration => Spring.standardSlow.duration;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController.unbounded(vsync: this, value: widget.appear ? 0 : 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.appear) _animateTo(widget.present ? 1 : 0);
  }

  @override
  void didUpdateWidget(Presence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.present != oldWidget.present) _animateTo(widget.present ? 1 : 0);
  }

  void _animateTo(double target) {
    if (reduceMotion(context)) {
      _controller.value = target;
    } else {
      _controller.animateWith(
          Spring.standardSlow.simulate(_controller.value, target, velocity: _controller.velocity));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !widget.present,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final v = unit(_controller.value);
            if (v >= 1) return child!;
            // Space first, content second on the way in; the reverse on the
            // way out.
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: v,
                child: Opacity(opacity: unit((v - 0.4) / 0.6), child: child),
              ),
            );
          },
          child: widget.child,
        ),
      );
}
