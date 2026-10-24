@Tags(['dbus'])
library;

import 'package:dbus/dbus.dart';
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

import '../support/private_bus.dart';

class FakeLogin1 extends DBusObject {
  FakeLogin1() : super(SleepMonitor.login1Path);

  Future<void> prepareForSleep(bool start) => emitSignal(
    SleepMonitor.managerInterface,
    'PrepareForSleep',
    [DBusBoolean(start)],
  );
}

class FakeNetworkManager extends DBusObject {
  FakeNetworkManager() : super(ConnectivityMonitor.nmPath);

  int connectivity = 4;
  int state = 70;

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse({
        'Connectivity': DBusUint32(connectivity),
        'State': DBusUint32(state),
        'NetworkingEnabled': const DBusBoolean(true),
      });

  Future<void> setState(int s) async {
    state = s;
    await emitSignal(ConnectivityMonitor.nmInterface, 'StateChanged', [
      DBusUint32(s),
    ]);
  }

  Future<void> setConnectivity(int c) async {
    connectivity = c;
    await emitPropertiesChanged(
      ConnectivityMonitor.nmInterface,
      changedProperties: {'Connectivity': DBusUint32(c)},
    );
  }
}

void main() {
  if (!dbusDaemonAvailable) {
    test('system monitors', () {}, skip: 'dbus-daemon not installed');
    return;
  }

  late PrivateBus bus;
  setUp(() async => bus = await PrivateBus.start());
  tearDown(() => bus.stop());

  group('SleepMonitor', () {
    test('no logind: start() is false', () async {
      final m = SleepMonitor(systemBus: bus.client());
      expect(await m.start(), isFalse);
      await m.dispose();
    });

    test('emits preparing and resumed', () async {
      final login1 = FakeLogin1();
      await serve(bus, SleepMonitor.login1Name, login1);
      final m = SleepMonitor(systemBus: bus.client());
      expect(await m.start(), isTrue);
      final events = <SleepEvent>[];
      m.events.listen(events.add);
      final resumed = m.resumed.first;
      await login1.prepareForSleep(true);
      await login1.prepareForSleep(false);
      await eventually(() => events.length == 2);
      expect(events[0], isA<SleepPreparing>());
      expect((events[1] as SleepResumed).sleptFor, isNotNull);
      expect(await resumed, isA<SleepResumed>());
      await m.dispose();
    });
  });

  group('ConnectivityMonitor', () {
    test('no NetworkManager: null and unavailable', () async {
      final m = ConnectivityMonitor(systemBus: bus.client());
      expect(await m.start(), isNull);
      expect(m.isAvailable, isFalse);
      await m.dispose();
    });

    test('reads and follows state and connectivity', () async {
      final nm = FakeNetworkManager();
      await serve(bus, ConnectivityMonitor.nmName, nm);
      final m = ConnectivityMonitor(systemBus: bus.client());
      final initial = await m.start();
      expect(initial!.connectivity, NetworkConnectivity.full);
      expect(initial.state, NetworkState.connectedGlobal);
      expect(initial.isOnline, isTrue);

      final changes = <ConnectivityStatus>[];
      m.changes.listen(changes.add);
      await nm.setState(20);
      await nm.setConnectivity(1);
      await nm.setConnectivity(1); // unchanged
      await nm.setConnectivity(2);
      await eventually(() => changes.length == 3);
      expect(changes[0].state, NetworkState.disconnected);
      expect(changes[1].connectivity, NetworkConnectivity.none);
      expect(changes[1].isOnline, isFalse);
      expect(changes[2].connectivity, NetworkConnectivity.portal);
      expect(m.current, changes.last);

      expect(
        const ConnectivityStatus(
          NetworkConnectivity.unknown,
          NetworkState.connectedGlobal,
        ).isOnline,
        isTrue,
      );
      await m.dispose();
    });
  });
}
