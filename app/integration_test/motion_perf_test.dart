// Measures frame times of the real app in profile mode while it is driven
// through its main motions, using the in-memory demo account:
//
//   PLUME_ALLOW_MULTIPLE_INSTANCES=1 flutter drive --profile -d linux \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/motion_perf_test.dart
//
// A window opens for about a minute. The driver prints a table and writes
// build/perf/motion_perf.json.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/navigation.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/app.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/reader/reader_pane.dart';
import 'package:plume/src/ui/threads/thread_list_pane.dart';
import 'package:plume_core/plume_core.dart';

import '../test/support/demo_services.dart';

/// `--dart-define=PLUME_PERF_TRACE=true` records which widgets build while
/// stepping through threads, instead of timing them.
const _trace = bool.fromEnvironment('PLUME_PERF_TRACE');
const _traceWidgets = bool.fromEnvironment('PLUME_PERF_TRACE_WIDGETS');
const _traceLayouts = bool.fromEnvironment('PLUME_PERF_TRACE_LAYOUTS');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('motion stays within the frame budget', (tester) async {
    final services = await demoServices();
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: Consumer(builder: (context, r, child) {
        ref = r;
        return child!;
      }, child: const PlumeApp()),
    ));
    await wait(1500);

    // The Linux key map has no entry for some keys, so name the physical key.
    final physical = {
      LogicalKeyboardKey.enter: PhysicalKeyboardKey.enter,
      LogicalKeyboardKey.escape: PhysicalKeyboardKey.escape,
      LogicalKeyboardKey.keyE: PhysicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyI: PhysicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyJ: PhysicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK: PhysicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyR: PhysicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyU: PhysicalKeyboardKey.keyU,
    };
    Future<void> key(LogicalKeyboardKey key, {String? character, int pause = 350}) async {
      // When the window loses focus (another window was clicked), Flutter
      // parks keyboard focus until it comes back; act as if it had.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.sendKeyDownEvent(key, character: character, physicalKey: physical[key]);
      await tester.sendKeyUpEvent(key, physicalKey: physical[key]);
      await wait(pause);
    }

    Future<void> fling(Finder scrollable, double dy) async {
      await tester.fling(scrollable, Offset(0, dy), 2500);
      await wait(900);
    }

    final list = find.descendant(of: find.byType(ThreadListPane), matching: find.byType(Scrollable)).first;
    Finder reader() => find.descendant(of: find.byType(ReaderPane), matching: find.byType(Scrollable)).first;

    // Opening marks each conversation read, so the unread weight animates too.
    Future<void> stepThrough() async {
      await key(LogicalKeyboardKey.enter);
      for (var i = 0; i < 8; i++) {
        await key(LogicalKeyboardKey.keyJ, character: 'j', pause: 260);
      }
      for (var i = 0; i < 4; i++) {
        await key(LogicalKeyboardKey.keyK, character: 'k', pause: 260);
      }
      await wait(600);
    }

    if (_trace) {
      // Each frame's phases and any garbage collection. With
      // PLUME_PERF_TRACE_WIDGETS or _LAYOUTS also every widget build or
      // render object layout, which slows frames and can overflow the
      // timeline.
      debugProfileBuildsEnabled = _traceWidgets;
      debugProfileLayoutsEnabled = _traceLayouts;
      await binding.traceAction(stepThrough, reportKey: 'step through threads (timeline)', streams: const ['Dart', 'GC']);
      debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
    } else {
      await binding.watchPerformance(reportKey: 'step through threads', stepThrough);
    }

    await binding.watchPerformance(reportKey: 'read / unread', () async {
      for (var i = 0; i < 3; i++) {
        await key(LogicalKeyboardKey.keyU, character: 'U', pause: 500);
        await key(LogicalKeyboardKey.keyI, character: 'I', pause: 500);
      }
    });

    await binding.watchPerformance(reportKey: 'archive', () async {
      for (var i = 0; i < 3; i++) {
        await key(LogicalKeyboardKey.keyE, character: 'e', pause: 700);
      }
      await wait(600);
    });

    final offsite = ref.read(visibleThreadsProvider).value!.firstWhere((t) => t.subject.contains('offsite'));
    openThread(ref, offsite);
    await wait(800);
    await binding.watchPerformance(reportKey: 'long thread', () async {
      await tester.tap(find.textContaining('older messages'), kind: PointerDeviceKind.mouse);
      await wait(700);
      await fling(reader(), -1200);
      await fling(reader(), 1200);
    });

    await binding.watchPerformance(reportKey: 'reply and close', () async {
      for (var i = 0; i < 3; i++) {
        await key(LogicalKeyboardKey.keyR, character: 'r', pause: 900);
        ref.read(composeProvider.notifier).close(ref.read(composeProvider).last.id);
        await wait(700);
      }
    });

    // The list is on screen at every window size once the reader is closed.
    await key(LogicalKeyboardKey.escape, pause: 800);
    await binding.watchPerformance(reportKey: 'scroll list', () async {
      await fling(list, -900);
      await fling(list, 900);
      await fling(list, -600);
      await fling(list, 600);
    });

    await binding.watchPerformance(reportKey: 'switch views', () async {
      for (final category in const [MailCategory.promotions, MailCategory.social, MailCategory.updates, MailCategory.primary]) {
        ref.read(viewProvider.notifier).show(MailView(ViewKind.inbox, category: category));
        await wait(600);
      }
    });

    // Stillness: once idle, nothing may be animating. The live test binding
    // draws frames continuously by itself, so frame counts say nothing here;
    // running animations do.
    await wait(1500);
    var animating = 0;
    for (var i = 0; i < 30; i++) {
      animating = math.max(animating, SchedulerBinding.instance.transientCallbackCount);
      await wait(100);
    }
    // In debug runs, name whatever is still animating.
    assert(SchedulerBinding.instance.debugAssertNoTransientCallbacks('Still animating while idle'));

    final view = tester.view;
    final display = view.display;
    binding.reportData = {
      ...?binding.reportData,
      'window': {
        'width': view.physicalSize.width / view.devicePixelRatio,
        'height': view.physicalSize.height / view.devicePixelRatio,
        'device_pixel_ratio': view.devicePixelRatio,
        'refresh_rate': display.refreshRate,
      },
      'idle': {'running_animations': animating},
    };

    await tester.pumpWidget(const SizedBox());
    await services.engine.dispose();
  });
}

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
