import 'dart:io';

/// The display protocol of the current graphical session.
enum DesktopSessionType { wayland, x11, tty, unknown }

/// A best-effort description of the Linux desktop the app is running in.
///
/// Built from `XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP`, `DESKTOP_SESSION`
/// and `XDG_SESSION_TYPE`, plus compositor-specific sockets
/// (`HYPRLAND_INSTANCE_SIGNATURE`, `SWAYSOCK`, `NIRI_SOCKET`, `I3SOCK`) for
/// sessions started without a display manager.
///
/// Everything here is a heuristic: desktop identifiers are free-form strings
/// and users override them. Treat the results as hints for defaults, never as
/// hard gates.
class DesktopEnvironment {
  /// Creates a description from an explicit environment map.
  ///
  /// [isFlatpak] defaults to checking `FLATPAK_ID` in [environment]; pass it
  /// explicitly to account for `/.flatpak-info` (see [DesktopEnvironment.current]).
  factory DesktopEnvironment.fromEnvironment(
    Map<String, String> environment, {
    bool? isFlatpak,
  }) {
    final desktops = <String>[];
    void addAll(String? value) {
      if (value == null) return;
      for (final part in value.split(RegExp('[:;]'))) {
        final token = _normalize(part);
        if (token.isNotEmpty && !desktops.contains(token)) desktops.add(token);
      }
    }

    addAll(environment['XDG_CURRENT_DESKTOP']);
    addAll(environment['XDG_SESSION_DESKTOP']);
    addAll(_sessionBaseName(environment['DESKTOP_SESSION']));

    // Compositors started from a TTY often leave XDG_CURRENT_DESKTOP unset;
    // their IPC sockets are a reliable fallback.
    if (environment.containsKey('HYPRLAND_INSTANCE_SIGNATURE')) {
      addAll('hyprland');
    }
    if (environment.containsKey('NIRI_SOCKET')) addAll('niri');
    if (environment.containsKey('SWAYSOCK')) addAll('sway');
    if (environment.containsKey('I3SOCK')) addAll('i3');

    return DesktopEnvironment._(
      desktops: List.unmodifiable(desktops),
      sessionType: _parseSessionType(environment),
      isFlatpak: isFlatpak ?? environment.containsKey('FLATPAK_ID'),
      hasUwsm: environment.keys.any((k) => k.startsWith('UWSM_')),
    );
  }

  DesktopEnvironment._({
    required this.desktops,
    required this.sessionType,
    required this.isFlatpak,
    required this.hasUwsm,
  });

  /// The environment of the current process.
  factory DesktopEnvironment.current() => DesktopEnvironment.fromEnvironment(
    Platform.environment,
    isFlatpak:
        Platform.environment.containsKey('FLATPAK_ID') ||
        File('/.flatpak-info').existsSync(),
  );

  /// Normalised (lower-case, `x-` prefix stripped) desktop identifiers, most
  /// specific first, e.g. `['hyprland']`, `['ubuntu', 'gnome']`, `['kde']`.
  final List<String> desktops;

  /// Wayland, X11 or unknown.
  final DesktopSessionType sessionType;

  /// Whether the app runs inside a Flatpak sandbox.
  final bool isFlatpak;

  /// Whether the session was started by uwsm (systemd-managed Wayland
  /// session), which runs XDG autostart entries even on bare compositors.
  final bool hasUwsm;

  bool get isWayland => sessionType == DesktopSessionType.wayland;
  bool get isX11 => sessionType == DesktopSessionType.x11;

  /// The most specific desktop identifier, or `null` when none is set.
  String? get primary => desktops.isEmpty ? null : desktops.first;

  bool _has(Iterable<String> names) => desktops.any(names.contains);

  bool get isKde => _has(const ['kde', 'plasma', 'plasmawayland']);
  bool get isGnome => _has(const ['gnome', 'gnome-classic', 'gnome-flashback']);
  bool get isXfce => _has(const ['xfce', 'xfce4']);
  bool get isCinnamon => _has(const ['cinnamon', 'x-cinnamon']);
  bool get isMate => _has(const ['mate']);
  bool get isLxqt => _has(const ['lxqt']);
  bool get isBudgie => _has(const ['budgie', 'budgie-desktop']);
  bool get isPantheon => _has(const ['pantheon']);
  bool get isCosmic => _has(const ['cosmic']);
  bool get isUnity => _has(const ['unity']);
  bool get isDeepin => _has(const ['deepin', 'dde']);
  bool get isHyprland => _has(const ['hyprland']);
  bool get isSway => _has(const ['sway']);
  bool get isNiri => _has(const ['niri']);
  bool get isRiver => _has(const ['river']);
  bool get isI3 => _has(const ['i3']);

  /// Full desktop environments that ship their own session manager and run
  /// XDG autostart entries themselves.
  bool get isFullDesktop =>
      isKde ||
      isGnome ||
      isXfce ||
      isCinnamon ||
      isMate ||
      isLxqt ||
      isBudgie ||
      isPantheon ||
      isCosmic ||
      isUnity ||
      isDeepin ||
      _has(const ['lxde', 'enlightenment', 'trinity', 'ukui', 'gnome-mobile']);

  /// Tiling window managers / compositors, where windows have no minimise or
  /// maximise in the usual sense and title-bar buttons look out of place.
  bool get isTilingCompositor => !isFullDesktop && _has(_tiling);

  static const _tiling = {
    'hyprland',
    'sway',
    'swayfx',
    'niri',
    'river',
    'i3',
    'i3wm',
    'bspwm',
    'qtile',
    'dwm',
    'dwl',
    'herbstluftwm',
    'awesome',
    'xmonad',
    'spectrwm',
    'leftwm',
    'notion',
    'ratpoison',
    'stumpwm',
    'mango',
    'maomaowm',
    'jay',
    'miracle-wm',
    'pinnacle',
    'scroll',
    'velox',
    'japokwm',
    'cagebreak',
  };

  /// Whether the window manager normally draws window frames itself (or, for
  /// tiling compositors, wants no client-side frame at all), so a custom
  /// client-side title bar with caption buttons is not the native look.
  ///
  /// GNOME-family desktops (GNOME, Budgie, Pantheon, COSMIC) expect
  /// client-side decorations and return false. Unknown Wayland compositors
  /// return false; unknown X11 window managers return true.
  bool get prefersServerSideDecorations {
    if (isGnome || isBudgie || isPantheon || isCosmic) return false;
    if (isTilingCompositor) return true;
    if (isKde || isXfce || isCinnamon || isMate || isLxqt || isDeepin) {
      return true;
    }
    if (_has(const ['labwc', 'wayfire', 'openbox', 'fluxbox', 'icewm'])) {
      return true;
    }
    return isX11;
  }

  /// Whether a system tray (StatusNotifierItem host) is likely without extra
  /// setup. GNOME needs the AppIndicator extension, so this is false there;
  /// always confirm with `StatusNotifierTray.isAvailable()`.
  bool get trayExpected => !isGnome;

  @override
  String toString() =>
      'DesktopEnvironment(desktops: $desktops, session: ${sessionType.name}, '
      'flatpak: $isFlatpak, tiling: $isTilingCompositor)';

  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('x-')) s = s.substring(2);
    return s;
  }

  /// `DESKTOP_SESSION` is sometimes a path to the session file
  /// (`/usr/share/xsessions/plasma`), sometimes a name like `plasmawayland`
  /// or `hyprland-uwsm`.
  static String? _sessionBaseName(String? value) {
    if (value == null || value.isEmpty) return null;
    var base = value.split('/').last;
    if (base.endsWith('.desktop')) {
      base = base.substring(0, base.length - '.desktop'.length);
    }
    if (base.endsWith('-uwsm')) base = base.substring(0, base.length - 5);
    if (base == 'plasmawayland' || base == 'plasmax11') base = 'kde';
    if (base == 'ubuntu' || base == 'ubuntu-wayland') base = 'gnome';
    return base;
  }

  static DesktopSessionType _parseSessionType(Map<String, String> env) {
    switch (env['XDG_SESSION_TYPE']?.toLowerCase()) {
      case 'wayland':
        return DesktopSessionType.wayland;
      case 'x11':
        return DesktopSessionType.x11;
      case 'tty':
        // A compositor launched from a TTY keeps the logind session type.
        if (env.containsKey('WAYLAND_DISPLAY')) {
          return DesktopSessionType.wayland;
        }
        if (env.containsKey('DISPLAY')) return DesktopSessionType.x11;
        return DesktopSessionType.tty;
    }
    if (env.containsKey('WAYLAND_DISPLAY')) return DesktopSessionType.wayland;
    if (env.containsKey('DISPLAY')) return DesktopSessionType.x11;
    return DesktopSessionType.unknown;
  }
}
