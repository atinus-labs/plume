import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/platform/linux/linux_desktop.dart';
import 'package:plume/src/platform/linux/window_channel.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/services/secret_store.dart';
import 'package:plume/src/services/window_frame.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/settings/settings_page.dart';
import 'package:plume/src/ui/shell/title_bar.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:plume_store/plume_store.dart';

/// Records what the title bar asks of the window.
class _Frame extends WindowFrame {
  _Frame({this.defaultStyle = TitleBar.plume, String layout = ''}) : _buttons = parseDecorationLayout(layout);

  @override
  final TitleBar defaultStyle;
  (List<WindowButton>, List<WindowButton>) _buttons;
  bool _maximized = false;
  final calls = <String>[];

  set layout(String value) {
    _buttons = parseDecorationLayout(value);
    notifyListeners();
  }

  set maximized(bool value) {
    _maximized = value;
    notifyListeners();
  }

  @override
  bool get maximized => _maximized;
  @override
  List<WindowButton> get leading => _buttons.$1;
  @override
  List<WindowButton> get trailing => _buttons.$2;
  @override
  Future<void> apply(TitleBar style) async => calls.add('apply ${style.name}');
  @override
  Future<void> startMove() async => calls.add('startMove');
  @override
  Future<void> showMenu() async => calls.add('showMenu');
  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> toggleMaximize() async => calls.add('toggleMaximize');
}

class _Desktop implements DesktopIntegration {
  _Desktop(this.windowFrame);

  @override
  final WindowFrame? windowFrame;
  var quits = 0;

  @override
  bool get hasTray => false;
  @override
  bool get autostartSupported => false;
  @override
  SystemAppearance get appearance => const SystemAppearance();
  @override
  Future<bool> isAutostartEnabled() async => false;
  @override
  Future<DefaultMailAppStatus> defaultMailAppStatus() async => DefaultMailAppStatus.unsupported;
  @override
  Future<void> quit() async => quits++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

ProviderContainer _container(WidgetTester tester, DesktopIntegration desktop, AppSettings settings) {
  final store = DriftMailStore.inMemory();
  addTearDown(() => tester.runAsync(store.close));
  final service = AccountsService(store: store, connectors: const []);
  final engine = MailEngine(store: store, factories: service.factories, tokenSourceFor: service.tokenSourceFor);
  final container = ProviderContainer(
    overrides: [
      servicesProvider.overrideWithValue(Services(
        store: store,
        engine: engine,
        desktop: desktop,
        secrets: _NoSecrets(),
        accounts: service,
        initialSettings: settings,
      )),
      accountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      syncStatusProvider.overrideWith((ref) => Stream.value(const {})),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<(_Desktop, ProviderContainer)> _pump(
  WidgetTester tester,
  _Frame frame,
  Widget home, {
  AppSettings settings = const AppSettings(),
  Size size = const Size(1200, 800),
}) async {
  final desktop = _Desktop(frame);
  final container = _container(tester, desktop, settings);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
  return (desktop, container);
}

const _bar = Scaffold(body: Column(children: [WindowTitleBar(), Spacer()]));

void main() {
  group('parseDecorationLayout', () {
    const minimize = WindowButton.minimize, maximize = WindowButton.maximize, close = WindowButton.close;
    void expectLayout(String layout, List<WindowButton> leading, List<WindowButton> trailing) {
      final (l, t) = parseDecorationLayout(layout);
      expect(l, leading, reason: layout);
      expect(t, trailing, reason: layout);
    }

    test('splits the buttons on each side of the title', () {
      expectLayout('icon:minimize,maximize,close', [], [minimize, maximize, close]);
      expectLayout('close,minimize,maximize:', [close, minimize, maximize], []);
      expectLayout('appmenu: close', [], [close]);
      expectLayout('menu', [], []);
    });

    test("falls back to GTK's default when the desktop doesn't say", () {
      expectLayout('', [], [minimize, maximize, close]);
    });
  });

  test('the title bar choice is saved with the settings', () {
    expect(AppSettings.fromJson(const AppSettings(titleBar: TitleBar.system).toJson()).titleBar, TitleBar.system);
    expect(AppSettings.fromJson(const AppSettings().toJson()).titleBar, isNull);
    expect(AppSettings.fromJson(const {'titleBar': 'bogus'}).titleBar, isNull);
  });

  testWidgets('the title bar follows the desktop until the user picks one', (tester) async {
    TitleBar resolve(DesktopIntegration desktop, AppSettings settings) =>
        _container(tester, desktop, settings).read(titleBarProvider);

    final tiling = _Desktop(_Frame(defaultStyle: TitleBar.none));
    expect(resolve(tiling, const AppSettings()), TitleBar.none);
    expect(resolve(tiling, const AppSettings(titleBar: TitleBar.plume)), TitleBar.plume);
    expect(resolve(_Desktop(_Frame()), const AppSettings()), TitleBar.plume);
    // Nothing to decorate: no title bar, whatever was saved.
    expect(resolve(_Desktop(null), const AppSettings(titleBar: TitleBar.plume)), TitleBar.none);
  });

  test('the window channel carries the title bar calls', () async {
    const channel = MethodChannel(LinuxWindow.channelName);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'decorationLayout' ? 'close,minimize:' : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final window = LinuxWindow(channel: channel, environment: DesktopEnvironment.fromEnvironment(const {}));
    addTearDown(window.dispose);
    final changes = <String>[];
    window.decorationLayoutChanged.listen(changes.add);

    await window.setSystemTitleBar(true);
    await window.showWindowMenu();
    expect(await window.decorationLayout(), 'close,minimize:');
    expect(calls.map((c) => (c.method, c.arguments)), [
      ('setSystemTitleBar', true),
      ('showWindowMenu', null),
      ('decorationLayout', null),
    ]);

    await messenger.handlePlatformMessage(
      LinuxWindow.channelName,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onDecorationLayoutChanged', ':close')),
      (_) {},
    );
    expect(changes, [':close']);
  });

  testWidgets('window buttons sit where the desktop puts them', (tester) async {
    final frame = _Frame(layout: 'icon:minimize,maximize,close');
    await _pump(tester, frame, _bar);

    double x(String tooltip) => tester.getCenter(find.byTooltip(tooltip)).dx;
    final name = tester.getCenter(find.text('Plume')).dx;
    expect(name, lessThan(x('Minimise')));
    expect(x('Minimise'), lessThan(x('Maximise')));
    expect(x('Maximise'), lessThan(x('Close')));
    // As far from the window's edge as from its top.
    expect(tester.getTopRight(find.byTooltip('Close')).dx, 1200 - 6);

    frame.layout = 'close,minimize:';
    await tester.pumpAndSettle();
    expect(find.byTooltip('Maximise'), findsNothing);
    expect(tester.getTopLeft(find.byTooltip('Close')).dx, 6);
    expect(x('Close'), lessThan(x('Minimise')));
    expect(x('Minimise'), lessThan(tester.getCenter(find.text('Plume')).dx));
  });

  testWidgets('the buttons and the bar control the window', (tester) async {
    final frame = _Frame();
    final (desktop, _) = await _pump(tester, frame, _bar);

    await tester.tap(find.byTooltip('Minimise'));
    await tester.tap(find.byTooltip('Maximise'));
    await tester.pumpAndSettle();
    expect(frame.calls, ['minimize', 'toggleMaximize']);

    frame.maximized = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Maximise'), findsNothing);
    expect(find.byTooltip('Restore'), findsOneWidget);

    // The name is part of the bar: dragging it moves the window.
    frame.calls.clear();
    final name = tester.getCenter(find.text('Plume'));
    await tester.dragFrom(name, const Offset(60, 20));
    await tester.pumpAndSettle();
    expect(frame.calls, ['startMove']);

    frame.calls.clear();
    await tester.tapAt(name);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(name);
    await tester.pumpAndSettle();
    expect(frame.calls, ['toggleMaximize']);

    frame.calls.clear();
    await tester.tapAt(name, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(frame.calls, ['showMenu']);

    // No tray to keep running in: closing quits.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(desktop.quits, 1);
  });

  testWidgets('settings switch between Plume’s title bar, the system’s and none', (tester) async {
    final frame = _Frame();
    final (_, container) = await _pump(tester, frame, const SettingsPage(), size: const Size(1200, 1600));
    expect(find.byType(WindowTitleBar), findsOneWidget);
    expect(find.text('Window buttons in Plume’s style, arranged like your desktop’s'), findsOneWidget);

    Future<void> pick(String label) async {
      final segment = find.descendant(of: find.byKey(const ValueKey('settings_title_bar')), matching: find.text(label));
      await tester.ensureVisible(segment);
      await tester.pumpAndSettle();
      await tester.tap(segment);
      await tester.pumpAndSettle();
    }

    await pick('System');
    expect(frame.calls, ['apply system']);
    expect(container.read(settingsProvider).titleBar, TitleBar.system);
    expect(find.byType(WindowTitleBar), findsNothing);
    expect(find.text('Your desktop’s own title bar'), findsOneWidget);

    await pick('None');
    expect(frame.calls.last, 'apply none');
    expect(find.byType(WindowTitleBar), findsNothing);

    await pick('Plume');
    expect(frame.calls.last, 'apply plume');
    expect(find.byType(WindowTitleBar), findsOneWidget);
  });

  testWidgets('no title bar setting where Plume has no window to decorate', (tester) async {
    final desktop = _Desktop(null);
    final container = _container(tester, desktop, const AppSettings());
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: PlumeTheme.build(brightness: Brightness.light, seed: PlumeTheme.defaultSeed, contrast: 0.0),
        home: const SettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Title bar'), findsNothing);
    expect(find.byType(WindowTitleBar), findsNothing);
  });
}
