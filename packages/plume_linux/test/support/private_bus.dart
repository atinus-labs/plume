import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// Whether `dbus-daemon` is installed (integration tests skip otherwise).
final bool dbusDaemonAvailable = () {
  try {
    return Process.runSync('dbus-daemon', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}();

/// A throwaway message bus (`dbus-daemon` with no service directories, so
/// nothing real is ever auto-started on it).
class PrivateBus {
  PrivateBus._(this._process, this.address, this._dir);

  final Process _process;
  final String address;
  final Directory _dir;
  final _clients = <DBusClient>[];

  static Future<PrivateBus> start() async {
    final dir = await Directory.systemTemp.createTemp('plume_dbus_');
    final config = File('${dir.path}/bus.conf');
    await config.writeAsString('''
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=${dir.path}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
''');
    final process = await Process.start('dbus-daemon', [
      '--config-file=${config.path}',
      '--print-address',
      '--nofork',
      '--nosyslog',
    ]);
    unawaited(process.stderr.drain<void>());
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final address = Completer<String>();
    lines.listen((l) {
      if (!address.isCompleted && l.trim().isNotEmpty) {
        address.complete(l.trim());
      }
    });
    return PrivateBus._(
      process,
      await address.future.timeout(const Duration(seconds: 10)),
      dir,
    );
  }

  /// A new connection; closed by [stop] unless closed earlier.
  DBusClient client() {
    final c = DBusClient(DBusAddress(address));
    _clients.add(c);
    return c;
  }

  Future<void> stop() async {
    for (final c in _clients) {
      try {
        await c.close();
      } catch (_) {}
    }
    _process.kill();
    await _process.exitCode;
    await _dir.delete(recursive: true);
  }
}

/// Exports [object] on a fresh connection that owns [name].
Future<DBusClient> serve(PrivateBus bus, String name, DBusObject object) async {
  final c = bus.client();
  await c.registerObject(object);
  final reply = await c.requestName(name);
  if (reply != DBusRequestNameReply.primaryOwner) {
    throw StateError('Could not own $name: $reply');
  }
  return c;
}

/// Waits until [predicate] holds, polling.
Future<void> eventually(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
