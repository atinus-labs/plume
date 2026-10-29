// Renders the real app offscreen to PNGs for visual review.
//
//   PLUME_SCREENS=1 flutter test test/screens/screens_test.dart
//
// Every scenario is drawn at each window size in light and dark, into
// build/screens/<size>/. Motion scenarios stop the clock partway through an
// animation and write one filmstrip per motion to build/screens/motion/.
// PLUME_SCREEN_SIZES=phone,half limits the sizes. A layout overflow fails the
// test. Skipped unless PLUME_SCREENS is set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/services/window_frame.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/navigation.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/app.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/compose/rich_text.dart';
import 'package:plume/src/ui/onboarding/add_account.dart';
import 'package:plume/src/ui/reader/reader_pane.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

import '../support/demo_services.dart';

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
  'welcome': [],
  'inbox': [],
  'settings_branding': [
    (t, c) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.comma);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
    (t, c) async => t.scrollUntilVisible(
      find.text('Version 0.1.0 · org.atinus.plume'),
      500,
      scrollable: find.byType(Scrollable).first,
    ),
  ],
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
  'long_thread': [
    (t, c) async {
      final list = c.read(visibleThreadsProvider).value!;
      openThread(c, list.firstWhere((x) => x.subject.contains('offsite')));
    },
  ],
  'long_thread_scrolled': [
    (t, c) async {
      final list = c.read(visibleThreadsProvider).value!;
      openThread(c, list.firstWhere((x) => x.subject.contains('offsite')));
    },
    (t, c) async => t.tap(find.textContaining('older messages')),
    (t, c) async => t.tap(find.textContaining('Found a converted farmhouse')),
    (t, c) async => t.tap(find.textContaining('That looks perfect')),
    (t, c) async => t.drag(
          find.descendant(of: find.byType(ReaderPane), matching: find.byType(Scrollable)).first,
          const Offset(0, -400),
        ),
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
  'showcase': [
    (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
    (t, c) async {
      c.read(composeProvider.notifier).reopen(OutgoingMessage(
        accountId: 'demo',
        from: const Address('alex.rivera@example.com', 'Alex Rivera'),
        to: const [Address('arjun@northwind.dev', 'Arjun Mehta')],
        subject: 'Re: Q4 infrastructure budget',
        textBody: "Thanks Arjun. The reserved instances breakdown looks solid. Let's move the batch jobs to spot next.",
        htmlBody: "<div>Thanks Arjun. The reserved instances breakdown looks solid. Let's move the batch jobs to spot next.</div>",
        attachments: [
          OutgoingAttachment(
            filename: 'Q4-forecast.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            bytes: Uint8List(48213),
          ),
        ],
      ));
    },
  ],
  'compose_formatting': [
    (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
    (t, c) async {
      c.read(composeProvider.notifier).reopen(OutgoingMessage(
        accountId: 'demo',
        from: const Address('alex.rivera@example.com', 'Alex Rivera'),
        to: const [Address('arjun@northwind.dev', 'Arjun Mehta')],
        subject: 'Launch checklist',
        textBody: '',
        htmlBody: '<div>Hi Arjun,</div><div><br></div>'
            '<div>Here is the plan for <b>Thursday</b>, see the <a href="https://example.com/doc">doc</a>:</div>'
            '<ol><li>Freeze the <i>release</i> branch</li><li><u>Run</u> the full suite</li></ol>'
            '<ul><li>Ping support</li></ul><div><s>Old step</s> Done.</div>',
      ));
    },
    // Select "Hi Arjun" and make it bold from the keyboard.
    (t, c) async {
      final body = find.byWidgetPredicate((w) => w is TextField && w.controller is RichTextController);
      await t.tap(body);
      final controller = (t.widget<TextField>(body).controller)!;
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Clicking a toolbar button keeps the selection in the body.
      await t.tap(find.byTooltip('Italic (Ctrl+I)'), kind: PointerDeviceKind.mouse);
      await t.pump();
      expect((controller as RichTextController).toHtml(), startsWith('<div><b><i>Hi Arjun</i></b>,</div>'));
    },
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
  'title_bar': [],
  'title_bar_left': [],
  'title_bar_settings': [
    (t, c) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.comma);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
    (t, c) async => t.scrollUntilVisible(find.text('Title bar'), 300, scrollable: find.byType(Scrollable).first),
    (t, c) async => Scrollable.ensureVisible(t.element(find.text('Title bar')), alignment: 0.5),
  ],
};

/// Scenarios drawn as on a floating desktop: Plume's title bar, with the
/// window buttons where GTK's decoration layout puts them.
final _frames = <String, WindowFrame Function()>{
  'title_bar': DemoWindowFrame.new,
  'title_bar_left': () => DemoWindowFrame(layout: 'close,minimize,maximize:'),
  'title_bar_settings': DemoWindowFrame.new,
  'window_button_press': DemoWindowFrame.new,
  'window_button_release': DemoWindowFrame.new,
};

/// The mouse holding a window button down, between motion steps.
TestGesture? _windowButton;

/// Moves the mouse onto Close and holds the button down.
Future<void> _pressClose(WidgetTester t) async {
  final at = t.getCenter(find.byTooltip('Close'));
  final mouse = _windowButton = await t.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.moveTo(at);
  await mouse.down(at);
}

const _sizes = {
  'desktop': Size(1600, 1000),
  // Half of a tiled 1920px screen: list and a narrow reader side by side.
  'tiled': Size(960, 1000),
  // Half of a tiled 1600px screen: one pane at a time beside the rail.
  'half': Size(800, 1000),
  'phone': Size(412, 900),
};

bool _sizeEnabled(String size) {
  final only = Platform.environment['PLUME_SCREEN_SIZES'];
  return only == null || only.split(',').contains(size);
}

/// An animation stopped partway: [setup] runs and settles, then [action]
/// runs with the clock held, and a frame is taken [at] each number of
/// milliseconds after it, plus one once everything has settled.
class _Motion {
  const _Motion({
    this.setup = const [],
    required this.action,
    this.at = const [40, 90, 150, 240],
    this.sizes = const {'desktop'},
    this.crop,
  });

  final List<Step> setup;
  final Step action;
  final List<int> at;
  final Set<String> sizes;

  /// The part of the window worth looking at, for a window of the given size.
  final Rect Function(Size window)? crop;
}

Rect _listArea(Size w) => const Rect.fromLTWH(270, 180, 430, 560);
Rect _readerArea(Size w) => Rect.fromLTWH(w.width - 900, 0, 900, 700);
Rect _composeArea(Size w) => Rect.fromLTWH(w.width - 820, w.height - 700, 820, 700);
Rect _titleBarArea(Size w) => Rect.fromLTWH(w.width - 240, 0, 240, 48);

ThreadSummary _thread(WidgetRef c, String subject) =>
    c.read(visibleThreadsProvider).value!.firstWhere((x) => x.subject.contains(subject));

final _motions = <String, _Motion>{
  // A window button turns red under the mouse and squares off as it goes
  // down...
  'window_button_press': _Motion(
    action: (t, c) async => _pressClose(t),
    at: const [16, 40, 70, 120],
    crop: _titleBarArea,
  ),
  // ...then springs back as it comes up.
  'window_button_release': _Motion(
    setup: [(t, c) async => _pressClose(t)],
    action: (t, c) async => _windowButton!.up(),
    at: const [16, 40, 70, 120, 200],
    crop: _titleBarArea,
  ),
  // J: the next conversation comes up from below.
  'open_next': _Motion(
    setup: [(t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first)],
    action: (t, c) async => stepThread(c, 1),
    crop: _readerArea,
  ),
  // The archived row closes up; the rows below rise into its place.
  'archive': _Motion(
    action: (t, c) async => applyThreadAction(c, MailAction.archive, [keyOf(c.read(visibleThreadsProvider).value![1])]),
    at: const [60, 140, 240, 360],
    crop: _listArea,
  ),
  'view_switch': _Motion(
    action: (t, c) async =>
        c.read(viewProvider.notifier).show(const MailView(ViewKind.inbox, category: MailCategory.promotions)),
    crop: _listArea,
  ),
  'unfold': _Motion(
    setup: [(t, c) async => openThread(c, _thread(c, 'offsite'))],
    action: (t, c) async => t.tap(find.textContaining('older messages')),
    at: const [60, 140, 240, 360],
    crop: _readerArea,
  ),
  'compose_open': _Motion(
    setup: [(t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first)],
    action: (t, c) async => c.read(composeProvider.notifier).newMessage(),
    crop: _composeArea,
  ),
  'compose_close': _Motion(
    setup: [
      (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
      (t, c) async => c.read(composeProvider.notifier).newMessage(),
    ],
    action: (t, c) async => c.read(composeProvider.notifier).close(c.read(composeProvider).last.id),
    at: const [40, 90, 150, 210],
    crop: _composeArea,
  ),
  'open_phone': _Motion(
    action: (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
    sizes: const {'phone'},
  ),
  // The reply toolbar stretches into the reply window.
  'reply': _Motion(
    setup: [(t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first)],
    action: (t, c) async => t.tap(find.widgetWithText(TextButton, 'Reply'), kind: PointerDeviceKind.mouse),
    at: const [40, 100, 170, 260],
    crop: _composeArea,
  ),
  // A reply closed without sending shrinks back into the toolbar.
  'reply_close': _Motion(
    setup: [
      (t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first),
      (t, c) async => t.tap(find.widgetWithText(TextButton, 'Reply'), kind: PointerDeviceKind.mouse),
    ],
    action: (t, c) async => c.read(composeProvider.notifier).close(c.read(composeProvider).last.id),
    at: const [40, 100, 170, 260],
    crop: _composeArea,
  ),
  // The compose button grows into a full-window message.
  'compose_phone': _Motion(
    action: (t, c) async => t.tap(find.byTooltip('Compose (C)'), kind: PointerDeviceKind.mouse),
    at: const [40, 100, 170, 260],
    sizes: const {'phone'},
  ),
  // E presses the archive button, the row closes up and the next
  // conversation comes in under a toolbar that stays put.
  'archive_key': _Motion(
    setup: [(t, c) async => openThread(c, (c.read(visibleThreadsProvider).value!).first)],
    action: (t, c) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyE, character: 'e');
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyE);
    },
    at: const [40, 100, 170, 260],
    crop: (w) => const Rect.fromLTWH(270, 0, 820, 460),
  ),
};

class _Harness {
  _Harness._(this.tester, this.ref, this.boundary, this.container, this.services);

  final WidgetTester tester;
  final WidgetRef ref;
  final GlobalKey boundary;
  final ProviderContainer container;
  final Services services;

  static Future<_Harness> start(WidgetTester tester, String scenario, Size size, Brightness brightness) async {
    await tester.runAsync(_loadFonts);
    // flutter_test draws shadows as solid outlines by default.
    debugDisableShadows = false;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);

    final services = (await tester.runAsync(() => demoServices(frame: _frames[scenario]?.call())))!;
    final boundary = GlobalKey();
    final container = ProviderContainer(overrides: [
      servicesProvider.overrideWithValue(services),
      if (scenario == 'welcome') accountsProvider.overrideWith((ref) => Stream.value(const [])),
    ]);
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundary,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: brightness == Brightness.dark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
              width: 1,
            ),
          ),
          position: DecorationPosition.foreground,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Consumer(builder: (context, r, child) {
              ref = r;
              return child!;
            }, child: const PlumeApp()),
          ),
        ),
      ),
    ));
    final harness = _Harness._(tester, ref, boundary, container, services);
    await harness.settle();
    return harness;
  }

  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets database writes and streams land without moving the clock, so any
  /// animation they start is still at its first frame.
  Future<void> propagate() async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(Duration.zero);
    }
  }

  Future<ui.Image> capture() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() => render.toImage(pixelRatio: 1)))!;
  }

  Future<void> finish() async {
    Toaster.instance.clear();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Let debounce/retry timers started by the UI run out.
    await tester.pump(const Duration(seconds: 30));
    debugDisableShadows = true;
    await tester.runAsync(() => services.engine.dispose());
    await tester.runAsync(() => (services.store as DriftMailStore).close());
  }
}

Future<void> _writePng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final out = File(path);
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(data!.buffer.asUint8List());
}

/// Frames side by side, each labelled with its time.
Future<ui.Image> _filmstrip(List<(String, ui.Image)> frames, Rect crop, Brightness brightness) {
  const gap = 16.0;
  const label = 32.0;
  final dark = brightness == Brightness.dark;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final width = frames.length * crop.width + (frames.length + 1) * gap;
  final height = crop.height + label + 2 * gap;
  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
  for (final (i, (name, image)) in frames.indexed) {
    final x = gap + i * (crop.width + gap);
    final dst = Rect.fromLTWH(x, gap, crop.width, crop.height);
    canvas.drawImageRect(image, crop, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawRect(dst, Paint()
      ..style = PaintingStyle.stroke
      ..color = dark ? const Color(0x55FFFFFF) : const Color(0x33000000));
    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'packages/plume_design/Google Sans Flex', fontSize: 18))
          ..pushStyle(ui.TextStyle(color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)))
          ..addText(name))
        .build()
      ..layout(ui.ParagraphConstraints(width: crop.width));
    canvas.drawParagraph(paragraph, Offset(x, gap + crop.height + 6));
  }
  return recorder.endRecording().toImage(width.ceil(), height.ceil());
}

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
      for (final entry in _scenarios.entries) {
        testWidgets('$sizeName ${entry.key} ${brightness.name}', skip: !_enabled || !_sizeEnabled(sizeName),
            (tester) async {
          final h = await _Harness.start(tester, entry.key, size, brightness);
          for (final step in entry.value) {
            await step(tester, h.ref);
            await h.settle();
          }
          await h.settle();
          final image = await h.capture();
          await tester.runAsync(() => _writePng(image, 'build/screens/$sizeName/${entry.key}_${brightness.name}.png'));
          // Stillness: once settled, nothing may keep animating. On failure
          // the report shows where each running animation was started.
          SchedulerBinding.instance.debugAssertNoTransientCallbacks('Still animating after settling');
          await h.finish();
        });
      }
    }

    for (final entry in _motions.entries) {
      final motion = entry.value;
      for (final sizeName in motion.sizes) {
        final size = _sizes[sizeName]!;
        testWidgets('motion $sizeName ${entry.key} ${brightness.name}', skip: !_enabled || !_sizeEnabled(sizeName),
            (tester) async {
          final h = await _Harness.start(tester, entry.key, size, brightness);
          for (final step in motion.setup) {
            await step(tester, h.ref);
            await h.settle();
          }
          final frames = <(String, ui.Image)>[('before', await h.capture())];
          await motion.action(tester, h.ref);
          await h.propagate();
          var elapsed = 0;
          for (final ms in motion.at) {
            await tester.pump(Duration(milliseconds: ms - elapsed));
            elapsed = ms;
            frames.add(('$ms ms', await h.capture()));
          }
          await h.settle();
          frames.add(('settled', await h.capture()));
          final crop = motion.crop?.call(size) ?? Offset.zero & size;
          final strip = (await tester.runAsync(() => _filmstrip(frames, crop, brightness)))!;
          await tester.runAsync(() => _writePng(strip, 'build/screens/motion/${sizeName}_${entry.key}_${brightness.name}.png'));
          await h.finish();
        });
      }
    }
  }
}
