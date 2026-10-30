import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/app.dart';
import 'package:plume_store/plume_store.dart';

import 'demo_services.dart';

/// The whole app on the demo account, in a window of [size].
class DemoApp {
  DemoApp._(this.tester, this.ref, this.services);

  final WidgetTester tester;
  final WidgetRef ref;
  final Services services;

  static Future<DemoApp> start(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(demoServices))!;
    final container = ProviderContainer(overrides: [servicesProvider.overrideWithValue(services)]);
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, r, child) {
        ref = r;
        return child!;
      }, child: const PlumeApp()),
    ));
    addTearDown(() async {
      Toaster.instance.clear();
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 30));
      await tester.runAsync(services.engine.dispose);
      await tester.runAsync((services.store as DriftMailStore).close);
    });
    final app = DemoApp._(tester, ref, services);
    await app.settle();
    return app;
  }

  /// Lets database writes, streams and animations finish.
  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
