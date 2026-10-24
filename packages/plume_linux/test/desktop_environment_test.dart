import 'package:plume_linux/plume_linux.dart';
import 'package:test/test.dart';

DesktopEnvironment env(Map<String, String> vars, {bool? flatpak}) =>
    DesktopEnvironment.fromEnvironment(vars, isFlatpak: flatpak);

void main() {
  group('DesktopEnvironment', () {
    test('Hyprland on Wayland is a tiling compositor', () {
      final e = env({
        'XDG_CURRENT_DESKTOP': 'Hyprland',
        'XDG_SESSION_TYPE': 'wayland',
        'DESKTOP_SESSION': 'hyprland',
      });
      expect(e.isHyprland, isTrue);
      expect(e.isWayland, isTrue);
      expect(e.isTilingCompositor, isTrue);
      expect(e.prefersServerSideDecorations, isTrue);
      expect(e.isFullDesktop, isFalse);
      expect(e.primary, 'hyprland');
    });

    test('splits colon lists and strips X- prefixes', () {
      final e = env({
        'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME',
        'XDG_SESSION_TYPE': 'x11',
      });
      expect(e.desktops, ['ubuntu', 'gnome']);
      expect(e.isGnome, isTrue);
      expect(e.isX11, isTrue);
      expect(e.prefersServerSideDecorations, isFalse);
      expect(e.trayExpected, isFalse);

      expect(env({'XDG_CURRENT_DESKTOP': 'X-Cinnamon'}).isCinnamon, isTrue);
      expect(env({'XDG_CURRENT_DESKTOP': 'sway:wlroots'}).isSway, isTrue);
    });

    test('KDE prefers server-side decorations and is not tiling', () {
      final e = env({
        'XDG_CURRENT_DESKTOP': 'KDE',
        'XDG_SESSION_TYPE': 'wayland',
        'DESKTOP_SESSION': '/usr/share/wayland-sessions/plasmawayland',
      });
      expect(e.isKde, isTrue);
      expect(e.isTilingCompositor, isFalse);
      expect(e.prefersServerSideDecorations, isTrue);
      expect(e.trayExpected, isTrue);
    });

    test('recognises tiling window managers', () {
      for (final wm in [
        'sway',
        'niri',
        'river',
        'i3',
        'bspwm',
        'qtile',
        'dwm',
        'herbstluftwm',
        'awesome',
      ]) {
        expect(
          env({'XDG_CURRENT_DESKTOP': wm}).isTilingCompositor,
          isTrue,
          reason: wm,
        );
      }
      for (final de in ['XFCE', 'GNOME', 'KDE', 'Cinnamon', 'MATE', 'LXQt']) {
        expect(
          env({'XDG_CURRENT_DESKTOP': de}).isTilingCompositor,
          isFalse,
          reason: de,
        );
      }
    });

    test('falls back to compositor sockets when XDG vars are missing', () {
      expect(
        env({
          'HYPRLAND_INSTANCE_SIGNATURE': 'abc',
          'WAYLAND_DISPLAY': 'wayland-1',
        }).isHyprland,
        isTrue,
      );
      expect(env({'SWAYSOCK': '/run/sway.sock'}).isSway, isTrue);
      expect(env({'NIRI_SOCKET': '/run/niri.sock'}).isTilingCompositor, isTrue);
      expect(env({'I3SOCK': '/run/i3'}).isI3, isTrue);
    });

    test('session type inference', () {
      expect(env({'XDG_SESSION_TYPE': 'Wayland'}).isWayland, isTrue);
      expect(
        env({'XDG_SESSION_TYPE': 'tty', 'WAYLAND_DISPLAY': 'wayland-0'})
            .sessionType,
        DesktopSessionType.wayland,
      );
      expect(env({'DISPLAY': ':0'}).sessionType, DesktopSessionType.x11);
      expect(env({}).sessionType, DesktopSessionType.unknown);
    });

    test('DESKTOP_SESSION names are normalised', () {
      expect(env({'DESKTOP_SESSION': 'hyprland-uwsm'}).isHyprland, isTrue);
      expect(env({'DESKTOP_SESSION': 'plasmawayland'}).isKde, isTrue);
      expect(env({'DESKTOP_SESSION': 'ubuntu'}).isGnome, isTrue);
    });

    test('Flatpak and uwsm detection', () {
      expect(env({'FLATPAK_ID': 'org.atinus.plume'}).isFlatpak, isTrue);
      expect(env({}).isFlatpak, isFalse);
      expect(env({}, flatpak: true).isFlatpak, isTrue);
      expect(env({'UWSM_FINALIZE_VARNAMES': ''}).hasUwsm, isTrue);
    });

    test('unknown environments', () {
      final e = env({'XDG_SESSION_TYPE': 'wayland'});
      expect(e.primary, isNull);
      expect(e.isTilingCompositor, isFalse);
      expect(e.prefersServerSideDecorations, isFalse);
      expect(
        env({'XDG_SESSION_TYPE': 'x11'}).prefersServerSideDecorations,
        isTrue,
      );
    });
  });
}
