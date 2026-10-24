// Manual smoke test for the current desktop session.
//
//   dart run example/desktop_smoke.dart          # probe everything (read-only)
//   dart run example/desktop_smoke.dart notify   # click the notification
//   dart run example/desktop_smoke.dart tray     # click / open the tray menu
//
// Interactive modes clean up after themselves within 60 seconds.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:plume_linux/plume_linux.dart';

void out(Object? line) => stdout.writeln(line);

Future<void> main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(
    (r) => stderr.writeln('[${r.loggerName}] ${r.message}'),
  );
  switch (args.firstOrNull) {
    case 'notify':
      await notify();
    case 'tray':
      await tray();
    default:
      await probe();
  }
  exit(0);
}

Future<void> probe() async {
  final de = DesktopEnvironment.current();
  out('Desktop: $de');
  out('  prefersServerSideDecorations: ${de.prefersServerSideDecorations}');

  final n = DesktopNotifications();
  out(
    'Notifications: ${await n.initialize()} ${n.serverInfo} ${n.capabilities}',
  );
  await n.dispose();

  final a = PortalAppearance();
  out('Portal appearance: ${await a.initialize()} ${a.current}');
  await a.dispose();

  final t = StatusNotifierTray();
  out('Tray host available: ${await t.isAvailable()}');
  await t.dispose();

  final c = ConnectivityMonitor();
  out('Connectivity: ${await c.start()}');
  await c.dispose();

  final s = SleepMonitor();
  out('Sleep monitor: ${await s.start()}');
  await s.dispose();

  final auto = Autostart();
  out(
    'Autostart: enabled=${await auto.isEnabled()} '
    'honoured=${await auto.probeXdgAutostartSupport()} '
    'snippet=${auto.compositorAutostartSnippet}',
  );
}

Future<void> notify() async {
  final n = DesktopNotifications();
  if (!await n.initialize()) {
    out('No notification server.');
    return;
  }
  final done = Completer<void>();
  n.events.listen((e) {
    out('Event: $e');
    if (!done.isCompleted) done.complete();
  });
  final id = await n.show(
    NotificationRequest(
      summary: 'Plume test',
      body: 'Click the notification or "Archive" <test>',
      appIcon: 'mail-unread',
      image: NotificationImage.rgba(
        _square(64, 0x67, 0x50, 0xA4),
        width: 64,
        height: 64,
        premultiplied: false,
      ),
      actions: const [
        NotificationAction.byDefault(),
        NotificationAction('archive', 'Archive'),
      ],
      category: NotificationCategories.emailArrived,
      inlineReply: const NotificationInlineReply(placeholder: 'Reply…'),
      transient: true,
      timeout: Duration.zero,
    ),
  );
  out('Shown notification $id; waiting up to 60 s for a click…');
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  await n.close(id);
  await n.dispose();
}

Future<void> tray() async {
  final t = StatusNotifierTray();
  final done = Completer<void>();
  var checked = false;
  List<TrayMenuItem> menu() => [
    const TrayMenuItem(id: 'open', label: 'Plume test: Open'),
    TrayMenuItem(id: 'toggle', label: 'Plume test: Toggle', checked: checked),
    const TrayMenuItem.separator(),
    const TrayMenuItem(id: 'quit', label: 'Plume test: Quit'),
  ];
  t.events.listen((e) async {
    out('Event: $e');
    if (e is TrayMenuItemSelected && e.id == 'toggle') {
      checked = !checked;
      await t.setMenu(menu());
    }
    if (e is TrayMenuItemSelected && e.id == 'quit' && !done.isCompleted) {
      done.complete();
    }
  });
  final ok = await t.start(
    TrayConfig(
      title: 'Plume test',
      iconPixmaps: [
        for (final s in [16, 22, 32, 48])
          TrayPixmap.fromRgba(
            _square(s, 0x67, 0x50, 0xA4),
            s,
            s,
            premultiplied: false,
          ),
      ],
      tooltipBody: 'plume_linux smoke test',
      menu: menu(),
    ),
  );
  out(
    'Tray visible: $ok (${t.busName}); click it, open its menu, '
    'choose Quit or wait 60 s',
  );
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  await t.dispose();
}

Uint8List _square(int size, int r, int g, int b) {
  final px = Uint8List(size * size * 4);
  for (var i = 0; i < px.length; i += 4) {
    px
      ..[i] = r
      ..[i + 1] = g
      ..[i + 2] = b
      ..[i + 3] = 255;
  }
  return px;
}
