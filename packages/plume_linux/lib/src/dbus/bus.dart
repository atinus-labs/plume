import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

final _log = Logger('plume_linux.bus');

/// Default timeout for D-Bus round trips. `package:dbus` never times out on
/// its own (and never fails pending calls when the socket drops), so every
/// call made by this package is bounded.
const defaultCallTimeout = Duration(seconds: 5);

/// A D-Bus connection that is either owned by a component (created lazily and
/// closed on dispose) or borrowed from the caller (never closed by us).
///
/// It also works around a `package:dbus` 0.8 quirk: if the very first
/// connection attempt fails, every later call on that client hangs forever.
/// [connect] performs one bounded probe and remembers a failure so callers can
/// degrade instead of hanging.
class BusHandle {
  BusHandle.session([DBusClient? client])
    : client = client ?? DBusClient.session(),
      owned = client == null;

  BusHandle.system([DBusClient? client])
    : client = client ?? DBusClient.system(),
      owned = client == null;

  final DBusClient client;
  final bool owned;

  Future<bool>? _connecting;
  bool _closed = false;

  /// Connects (once) and returns whether the bus is usable.
  Future<bool> connect({Duration timeout = defaultCallTimeout}) {
    if (_closed) return Future.value(false);
    return _connecting ??= () async {
      try {
        await client.getId().timeout(timeout);
        return true;
      } catch (e) {
        _log.info('D-Bus connection to ${client.toString()} failed: $e');
        return false;
      }
    }();
  }

  /// Closes the connection if this handle owns it.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!owned) return;
    try {
      await client.close();
    } catch (e) {
      _log.fine('Error closing D-Bus client: $e');
    }
  }
}

/// Strips any number of nested variants (`v`, `<<v>>`, ...).
DBusValue unwrapVariant(DBusValue value) {
  var v = value;
  while (v is DBusVariant) {
    v = v.value;
  }
  return v;
}

/// Whether [name] currently has an owner, or (optionally) can be
/// bus-activated.
Future<bool> isNameAvailable(
  DBusClient client,
  String name, {
  bool includeActivatable = true,
  Duration timeout = defaultCallTimeout,
}) async {
  try {
    if (await client.nameHasOwner(name).timeout(timeout)) return true;
    if (!includeActivatable) return false;
    final activatable = await client.listActivatableNames().timeout(timeout);
    return activatable.contains(name);
  } catch (e) {
    _log.fine('Name lookup for $name failed: $e');
    return false;
  }
}

/// The error name of a failed call, or `null` for non-D-Bus errors.
String? dbusErrorName(Object error) =>
    error is DBusMethodResponseException ? error.errorName : null;

/// Listens to [stream] and logs (instead of propagating) signal signature
/// errors from misbehaving peers.
StreamSubscription<DBusSignal> listenSignals(
  Stream<DBusSignal> stream,
  void Function(DBusSignal signal) onSignal,
  Logger log,
) {
  return stream.listen((signal) {
    try {
      onSignal(signal);
    } catch (e, st) {
      log.warning('Failed to handle ${signal.interface}.${signal.name}', e, st);
    }
  }, onError: (Object e) => log.fine('Ignoring malformed signal: $e'));
}

/// Ensures match rules added by freshly listened [DBusSignalStream]s are
/// active on the bus.
///
/// `package:dbus` sends `AddMatch` asynchronously from `listen()`; yielding
/// once lets it go out, and a round trip on the same connection guarantees
/// the bus has processed it, so no signal emitted afterwards is missed.
Future<void> flushMatchRules(
  DBusClient client, {
  Duration timeout = defaultCallTimeout,
}) async {
  await Future<void>.delayed(Duration.zero);
  try {
    await client.getId().timeout(timeout);
  } catch (e) {
    _log.fine('Match rule flush failed: $e');
  }
}
