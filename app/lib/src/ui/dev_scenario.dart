import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui; // TEMP-VERIFY

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // TEMP-VERIFY
import 'package:flutter/rendering.dart'; // TEMP-VERIFY
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/mail.dart';
import '../state/navigation.dart';
import '../state/services.dart'; // TEMP-VERIFY
import '../state/settings.dart'; // TEMP-VERIFY
import 'actions.dart';
import 'compose/compose_host.dart';

/// Debug-only: drives the UI into a named state on startup so screens can be
/// checked without synthetic input (`PLUME_DEV_SCENARIO=reader|compose|...`).
class DevScenario extends ConsumerStatefulWidget {
  const DevScenario({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DevScenario> createState() => _DevScenarioState();
}

class _DevScenarioState extends ConsumerState<DevScenario> {
  @override
  void initState() {
    super.initState();
    final scenario = kDebugMode ? Platform.environment['PLUME_DEV_SCENARIO'] : null;
    if (scenario != null) unawaited(_run(scenario));
  }

  Future<void> _run(String scenario) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final threads = ref.read(visibleThreadsProvider).value ?? const [];
    for (final step in scenario.split(',')) {
      switch (step) {
        case 'reader' when threads.isNotEmpty:
          openThread(ref, threads.first);
        case 'reader2' when threads.length > 1:
          openThread(ref, threads[1]);
        case 'select' when threads.length > 3:
          ref.read(selectionProvider.notifier).setAll([threads[1].key, threads[3].key]);
        case 'compose':
          ref.read(composeProvider.notifier).newMessage();
        case 'everything':
          ref.read(viewProvider.notifier).show(ref.read(viewProvider).withCategory(null));
        case 'light':
        case 'dark':
          break;
        case final s when s.startsWith('open:'): // TEMP-VERIFY
          final all = ref.read(visibleThreadsProvider).value ?? const [];
          final t = all.where((t) => t.subject.contains(s.substring(5))).firstOrNull;
          if (t != null) openThread(ref, t);
        case final s when s.startsWith('snap:'): // TEMP-VERIFY
          await WidgetsBinding.instance.endOfFrame;
          final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(s.substring(5)).writeAsBytesSync(data!.buffer.asUint8List());
        case 'demo': // TEMP-VERIFY
          await ref.read(accountsServiceProvider).add('demo');
          await Future<void>.delayed(const Duration(seconds: 3));
        case 'remote': // TEMP-VERIFY
          ref.read(settingsProvider.notifier).update((s) => s.copyWith(remoteImages: RemoteImages.always));
        case 'darkmode': // TEMP-VERIFY
          ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: ThemeMode.dark));
        case final s when s.startsWith('drag:'): // TEMP-VERIFY
          final v = s.substring(5).split(' ').map(double.parse).toList();
          final a = Offset(v[0], v[1]), b = Offset(v[2], v[3]);
          final g = GestureBinding.instance;
          final t0 = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch % 100000000);
          const mouse = PointerDeviceKind.mouse;
          g.handlePointerEvent(PointerAddedEvent(timeStamp: t0, position: a, kind: mouse, device: 7));
          g.handlePointerEvent(PointerHoverEvent(timeStamp: t0, position: a, kind: mouse, device: 7));
          g.handlePointerEvent(PointerDownEvent(timeStamp: t0 + const Duration(milliseconds: 20), pointer: 901, device: 7, position: a, kind: mouse, buttons: kPrimaryMouseButton));
          for (var i = 1; i <= 12; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 16));
            g.handlePointerEvent(PointerMoveEvent(timeStamp: t0 + Duration(milliseconds: 20 + 16 * i), pointer: 901, device: 7, position: Offset.lerp(a, b, i / 12)!, delta: (b - a) / 12, kind: mouse, buttons: kPrimaryMouseButton));
          }
          g.handlePointerEvent(PointerUpEvent(timeStamp: t0 + const Duration(milliseconds: 260), pointer: 901, device: 7, position: b, kind: mouse));
        case final s when s.startsWith('hover:'): // TEMP-VERIFY
          final v = s.substring(6).split(' ').map(double.parse).toList();
          GestureBinding.instance.handlePointerEvent(PointerHoverEvent(timeStamp: Duration(milliseconds: DateTime.now().millisecondsSinceEpoch % 100000000), position: Offset(v[0], v[1]), kind: PointerDeviceKind.mouse, device: 7));
          await Future<void>.delayed(const Duration(milliseconds: 900));
        case 'wait': // TEMP-VERIFY
          await Future<void>.delayed(const Duration(seconds: 2));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(key: _boundary, child: widget.child); // TEMP-VERIFY
  final _boundary = GlobalKey(); // TEMP-VERIFY
}
