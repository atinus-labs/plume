import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_design/plume_design.dart';

import '../../config.dart';
import '../../services/window_frame.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../common/logo.dart';
import 'nav_rail.dart';

/// Plume's title bar, when it stands in for the desktop's
/// ([TitleBar.plume]): the app's name, window buttons where the desktop puts
/// them, and room to move the window. Drag it to move the window,
/// double-click it to maximise, right-click it for the window menu.
class WindowTitleBar extends ConsumerWidget {
  const WindowTitleBar({super.key});

  static const _height = 40.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = ref.watch(desktopProvider);
    final frame = desktop.windowFrame;
    if (frame == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    Future<void> close() async {
      final background = ref.read(settingsProvider).runInBackground && desktop.hasTray;
      await (background ? desktop.hideWindow() : desktop.quit());
    }

    return SizedBox(
      height: _height,
      child: ListenableBuilder(
        listenable: frame,
        builder: (context, _) {
          final leading = frame.leading;
          final trailing = frame.trailing;
          // Window buttons sit as far from the side as from the top.
          const edge = (_height - _WindowButtonState.size) / 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => unawaited(frame.startMove()),
                onDoubleTap: () => unawaited(frame.toggleMaximize()),
                onSecondaryTapDown: (_) => unawaited(frame.showMenu()),
              ),
              Padding(
                padding: EdgeInsets.only(left: leading.isEmpty ? 16 : edge, right: trailing.isEmpty ? 16 : edge),
                child: Row(
                  children: [
                    if (leading.isNotEmpty) ...[
                      _WindowButtons(frame: frame, buttons: leading, onClose: close),
                      const SizedBox(width: 16),
                    ],
                    // Clicks on the name fall through to the drag area behind.
                    Expanded(
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            const ExcludeSemantics(child: PlumeLogo(size: 28)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                AppConfig.appName,
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (trailing.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      _WindowButtons(frame: frame, buttons: trailing, onClose: close),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Minimise, maximise and close, in the desktop's order.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.frame, required this.buttons, required this.onClose});

  final WindowFrame frame;
  final List<WindowButton> buttons;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, button) in buttons.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            switch (button) {
              WindowButton.minimize => _WindowButton(
                  icon: Symbols.remove_rounded,
                  label: 'Minimise',
                  onPressed: frame.minimize,
                ),
              WindowButton.maximize => _WindowButton(
                  icon: frame.maximized ? Symbols.filter_none_rounded : Symbols.crop_square_rounded,
                  iconSize: frame.maximized ? 13 : 15,
                  label: frame.maximized ? 'Restore' : 'Maximise',
                  onPressed: frame.toggleMaximize,
                ),
              WindowButton.close => _WindowButton(
                  icon: Symbols.close_rounded,
                  label: 'Close',
                  onPressed: onClose,
                  close: true,
                ),
            },
          ],
        ],
      );
}

/// A window button: a soft tonal circle that squares off and shrinks a little
/// while pressed, then springs back.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 16,
    this.close = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;
  final double iconSize;

  /// Turns red on hover.
  final bool close;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> with SingleTickerProviderStateMixin {
  static const size = 28.0;

  late final _press = AnimationController.unbounded(vsync: this);
  bool _hover = false;

  void _springTo(double target) {
    if (reduceMotion(context)) {
      _press.value = target;
    } else {
      unawaited(_press.animateWith(Spring.spatialFast.simulate(_press.value, target, velocity: _press.velocity)));
    }
  }

  void _activate() => unawaited(widget.onPressed());

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rest = (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    final hover = widget.close ? (scheme.error, scheme.onError) : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    return Semantics(
      button: true,
      label: widget.label,
      onTap: _activate,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          // Squishes from the moment the button goes down: a tap only
          // registers once it's up again, so a quick click would never show.
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kPrimaryButton) _springTo(1);
            },
            onPointerUp: (_) => _springTo(0),
            onPointerCancel: (_) => _springTo(0),
            child: GestureDetector(
              onTap: _activate,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _hover ? 1 : 0),
                duration: Spring.effectsFast.duration,
                curve: Spring.effectsFast.curve,
                builder: (context, h, _) => AnimatedBuilder(
                  animation: _press,
                  builder: (context, _) {
                    // Pressing squares the circle off and shrinks it a little.
                    final t = _press.value;
                    return Transform.scale(
                      scale: 1 - 0.1 * t,
                      child: SizedBox.square(
                        dimension: size,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: Color.lerp(rest.$1, hover.$1, h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(size / 2 - 6 * t.clamp(0, 1.2)),
                            ),
                          ),
                          child: Icon(widget.icon, size: widget.iconSize, color: Color.lerp(rest.$2, hover.$2, h)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rail on wide layouts.
class NavRailHost extends ConsumerWidget {
  const NavRailHost({super.key, required this.expanded, required this.onOpenSettings});

  final bool expanded;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => NavRail(expanded: expanded, onOpenSettings: onOpenSettings);
}

/// Rail content inside the compact-window drawer.
class NavRailDrawer extends StatelessWidget {
  const NavRailDrawer({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => NavRail(expanded: true, inDrawer: true, onOpenSettings: onOpenSettings);
}
