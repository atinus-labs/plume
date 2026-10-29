import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/bootstrap.dart';
import 'src/platform/linux/assistive_tech.dart';
import 'src/state/services.dart';
import 'src/ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _debugErrorLog();
  final services = await bootstrap(args);
  unawaited(AssistiveTech.instance.watch());
  runApp(ProviderScope(
    overrides: [servicesProvider.overrideWithValue(services)],
    child: const PlumeApp(),
  ));
}

/// Debug builds: mirror framework errors into `$PLUME_DEV_LOG` synchronously,
/// so they are visible even when stdout is not a terminal.
void _debugErrorLog() {
  final path = Platform.environment['PLUME_DEV_LOG'];
  if (!kDebugMode || path == null) return;
  final file = File(path);
  FlutterError.onError = (details) {
    file.writeAsStringSync('${details.toString()}\n\n', mode: FileMode.append);
    FlutterError.presentError(details);
  };
}
