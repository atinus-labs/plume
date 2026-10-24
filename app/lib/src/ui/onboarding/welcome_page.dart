import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/services.dart';
import '../common/logo.dart';
import '../shell/title_bar.dart';
import 'add_account.dart';

/// First run: no accounts yet.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surfaces = PlumeSurfaces.of(context);
    final desktop = ref.watch(desktopProvider);
    return Scaffold(
      backgroundColor: surfaces.window,
      body: Column(
        children: [
          if (desktop.drawsWindowControls) const WindowTitleBar(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Spring.spatialSlow.duration,
                  curve: Spring.spatialSlow.curve,
                  builder: (context, t, child) => Opacity(
                    opacity: unit(t),
                    child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Pane(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PlumeLogo(size: 104, animate: true),
                            const SizedBox(height: 28),
                            Text('Welcome to Plume', style: theme.textTheme.displaySmallEmphasized, textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            Text(
                              'A calm, fast home for your email.',
                              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            const AddAccountPanel(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
