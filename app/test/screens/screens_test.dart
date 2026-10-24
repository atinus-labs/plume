// Renders the real app offscreen to PNGs for visual review.
//
//   PLUME_SCREENS=1 flutter test test/screens/screens_test.dart
//
// Images land in build/screens/. Skipped unless PLUME_SCREENS is set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/demo/demo_provider.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/imap_connector.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/navigation.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/app.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/onboarding/add_account.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

final _enabled = Platform.environment['PLUME_SCREENS'] == '1';

String _packageRoot(String name) {
  final config = jsonDecode(File('.dart_tool/package_config.json').existsSync()
      ? File('.dart_tool/package_config.json').readAsStringSync()
      : File('../.dart_tool/package_config.json').readAsStringSync()) as Map<String, Object?>;
  final pkg = (config['packages']! as List).cast<Map<String, Object?>>().firstWhere((p) => p['name'] == name);
  final root = pkg['rootUri']! as String;
  if (root.startsWith('file://')) return Uri.parse(root).toFilePath();
  return File('../.dart_tool/$root').absolute.path;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('packages/plume_design/Google Sans Flex', '${_packageRoot('plume_design')}/fonts/GoogleSansFlex.ttf');
  await load('packages/material_symbols_icons/MaterialSymbolsRounded',
      '${_packageRoot('material_symbols_icons')}/lib/fonts/MaterialSymbolsRounded.ttf');
}

class _NoSecrets implements SecretStore {
  @override
  String get backend => 'test';
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

Future<Services> _services() async {
  final store = DriftMailStore.inMemory();
  final accounts = AccountsService(store: store, connectors: [DemoConnector(), ImapConnector(_NoSecrets())]);
  final engine = MailEngine(store: store, factories: accounts.factories, tokenSourceFor: accounts.tokenSourceFor);
  accounts.engine = engine;
  await engine.start();
  await accounts.add('demo');
  // Let the initial sync land.
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if ((engine.currentStatuses.values.firstOrNull?.initialSyncDone ?? false)) break;
  }
  return Services(
    store: store,
    engine: engine,
    desktop: HeadlessDesktop(),
    secrets: _NoSecrets(),
    accounts: accounts,
    initialSettings: const AppSettings(),
  );
}

typedef Step = Future<void> Function(WidgetTester tester, WidgetRef c);

Future<void> _openAddAccount(WidgetTester t, WidgetRef c) async =>
    unawaited(showAddAccountDialog(t.element(find.byType(Scaffold).first)));

Future<void> _openServerForm(WidgetTester t, WidgetRef c) async {
  await _openAddAccount(t, c);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.text('Other mail'));
}

// Built-in providers only: the form must not look servers up on the network.
Step _type(String field, String text) => (t, c) => t.enterText(find.widgetWithText(TextField, field), text);

final _scenarios = <String, List<Step>>{
  'inbox': [],
  'reader': [
    (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
  ],
  'reader_newsletter': [
    (t, c) async => c.read(viewProvider.notifier).show(const MailView(ViewKind.inbox, category: MailCategory.promotions)),
    (t, c) async {
      final list = c.read(visibleThreadsProvider).value!;
      openThread(c, list.firstWhere((x) => x.subject.contains('Five essays'), orElse: () => list.first));
    },
  ],
  'selection': [
    (t, c) async {
      final list = c.read(visibleThreadsProvider).value!;
      c.read(selectionProvider.notifier).setAll([list[1].key, list[2].key]);
    },
  ],
  'compose': [
    (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
    (t, c) async => c.read(composeProvider.notifier).newMessage(),
  ],
  'add_account': [_openAddAccount],
  'server_form_gmail': [
    _openServerForm,
    _type('Your name', 'Ren'),
    _type('Email address', 'ren@gmail.com'),
    _type('App password', 'abcdefghijklmnop'),
  ],
  'server_form_settings': [
    _openServerForm,
    _type('Your name', 'Ren'),
    _type('Email address', 'ren@fastmail.com'),
    (t, c) async => t.tap(find.text('Server settings')),
  ],
  'collapsed_rail': [
    (t, c) async => c.read(settingsProvider.notifier).update((s) => s.copyWith(railExpanded: false)),
    (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!)[1]),
  ],
};

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final entry in _scenarios.entries) {
      testWidgets('${entry.key} ${brightness.name}', skip: !_enabled, (tester) async {
        await tester.runAsync(_loadFonts);
        // flutter_test draws shadows as solid outlines by default.
        debugDisableShadows = false;
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);

        final services = (await tester.runAsync(_services))!;
        final boundary = GlobalKey();
        final container = ProviderContainer(overrides: [servicesProvider.overrideWithValue(services)]);
        late WidgetRef ref;
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: Consumer(builder: (context, r, child) {
              ref = r;
              return child!;
            }, child: const PlumeApp()),
          ),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        for (final step in entry.value) {
          await step(tester, ref);
          await settle();
        }
        await settle();

        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        });
        final out = File('build/screens/${entry.key}_${brightness.name}.png');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(png!);

        await tester.pumpWidget(const SizedBox());
        container.dispose();
        // Let debounce/retry timers started by the UI run out.
        await tester.pump(const Duration(seconds: 30));
        debugDisableShadows = true;
        await tester.runAsync(() => services.engine.dispose());
        await tester.runAsync(() => (services.store as DriftMailStore).close());
      });
    }
  }
}
