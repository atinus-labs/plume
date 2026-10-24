import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_design/plume_design.dart';

import '../config.dart';
import '../services/desktop.dart';
import '../state/mail.dart';
import '../state/services.dart';
import '../state/settings.dart';
import 'actions.dart';
import 'common/logo.dart';
import 'desktop_bridge.dart';
import 'dev_scenario.dart';
import 'onboarding/welcome_page.dart';
import 'shell/home_shell.dart';

/// Desktop appearance (accent colour, dark preference), live.
final appearanceProvider = StreamProvider<SystemAppearance>((ref) async* {
  final desktop = ref.watch(desktopProvider);
  yield desktop.appearance;
  yield* desktop.appearanceChanges;
});

class PlumeApp extends ConsumerWidget {
  const PlumeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final appearance = ref.watch(appearanceProvider).value ?? const SystemAppearance();
    final seed = settings.colorSource == ColorSource.custom
        ? Color(settings.customSeed)
        : (appearance.accent ?? PlumeTheme.defaultSeed);
    final contrast = appearance.highContrast ? 0.5 : 0.0;
    final mode = switch (settings.themeMode) {
      ThemeMode.system => switch (appearance.brightness) {
          Brightness.dark => ThemeMode.dark,
          Brightness.light => ThemeMode.light,
          null => ThemeMode.system,
        },
      final m => m,
    };

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: PlumeTheme.build(brightness: Brightness.light, seed: seed, contrast: contrast),
      darkTheme: PlumeTheme.build(brightness: Brightness.dark, seed: seed, contrast: contrast),
      themeMode: mode,
      themeAnimationDuration: Spring.effectsSlow.duration,
      themeAnimationCurve: Spring.effectsSlow.curve,
      home: const DesktopBridge(child: DevScenario(child: _RootGate())),
    );
  }
}

/// Welcome screen until the first account exists, then the mail shell.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final child = accounts.when(
      loading: () => const _Splash(key: ValueKey('splash')),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty ? const WelcomePage(key: ValueKey('welcome')) : const HomeShell(key: ValueKey('home')),
    );
    return AnimatedSwitcher(
      duration: Spring.standard.duration,
      switchInCurve: Spring.standard.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(animation), child: child),
      ),
      child: child,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PlumeSurfaces.of(context).window,
        child: const Center(child: PlumeLogo(size: 72, animate: true)),
      );
}
