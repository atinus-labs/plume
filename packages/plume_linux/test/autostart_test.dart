import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

DesktopEnvironment env(Map<String, String> vars) =>
    DesktopEnvironment.fromEnvironment(vars, isFlatpak: false);

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('plume_auto_'));
  tearDown(() => tmp.delete(recursive: true));

  Autostart autostart({
    String executable = '/opt/plume/plume',
    Map<String, String> vars = const {'XDG_CURRENT_DESKTOP': 'KDE'},
  }) => Autostart(
    executable: executable,
    configHome: tmp.path,
    environment: env(vars),
    isFlatpak: false,
  );

  group('desktop file', () {
    test('content', () {
      final a = autostart();
      final lines = a.desktopFileContents().split('\n');
      expect(lines.first, '[Desktop Entry]');
      expect(lines, contains('Type=Application'));
      expect(lines, contains('Name=Plume'));
      expect(lines, contains('Exec=/opt/plume/plume --background'));
      expect(lines, contains('Icon=org.atinus.plume'));
      expect(lines, contains('X-GNOME-Autostart-enabled=true'));
      expect(
        a.desktopFilePath,
        p.join(tmp.path, 'autostart', 'org.atinus.plume.desktop'),
      );
    });

    test('Exec quoting follows the Desktop Entry spec', () {
      expect(quoteExecArgument('/usr/bin/plume'), '/usr/bin/plume');
      expect(quoteExecArgument('--background'), '--background');
      expect(quoteExecArgument('/opt/My Apps/plume'), '"/opt/My Apps/plume"');
      expect(quoteExecArgument('100%'), '100%%');
      expect(quoteExecArgument(r'a"b'), r'"a\\"b"');
      expect(quoteExecArgument(r'a\b'), r'"a\\\\b"');
      expect(quoteExecArgument(r'$HOME'), r'"\\$HOME"');
      expect(quoteExecArgument(''), '""');
      final a = autostart(executable: '/home/me/My Apps/plume');
      expect(
        a.desktopFileContents(),
        contains('Exec="/home/me/My Apps/plume" --background\n'),
      );
    });
  });

  group('enable / disable', () {
    test('round trip against a temp config dir', () async {
      final a = autostart();
      expect(await a.isEnabled(), isFalse);
      await a.enable();
      expect(await a.isEnabled(), isTrue);
      expect(
        await File(a.desktopFilePath).readAsString(),
        a.desktopFileContents(),
      );
      expect(
        tmp
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.basename(f.path)),
        ['org.atinus.plume.desktop'],
        reason: 'no temp files left behind',
      );
      await a.enable(); // idempotent
      await a.disable();
      expect(await a.isEnabled(), isFalse);
      expect(File(a.desktopFilePath).existsSync(), isFalse);
      await a.disable(); // idempotent
    });

    test('respects Hidden and X-GNOME-Autostart-enabled=false', () async {
      final a = autostart();
      await a.enable();
      final f = File(a.desktopFilePath);
      await f.writeAsString('${a.desktopFileContents()}Hidden=true\n');
      expect(await a.isEnabled(), isFalse);
      expect(
        isDesktopEntryEnabled(
          '[Desktop Entry]\nX-GNOME-Autostart-enabled=false\n',
        ),
        isFalse,
      );
      expect(
        isDesktopEntryEnabled(
          '[Desktop Entry]\nExec=x\n[Other]\nHidden=true\n',
        ),
        isTrue,
      );
    });
  });

  group('compositorHonorsXdgAutostart', () {
    test('full desktops honour it', () {
      for (final de in ['KDE', 'GNOME', 'XFCE', 'X-Cinnamon', 'MATE', 'LXQt']) {
        expect(
          autostart(vars: {'XDG_CURRENT_DESKTOP': de})
              .compositorHonorsXdgAutostart,
          isTrue,
          reason: de,
        );
      }
    });

    test('bare compositors do not, unless uwsm is detected', () {
      for (final wm in ['Hyprland', 'sway', 'niri', 'river', 'i3']) {
        expect(
          autostart(vars: {'XDG_CURRENT_DESKTOP': wm})
              .compositorHonorsXdgAutostart,
          isFalse,
          reason: wm,
        );
      }
      expect(
        autostart(
          vars: {
            'XDG_CURRENT_DESKTOP': 'Hyprland',
            'UWSM_FINALIZE_VARNAMES': '',
          },
        ).compositorHonorsXdgAutostart,
        isTrue,
      );
    });

    test('compositor config snippets', () {
      String? snippet(String de) =>
          autostart(vars: {'XDG_CURRENT_DESKTOP': de})
              .compositorAutostartSnippet;
      expect(snippet('Hyprland'), 'exec-once = /opt/plume/plume --background');
      expect(snippet('sway'), 'exec /opt/plume/plume --background');
      expect(
        snippet('i3'),
        'exec --no-startup-id /opt/plume/plume --background',
      );
      expect(
        snippet('niri'),
        'spawn-at-startup "/opt/plume/plume" "--background"',
      );
      expect(snippet('KDE'), isNull);
      expect(
        autostart(
          executable: "/opt/it's/plume",
          vars: {'XDG_CURRENT_DESKTOP': 'Hyprland'},
        ).compositorAutostartSnippet,
        r"exec-once = '/opt/it'\''s/plume' --background",
      );
    });
  });
}
