import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

import '../dbus/bus.dart';

final _log = Logger('plume_linux.connectivity');

/// NetworkManager's `NMConnectivityState`.
enum NetworkConnectivity {
  unknown,
  none,

  /// Behind a captive portal.
  portal,

  /// Connected, but no route to the internet.
  limited,
  full;

  static NetworkConnectivity fromValue(int v) => switch (v) {
    1 => none,
    2 => portal,
    3 => limited,
    4 => full,
    _ => unknown,
  };
}

/// NetworkManager's `NMState`.
enum NetworkState {
  unknown(0),
  asleep(10),
  disconnected(20),
  disconnecting(30),
  connecting(40),
  connectedLocal(50),
  connectedSite(60),
  connectedGlobal(70);

  const NetworkState(this.value);
  final int value;

  static NetworkState fromValue(int v) =>
      values.firstWhere((s) => s.value == v, orElse: () => unknown);
}

/// One connectivity snapshot.
class ConnectivityStatus {
  const ConnectivityStatus(this.connectivity, this.state);

  final NetworkConnectivity connectivity;
  final NetworkState state;

  /// Worth attempting a sync. `unknown` connectivity (NM's checker disabled)
  /// falls back to the global connection state.
  bool get isOnline => switch (connectivity) {
    NetworkConnectivity.full => true,
    NetworkConnectivity.limited || NetworkConnectivity.portal => false,
    NetworkConnectivity.none => false,
    NetworkConnectivity.unknown => state == NetworkState.connectedGlobal,
  };

  @override
  bool operator ==(Object other) =>
      other is ConnectivityStatus &&
      other.connectivity == connectivity &&
      other.state == state;

  @override
  int get hashCode => Object.hash(connectivity, state);

  @override
  String toString() =>
      'ConnectivityStatus(${connectivity.name}, ${state.name}, online: $isOnline)';
}

/// Follows NetworkManager's `Connectivity` and `State` on the system bus.
///
/// Without NetworkManager (systemd-networkd, iwd-only, some containers)
/// [start] returns `null` and [isAvailable] is false; callers should then
/// assume online and rely on socket errors.
class ConnectivityMonitor {
  ConnectivityMonitor({
    DBusClient? systemBus,
    this.callTimeout = defaultCallTimeout,
  }) : _bus = BusHandle.system(systemBus);

  static const nmName = 'org.freedesktop.NetworkManager';
  static final nmPath = DBusObjectPath('/org/freedesktop/NetworkManager');
  static const nmInterface = 'org.freedesktop.NetworkManager';

  final Duration callTimeout;
  final BusHandle _bus;
  final _changes = StreamController<ConnectivityStatus>.broadcast();
  final _subscriptions = <StreamSubscription<DBusSignal>>[];
  Future<ConnectivityStatus?>? _start;
  ConnectivityStatus? _current;
  bool _disposed = false;

  bool get isAvailable => _current != null;

  /// The latest status, or `null` without NetworkManager.
  ConnectivityStatus? get current => _current;

  /// Distinct status changes.
  Stream<ConnectivityStatus> get changes => _changes.stream;

  /// Reads the current status and starts following changes. Returns `null`
  /// when NetworkManager is absent. Never throws.
  Future<ConnectivityStatus?> start() => _start ??= _doStart();

  Future<ConnectivityStatus?> _doStart() async {
    if (!await _bus.connect(timeout: callTimeout)) return null;
    final client = _bus.client;
    if (!await isNameAvailable(
      client,
      nmName,
      includeActivatable: false,
      timeout: callTimeout,
    )) {
      _log.info('NetworkManager not available');
      return null;
    }
    _subscriptions
      ..add(
        listenSignals(
          DBusSignalStream(
            client,
            sender: nmName,
            interface: nmInterface,
            name: 'StateChanged',
            path: nmPath,
            signature: DBusSignature('u'),
          ),
          (s) => _update(state: NetworkState.fromValue(s.values[0].asUint32())),
          _log,
        ),
      )
      ..add(
        listenSignals(
          DBusSignalStream(
            client,
            sender: nmName,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'PropertiesChanged',
            path: nmPath,
            signature: DBusSignature('sa{sv}as'),
          ),
          (s) {
            if (s.values[0].asString() != nmInterface) return;
            final changed = s.values[1].asStringVariantDict();
            final c = changed['Connectivity'];
            final st = changed['State'];
            if (c == null && st == null) return;
            _update(
              connectivity: c is DBusUint32
                  ? NetworkConnectivity.fromValue(c.value)
                  : null,
              state: st is DBusUint32 ? NetworkState.fromValue(st.value) : null,
            );
          },
          _log,
        ),
      );
    return refresh();
  }

  /// Re-reads both properties (e.g. after resume). `null` on failure.
  Future<ConnectivityStatus?> refresh() async {
    try {
      final props = await _bus.client
          .callMethod(
            destination: nmName,
            path: nmPath,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'GetAll',
            values: [const DBusString(nmInterface)],
            replySignature: DBusSignature('a{sv}'),
          )
          .timeout(callTimeout);
      final all = props.returnValues[0].asStringVariantDict();
      final c = all['Connectivity'];
      final s = all['State'];
      _update(
        connectivity: NetworkConnectivity.fromValue(
          c is DBusUint32 ? c.value : 0,
        ),
        state: NetworkState.fromValue(s is DBusUint32 ? s.value : 0),
        force: true,
      );
      return _current;
    } catch (e) {
      _log.fine('Reading NetworkManager state failed: $e');
      return null;
    }
  }

  void _update({
    NetworkConnectivity? connectivity,
    NetworkState? state,
    bool force = false,
  }) {
    if (_disposed) return;
    final prev = _current;
    if (prev == null && !force) return;
    final next = ConnectivityStatus(
      connectivity ?? prev?.connectivity ?? NetworkConnectivity.unknown,
      state ?? prev?.state ?? NetworkState.unknown,
    );
    _current = next;
    if (next != prev) {
      _log.fine('Connectivity: $next');
      if (prev != null) _changes.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _changes.close();
    await _bus.close();
  }
}
