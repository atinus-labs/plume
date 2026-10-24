import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../config.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../common/logo.dart';
import 'nav_rail.dart';

/// The app-drawn title bar for floating window managers (GNOME, KDE, ...).
/// Tiling compositors get no title bar at all.
class WindowTitleBar extends ConsumerWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = ref.watch(desktopProvider);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => unawaited(desktop.startWindowMove()),
              onDoubleTap: () => unawaited(desktop.toggleMaximize()),
              child: SizedBox.expand(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
            ),
          ),
          _WindowButton(icon: Symbols.remove_rounded, tooltip: 'Minimise', onPressed: desktop.minimize, color: scheme.onSurfaceVariant),
          _WindowButton(icon: Symbols.crop_square_rounded, tooltip: 'Maximise', onPressed: desktop.toggleMaximize, color: scheme.onSurfaceVariant),
          _WindowButton(
            icon: Symbols.close_rounded,
            tooltip: 'Close',
            color: scheme.onSurfaceVariant,
            onPressed: () async {
              final background = ref.read(settingsProvider).runInBackground && desktop.hasTray;
              await (background ? desktop.hideWindow() : desktop.quit());
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, required this.tooltip, required this.onPressed, required this.color});

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          tooltip: tooltip,
          iconSize: 18,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(32, 32)),
            fixedSize: WidgetStatePropertyAll(Size(32, 32)),
          ),
          padding: EdgeInsets.zero,
          onPressed: () => unawaited(onPressed()),
          icon: Icon(icon, color: color, weight: 500),
        ),
      );
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
