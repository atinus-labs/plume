@Tags(['dbus'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

import '../support/private_bus.dart';

/// A minimal `org.kde.StatusNotifierWatcher`.
class FakeWatcher extends DBusObject {
  FakeWatcher({this.hostRegistered = true})
    : super(StatusNotifierTray.watcherPath);

  bool hostRegistered;
  final items = <String>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name == 'RegisterStatusNotifierItem') {
      final service = call.values[0].asString();
      if (!items.contains(service)) items.add(service);
      await emitSignal(
        StatusNotifierTray.watcherInterface,
        'StatusNotifierItemRegistered',
        [DBusString(service)],
      );
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    switch (name) {
      case 'IsStatusNotifierHostRegistered':
        return DBusGetPropertyResponse(DBusBoolean(hostRegistered));
      case 'RegisteredStatusNotifierItems':
        return DBusGetPropertyResponse(DBusArray.string(items));
      case 'ProtocolVersion':
        return DBusGetPropertyResponse(const DBusInt32(0));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  Future<void> hostAppeared() async {
    hostRegistered = true;
    await emitSignal(
      StatusNotifierTray.watcherInterface,
      'StatusNotifierHostRegistered',
    );
  }
}

/// Acts as the tray host: talks to the item like a panel would.
class Host {
  Host(this.client, this.service);

  final DBusClient client;
  final String service;

  Future<DBusMethodSuccessResponse> item(
    String method, [
    List<DBusValue> values = const [],
  ]) => client.callMethod(
    destination: service,
    path: StatusNotifierTray.itemPath,
    interface: StatusNotifierTray.itemInterface,
    name: method,
    values: values,
  );

  Future<DBusMethodSuccessResponse> menu(
    String method, [
    List<DBusValue> values = const [],
  ]) => client.callMethod(
    destination: service,
    path: StatusNotifierTray.menuPath,
    interface: StatusNotifierTray.menuInterface,
    name: method,
    values: values,
  );

  Future<Map<String, DBusValue>> itemProperties() => DBusRemoteObject(
    client,
    name: service,
    path: StatusNotifierTray.itemPath,
  ).getAllProperties(StatusNotifierTray.itemInterface);

  Stream<DBusSignal> signals(DBusObjectPath path) =>
      DBusSignalStream(client, sender: service, path: path);
}

const _menu = [
  TrayMenuItem(id: 'open', label: 'Open Plume'),
  TrayMenuItem(id: 'compose', label: 'Compose', enabled: false),
  TrayMenuItem.separator(),
  TrayMenuItem(id: 'quit', label: 'Quit'),
];

TrayPixmap _pixmap(int size) =>
    TrayPixmap.fromRgba(Uint8List(size * size * 4), size, size);

void main() {
  if (!dbusDaemonAvailable) {
    test('tray integration', () {}, skip: 'dbus-daemon not installed');
    return;
  }

  late PrivateBus bus;

  setUp(() async => bus = await PrivateBus.start());
  tearDown(() => bus.stop());

  test(
    'without a watcher: start() is false, registers when one appears',
    () async {
      final tray = StatusNotifierTray(bus: bus.client());
      expect(await tray.isAvailable(), isFalse);
      final events = <TrayEvent>[];
      tray.events.listen(events.add);
      expect(
        await tray.start(const TrayConfig(iconName: 'mail-unread')),
        isFalse,
      );
      expect(tray.busName, startsWith('org.kde.StatusNotifierItem-$pid-'));

      final watcher = FakeWatcher();
      await serve(bus, StatusNotifierTray.watcherName, watcher);
      await eventually(() => tray.isRegistered);
      expect(watcher.items, [tray.busName]);
      expect(
        events.whereType<TrayAvailabilityChanged>().map((e) => e.available),
        [true],
      );
      await tray.dispose();
    },
  );

  test('watcher without a host: registered but not available', () async {
    final watcher = FakeWatcher(hostRegistered: false);
    await serve(bus, StatusNotifierTray.watcherName, watcher);
    final tray = StatusNotifierTray(bus: bus.client());
    expect(await tray.start(const TrayConfig()), isFalse);
    expect(watcher.items, hasLength(1));
    await watcher.hostAppeared();
    await eventually(() => tray.isRegistered);
    await tray.dispose();
  });

  group('with a watcher and host', () {
    late FakeWatcher watcher;
    late DBusClient watcherConn;
    late StatusNotifierTray tray;
    late Host host;
    final events = <TrayEvent>[];

    setUp(() async {
      events.clear();
      watcher = FakeWatcher();
      watcherConn = await serve(bus, StatusNotifierTray.watcherName, watcher);
      tray = StatusNotifierTray(bus: bus.client());
      tray.events.listen(events.add);
      final ok = await tray.start(
        TrayConfig(
          title: 'Plume',
          iconName: 'mail-read',
          iconPixmaps: [_pixmap(16), _pixmap(32)],
          tooltipBody: 'No unread mail',
          menu: _menu,
        ),
      );
      expect(ok, isTrue);
      expect(await tray.isAvailable(), isTrue);
      host = Host(bus.client(), tray.busName!);
    });

    tearDown(() => tray.dispose());

    test('exposes the StatusNotifierItem properties', () async {
      final p = await host.itemProperties();
      expect(p['Category'], const DBusString('Communications'));
      expect(p['Id'], const DBusString('org.atinus.plume'));
      expect(p['Title'], const DBusString('Plume'));
      expect(p['Status'], const DBusString('Active'));
      expect(p['IconName'], const DBusString('mail-read'));
      expect(p['IconPixmap']!.signature, DBusSignature('a(iiay)'));
      expect(p['IconPixmap']!.asArray(), hasLength(2));
      expect(p['AttentionIconPixmap']!.signature, DBusSignature('a(iiay)'));
      expect(p['ItemIsMenu'], const DBusBoolean(false));
      expect(p['Menu'], DBusObjectPath('/MenuBar'));
      expect(p['ToolTip']!.signature, DBusSignature('(sa(iiay)ss)'));
      expect(p['ToolTip']!.asStruct()[2], const DBusString('Plume'));
      expect(p['ToolTip']!.asStruct()[3], const DBusString('No unread mail'));
    });

    test('introspection describes both objects', () async {
      final node = await DBusRemoteObject(
        host.client,
        name: host.service,
        path: StatusNotifierTray.itemPath,
      ).introspect();
      expect(
        node.interfaces.map((i) => i.name),
        contains('org.kde.StatusNotifierItem'),
      );
      final menuNode = await DBusRemoteObject(
        host.client,
        name: host.service,
        path: StatusNotifierTray.menuPath,
      ).introspect();
      expect(
        menuNode.interfaces.map((i) => i.name),
        contains('com.canonical.dbusmenu'),
      );
    });

    test('host clicks become events, with activation tokens', () async {
      await host.item('Activate', [const DBusInt32(10), const DBusInt32(20)]);
      await host.item('ProvideXdgActivationToken', [const DBusString('tok')]);
      await host.item('Activate', [const DBusInt32(1), const DBusInt32(2)]);
      await host.item('SecondaryActivate', [
        const DBusInt32(3),
        const DBusInt32(4),
      ]);
      await host.item('Scroll', [
        const DBusInt32(-120),
        const DBusString('horizontal'),
      ]);
      await host.item('ContextMenu', [const DBusInt32(5), const DBusInt32(6)]);
      final hostEvents = events.where((e) => e is! TrayAvailabilityChanged);
      await eventually(() => hostEvents.length == 5);
      final clicks = hostEvents.toList();
      final a1 = clicks[0] as TrayActivated;
      expect((a1.x, a1.y, a1.activationToken), (10, 20, null));
      final a2 = clicks[1] as TrayActivated;
      expect((a2.x, a2.y, a2.activationToken), (1, 2, 'tok'));
      expect(clicks[2], isA<TraySecondaryActivated>());
      final scroll = clicks[3] as TrayScrolled;
      expect(scroll.delta, -120);
      expect(scroll.orientation, TrayScrollOrientation.horizontal);
      expect(clicks[4], isA<TrayContextMenuRequested>());
    });

    test('property setters emit New* signals', () async {
      final signals = <String>[];
      final sub = host
          .signals(StatusNotifierTray.itemPath)
          .listen(
            (s) => signals.add('${s.name}${s.values.map((v) => v.toNative())}'),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await tray.setStatus(TrayStatus.needsAttention);
      await tray.setStatus(TrayStatus.needsAttention); // no-op
      await tray.setIcon([_pixmap(22)], iconName: 'mail-unread');
      await tray.setAttentionIcon([_pixmap(22)]);
      await tray.setTitle('Plume (3)');
      await tray.setTooltip('Plume', '3 unread');
      await eventually(() => signals.length == 6);
      expect(signals, [
        'NewStatus(NeedsAttention)',
        'NewIcon()',
        'NewToolTip()',
        'NewAttentionIcon()',
        'NewTitle()',
        'NewToolTip()',
      ]);
      final p = await host.itemProperties();
      expect(p['Status'], const DBusString('NeedsAttention'));
      expect(p['IconName'], const DBusString('mail-unread'));
      expect(p['Title'], const DBusString('Plume (3)'));
      expect(p['AttentionIconPixmap']!.asArray(), hasLength(1));
      await sub.cancel();
    });

    test('dbusmenu: layout, properties and click events', () async {
      final version = await DBusRemoteObject(
        host.client,
        name: host.service,
        path: StatusNotifierTray.menuPath,
      ).getProperty(StatusNotifierTray.menuInterface, 'Version');
      expect(version, const DBusUint32(3));

      expect(
        (await host.menu('AboutToShow', [const DBusInt32(0)])).returnValues,
        [const DBusBoolean(false)],
      );

      final reply = await host.menu('GetLayout', [
        const DBusInt32(0),
        const DBusInt32(-1),
        DBusArray.string(const []),
      ]);
      expect(reply.signature, DBusSignature('u(ia{sv}av)'));
      final root = reply.returnValues[1].asStruct();
      final items = root[2].asVariantArray().map((v) => v.asStruct()).toList();
      expect(items, hasLength(4));
      final labels = items
          .map((i) => i[1].asStringVariantDict()['label']?.asString())
          .toList();
      expect(labels, ['Open Plume', 'Compose', null, 'Quit']);
      final quitId = items[3][0].asInt32();
      final composeId = items[1][0].asInt32();

      final prop = await host.menu('GetProperty', [
        DBusInt32(quitId),
        const DBusString('label'),
      ]);
      expect(prop.returnValues.single, const DBusVariant(DBusString('Quit')));

      final group = await host.menu('GetGroupProperties', [
        DBusArray.int32([quitId]),
        DBusArray.string(const ['label']),
      ]);
      expect(group.signature, DBusSignature('a(ia{sv})'));

      await host.menu('Event', [
        DBusInt32(quitId),
        const DBusString('clicked'),
        const DBusVariant(DBusInt32(0)),
        const DBusUint32(0),
      ]);
      // Disabled items and hover events do nothing.
      await host.menu('Event', [
        DBusInt32(composeId),
        const DBusString('clicked'),
        const DBusVariant(DBusInt32(0)),
        const DBusUint32(0),
      ]);
      final groupReply = await host.menu('EventGroup', [
        DBusArray(DBusSignature('(isvu)'), [
          DBusStruct([
            DBusInt32(items[0][0].asInt32()),
            const DBusString('hovered'),
            const DBusVariant(DBusInt32(0)),
            const DBusUint32(0),
          ]),
          DBusStruct([
            DBusInt32(items[0][0].asInt32()),
            const DBusString('clicked'),
            const DBusVariant(DBusInt32(0)),
            const DBusUint32(0),
          ]),
          DBusStruct([
            const DBusInt32(9999),
            const DBusString('clicked'),
            const DBusVariant(DBusInt32(0)),
            const DBusUint32(0),
          ]),
        ]),
      ]);
      expect(groupReply.returnValues.single.asInt32Array(), [9999]);

      final selected = events.whereType<TrayMenuItemSelected>();
      await eventually(() => selected.length == 2);
      expect(selected.map((e) => e.id), ['quit', 'open']);

      final unknown = host.menu('Event', [
        const DBusInt32(9999),
        const DBusString('clicked'),
        const DBusVariant(DBusInt32(0)),
        const DBusUint32(0),
      ]);
      await expectLater(unknown, throwsA(isA<DBusInvalidArgsException>()));
    });

    test('setMenu emits ItemsPropertiesUpdated or LayoutUpdated', () async {
      final signals = <DBusSignal>[];
      final sub = host.signals(StatusNotifierTray.menuPath).listen(signals.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await tray.setMenu([
        _menu[0],
        const TrayMenuItem(id: 'compose', label: 'Compose', enabled: true),
        _menu[2],
        _menu[3],
      ]);
      await tray.setMenu([_menu[0], _menu[3]]);
      await eventually(() => signals.length == 2);

      expect(signals[0].name, 'ItemsPropertiesUpdated');
      final updated = signals[0].values[0].asArray().single.asStruct();
      expect(updated[1].asStringVariantDict(), {
        'enabled': const DBusBoolean(true),
      });

      expect(signals[1].name, 'LayoutUpdated');
      final revision = signals[1].values[0].asUint32();
      final layout = await host.menu('GetLayout', [
        const DBusInt32(0),
        const DBusInt32(-1),
        DBusArray.string(const []),
      ]);
      expect(layout.returnValues[0].asUint32(), revision);
      expect(layout.returnValues[1].asStruct()[2].asArray(), hasLength(2));
      await sub.cancel();
    });

    test('re-registers when the watcher restarts', () async {
      await watcherConn.close();
      await eventually(() => !tray.isRegistered);
      expect(events.last, isA<TrayAvailabilityChanged>());

      final watcher2 = FakeWatcher();
      await serve(bus, StatusNotifierTray.watcherName, watcher2);
      await eventually(() => tray.isRegistered);
      expect(watcher2.items, [tray.busName]);
      expect(
        events.whereType<TrayAvailabilityChanged>().map((e) => e.available),
        [true, false, true],
      );
    });

    test('dispose releases the bus name', () async {
      final name = tray.busName!;
      final observer = bus.client();
      expect(await observer.nameHasOwner(name), isTrue);
      await tray.dispose();
      await eventually(() async => !await observer.nameHasOwner(name));
    });
  });

  test('two trays in one process get distinct names', () async {
    await serve(bus, StatusNotifierTray.watcherName, FakeWatcher());
    final a = StatusNotifierTray(bus: bus.client());
    final b = StatusNotifierTray(bus: bus.client());
    await a.start(const TrayConfig());
    await b.start(const TrayConfig(id: 'second'));
    expect(a.busName, isNot(b.busName));
    await a.dispose();
    await b.dispose();
  });
}
