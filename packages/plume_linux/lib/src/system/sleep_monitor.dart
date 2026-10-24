import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

import '../dbus/bus.dart';

final _log = Logger('plume_linux.sleep');

sealed class SleepEvent {
  const SleepEvent();
}

/// The system is about to suspend/hibernate.
final class SleepPreparing extends SleepEvent {
  const SleepPreparing();

  @override
  String toString() => 'SleepPreparing()';
}

/// The system resumed. [sleptFor] is the wall-clock gap since the matching
/// [SleepPreparing] (null if that was missed).
final class SleepResumed extends SleepEvent {
  const SleepResumed({this.sleptFor});
  final Duration? sleptFor;

  @override
  String toString() => 'SleepResumed(sleptFor: $sleptFor)';
}

/// Follows logind's `PrepareForSleep` on the system bus so the app can
/// reconnect IMAP/IDLE sockets and resync after resume.
class SleepMonitor {
  SleepMonitor({DBusClient? systemBus, this.callTimeout = defaultCallTimeout})
    : _bus = BusHandle.system(systemBus);

  static const login1Name = 'org.freedesktop.login1';
  static final login1Path = DBusObjectPath('/org/freedesktop/login1');
  static const managerInterface = 'org.freedesktop.login1.Manager';

  final Duration callTimeout;
  final BusHandle _bus;
  final _events = StreamController<SleepEvent>.broadcast();
  StreamSubscription<DBusSignal>? _subscription;
  Future<bool>? _start;
  DateTime? _sleptAt;
  bool _disposed = false;

  Stream<SleepEvent> get events => _events.stream;

  /// Convenience: only resume events.
  Stream<SleepResumed> get resumed =>
      events.where((e) => e is SleepResumed).cast<SleepResumed>();

  /// Starts listening. Returns false (and emits nothing) without logind.
  Future<bool> start() => _start ??= _doStart();

  Future<bool> _doStart() async {
    if (!await _bus.connect(timeout: callTimeout)) return false;
    if (!await isNameAvailable(_bus.client, login1Name, timeout: callTimeout)) {
      _log.info('logind not available; no sleep/resume events');
      return false;
    }
    _subscription = listenSignals(
      DBusSignalStream(
        _bus.client,
        sender: login1Name,
        interface: managerInterface,
        name: 'PrepareForSleep',
        path: login1Path,
        signature: DBusSignature('b'),
      ),
      _onPrepareForSleep,
      _log,
    );
    await flushMatchRules(_bus.client, timeout: callTimeout);
    return true;
  }

  void _onPrepareForSleep(DBusSignal s) {
    if (_disposed) return;
    final goingToSleep = s.values[0].asBoolean();
    if (goingToSleep) {
      _sleptAt = DateTime.now();
      _log.info('System preparing for sleep');
      _events.add(const SleepPreparing());
    } else {
      final at = _sleptAt;
      _sleptAt = null;
      final gap = at == null ? null : DateTime.now().difference(at);
      _log.info('System resumed (slept ${gap ?? 'unknown'})');
      _events.add(SleepResumed(sleptFor: gap));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _events.close();
    await _bus.close();
  }
}
