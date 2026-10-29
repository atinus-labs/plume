// Frame-pacing probe for Linux. Not part of the app.
//
// Runs for 10 s (after 3 s of warm-up) and prints, as one JSON line on
// stdout, every frame Flutter produced. Run it with WAYLAND_DEBUG=client to
// also log what the compositor was actually given, then compare the two with
// pacing.py:
//
//   flutter build linux --profile -t tool/frame_probe/main.dart
//   PLUME_ALLOW_MULTIPLE_INSTANCES=1 WAYLAND_DEBUG=client \
//     build/linux/x64/profile/bundle/plume app > /tmp/p.out 2> /tmp/p.wl
//   python3 tool/frame_probe/pacing.py /tmp/p.out /tmp/p.wl
//
// Modes:
//   minimal  a single box sliding back and forth (no Plume code at all)
//   app      the real Plume UI on the in-memory demo account, stepping
//            through conversations (j, then k) every 150 ms
//   idle     the same UI left alone, which should draw nothing at all
//
// While it runs, timeline.dart can show where each thread's time goes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume/src/platform/linux/assistive_tech.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/app.dart';

import '../../test/support/demo_services.dart';

const _warmUp = Duration(seconds: 3);
const _measure = Duration(seconds: 10);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = args.isEmpty ? 'minimal' : args.first;

  if (mode == 'app' || mode == 'idle') {
    // The user's mail and settings are untouched.
    final services = await demoServices();
    unawaited(AssistiveTech.instance.watch());
    WidgetRef? ref;
    runApp(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: Consumer(builder: (context, r, child) {
        ref = r;
        return child!;
      }, child: const PlumeApp()),
    ));
    if (mode == 'app') unawaited(_stepThrough(() => ref!));
  } else {
    runApp(const _Minimal());
  }

  await Future<void>.delayed(_warmUp);
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  final startWall = DateTime.now().microsecondsSinceEpoch;
  SchedulerBinding.instance.addTimingsCallback(collect);
  await Future<void>.delayed(_measure);
  // Let the last batch of timings arrive.
  SchedulerBinding.instance.scheduleFrame();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  SchedulerBinding.instance.removeTimingsCallback(collect);
  final endWall = DateTime.now().microsecondsSinceEpoch;

  stdout.writeln('PROBE ${jsonEncode({
    'mode': mode,
    'startWallUs': startWall,
    'endWallUs': endWall,
    'refreshRate': PlatformDispatcher.instance.views.first.display.refreshRate,
    'frames': [
      for (final t in timings)
        [
          t.timestampInMicroseconds(FramePhase.vsyncStart),
          t.timestampInMicroseconds(FramePhase.buildStart),
          t.timestampInMicroseconds(FramePhase.buildFinish),
          t.timestampInMicroseconds(FramePhase.rasterStart),
          t.timestampInMicroseconds(FramePhase.rasterFinish),
        ],
    ],
  })}');
  await stdout.flush();
  exit(0);
}

class _Minimal extends StatefulWidget {
  const _Minimal();

  @override
  State<_Minimal> createState() => _MinimalState();
}

class _MinimalState extends State<_Minimal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.white,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Align(
            alignment: Alignment(_c.value * 2 - 1, 0),
            child: const SizedBox.square(dimension: 120, child: ColoredBox(color: Colors.black)),
          ),
        ),
      );
}

/// Steps through conversations like someone pressing j eight times, then k
/// eight times, over and over: the reader cross-fades to each conversation
/// (laying out and drawing its mail) while the list's selection springs
/// after it, so something is always moving.
Future<void> _stepThrough(WidgetRef Function() ref) async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  for (var i = 0;; i++) {
    stepThread(ref(), i % 16 < 8 ? 1 : -1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}
