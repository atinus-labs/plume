import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/mail.dart';
import '../state/navigation.dart';
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
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
