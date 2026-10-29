import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:plume_linux/plume_linux.dart';

import '../../config.dart';
import '../../services/avatar_renderer.dart';
import '../../services/desktop.dart';
import '../../services/window_frame.dart';
import 'window_channel.dart';

final _log = Logger('plume.linux');

/// [DesktopIntegration] for Linux: GTK window channel, StatusNotifierItem
/// tray, freedesktop notifications, XDG portal appearance, XDG autostart,
/// `mailto:` handling via mimeapps.list, and logind/NetworkManager wake-ups.
final class LinuxDesktop implements DesktopIntegration {
  LinuxDesktop({required this.startHidden});

  /// Started with `--background`: the runner keeps the window unmapped.
  final bool startHidden;

  final _env = DesktopEnvironment.current();
  late final _window = LinuxWindow(environment: _env);
  late final _frame = _LinuxWindowFrame(_window, tiling: _env.isTilingCompositor);
  final _notifications = DesktopNotifications(appName: AppConfig.appName, desktopEntry: AppConfig.appId);
  final _tray = StatusNotifierTray();
  final _portal = PortalAppearance();
  final _sleep = SleepMonitor();
  final _connectivity = ConnectivityMonitor();
  late final _autostart = Autostart(appId: AppConfig.appId, appName: AppConfig.appName, iconName: AppConfig.appId);
  final _mimeApps = MimeApps();

  final _events = StreamController<DesktopEvent>.broadcast();
  final _appearance = StreamController<SystemAppearance>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  /// What each posted notification refers to, for its action buttons.
  final _posted = <int, MailNotification>{};

  SystemAppearance _current = const SystemAppearance();
  Color? _shellAccent;
  bool _trayRegistered = false;
  bool _autostartHonored = false;
  int _unread = -1;
  bool _online = true;

  @override
  Stream<DesktopEvent> get events => _events.stream;

  @override
  WindowFrame get windowFrame => _frame;

  @override
  bool get hasTray => _trayRegistered;

  @override
  bool get autostartSupported => _autostartHonored || _env.isFlatpak;

  @override
  SystemAppearance get appearance => _current;

  @override
  Stream<SystemAppearance> get appearanceChanges => _appearance.stream;

  @override
  Future<void> start() async {
    _subs
      ..add(_window.closeRequested.listen((_) => _events.add(const CloseRequestedEvent())))
      ..add(_window.activated.listen((a) => _events.add(ShowWindowEvent(activationToken: a.activationToken))))
      ..add(_window.openUris.listen((uris) {
        for (final uri in uris) {
          _events.add(OpenUriEvent(uri));
        }
      }))
      ..add(_window.stateChanged.listen((s) {
        _events.add(WindowStateEvent(visible: s.visible, focused: s.focused, maximized: s.maximized));
        _frame._update(maximized: s.maximized);
      }))
      ..add(_window.decorationLayoutChanged.listen((layout) => _frame._update(layout: layout)));

    await Future.wait([
      _window.decorationLayout().then((layout) => _frame._update(layout: layout)),
      _startNotifications(),
      _startPortal(),
      _startTray(),
      _startWakeups(),
      _probeAutostart(),
    ]);
    if (startHidden) _events.add(const WindowStateEvent(visible: false, focused: false, maximized: false));
  }

  Future<void> _startNotifications() async {
    try {
      final ok = await _notifications.initialize();
      if (!ok) _log.warning('No notification server on the session bus; new-mail alerts are off');
      _subs.add(_notifications.events.listen(_onNotificationEvent));
    } catch (e) {
      _log.warning('Notifications unavailable: $e');
    }
  }

  Future<void> _startPortal() async {
    _startShellAppearance();
    try {
      if (await _portal.initialize()) {
        _current = _convert(_portal.current);
        _subs.add(_portal.changes.listen((s) {
          _current = _convert(s);
          _appearance.add(_current);
        }));
      } else if (_shellAccent != null) {
        _current = SystemAppearance(accent: _shellAccent);
      }
    } catch (e) {
      _log.info('Appearance portal unavailable: $e');
      if (_shellAccent != null) {
        _current = SystemAppearance(accent: _shellAccent);
      }
    }
  }

  SystemAppearance _convert(AppearanceSettings s) => SystemAppearance(
        brightness: switch (s.colorScheme) {
          ColorSchemePreference.dark => Brightness.dark,
          ColorSchemePreference.light => Brightness.light,
          ColorSchemePreference.noPreference => null,
        },
        accent: s.accentColor == null ? _shellAccent : Color(s.accentColor!.toArgb32()),
        highContrast: s.contrast == ContrastPreference.high,
      );

  void _startShellAppearance() {
    _shellAccent = _resolveShellAccent();
    final dir = _shellAccentDir();
    if (dir == null || !dir.existsSync()) return;

    try {
      _subs.add(dir.watch().listen((event) {
        final name = p.basename(event.path);
        if (name == 'color.txt' || name == 'colors.json') {
          final next = _resolveShellAccent();
          if (next != _shellAccent) {
            _shellAccent = next;
            _current = _convert(_portal.current);
            _appearance.add(_current);
          }
        }
      }));
    } catch (e) {
      _log.fine('Cannot watch shell accent color directory: $e');
    }
  }

  Directory? _shellAccentDir() {
    final stateHome = Platform.environment['XDG_STATE_HOME'] ??
        (Platform.environment['HOME'] != null
            ? p.join(Platform.environment['HOME']!, '.local', 'state')
            : null);
    if (stateHome != null) {
      return Directory(p.join(stateHome, 'quickshell', 'user', 'generated'));
    }
    return null;
  }

  Color? _resolveShellAccent() {
    final dir = _shellAccentDir();
    if (dir != null && dir.existsSync()) {
      final color = _resolveShellAccentFromDir(dir);
      if (color != null) return color;
    }

    final cacheHome = Platform.environment['XDG_CACHE_HOME'] ??
        (Platform.environment['HOME'] != null
            ? p.join(Platform.environment['HOME']!, '.cache')
            : null);
    if (cacheHome != null) {
      final walFile = File(p.join(cacheHome, 'wal', 'colors.json'));
      if (walFile.existsSync()) {
        try {
          final map = jsonDecode(walFile.readAsStringSync()) as Map<String, dynamic>;
          final colors = map['colors'] as Map<String, dynamic>?;
          final color1 = colors?['color1'] as String?;
          if (color1 != null) {
            final color = _parseColor(color1.trim());
            if (color != null) return color;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  @visibleForTesting
  static Color? resolveShellAccentFromDir(Directory dir) => _resolveShellAccentFromDir(dir);

  static Color? _resolveShellAccentFromDir(Directory dir) {
    final colorTxt = File(p.join(dir.path, 'color.txt'));
    if (colorTxt.existsSync()) {
      try {
        final text = colorTxt.readAsStringSync().trim();
        final color = _parseColor(text);
        if (color != null) return color;
      } catch (_) {}
    }

    final colorsJson = File(p.join(dir.path, 'colors.json'));
    if (colorsJson.existsSync()) {
      try {
        final map = jsonDecode(colorsJson.readAsStringSync()) as Map<String, dynamic>;
        final primary = map['primary'] as String?;
        if (primary != null) {
          final color = _parseColor(primary.trim());
          if (color != null) return color;
        }
      } catch (_) {}
    }
    return null;
  }

  @visibleForTesting
  static Color? parseColor(String text) => _parseColor(text);

  static Color? _parseColor(String text) {
    try {
      final hex = text.startsWith('#') ? text.substring(1) : text;
      if (hex.length == 6) {
        final val = int.tryParse(hex, radix: 16);
        if (val != null) return Color(0xFF000000 | val);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _startTray() async {
    try {
      _trayRegistered = await _tray.start(TrayConfig(
        id: AppConfig.appId,
        title: AppConfig.appName,
        // Use the supplied pixmaps so hosts also display the unread badge.
        iconPixmaps: await _trayPixmaps(0),
        tooltipTitle: AppConfig.appName,
        menu: _menu,
      ));
      _subs.add(_tray.events.listen(_onTrayEvent));
    } catch (e) {
      _log.warning('Tray unavailable: $e');
    }
  }

  static const _menu = [
    TrayMenuItem(id: 'open', label: 'Open Plume'),
    TrayMenuItem(id: 'compose', label: 'Compose'),
    TrayMenuItem.separator(),
    TrayMenuItem(id: 'sync', label: 'Check for mail'),
    TrayMenuItem.separator(),
    TrayMenuItem(id: 'quit', label: 'Quit Plume'),
  ];

  void _onTrayEvent(TrayEvent event) {
    switch (event) {
      case TrayActivated(:final activationToken):
        _events.add(ShowWindowEvent(activationToken: activationToken, toggle: true));
      case TraySecondaryActivated(:final activationToken):
        _events.add(ComposeEvent(activationToken: activationToken));
      case TrayMenuItemSelected(:final id, :final activationToken):
        _events.add(switch (id) {
          'compose' => ComposeEvent(activationToken: activationToken),
          'sync' => const SyncNowEvent(),
          'quit' => const QuitEvent(),
          _ => ShowWindowEvent(activationToken: activationToken),
        });
      case TrayAvailabilityChanged(:final available):
        _trayRegistered = available;
      default:
        break;
    }
  }

  Future<void> _startWakeups() async {
    try {
      if (await _sleep.start()) _subs.add(_sleep.resumed.listen((_) => _events.add(const WakeEvent())));
    } catch (e) {
      _log.fine('Sleep monitor unavailable: $e');
    }
    try {
      final status = await _connectivity.start();
      if (status != null) {
        _online = status.isOnline;
        _subs.add(_connectivity.changes.listen((s) {
          if (s.isOnline && !_online) _events.add(const WakeEvent());
          _online = s.isOnline;
        }));
      }
    } catch (e) {
      _log.fine('Connectivity monitor unavailable: $e');
    }
  }

  Future<void> _probeAutostart() async {
    _autostartHonored = _autostart.compositorHonorsXdgAutostart;
    try {
      _autostartHonored = await _autostart.probeXdgAutostartSupport();
    } catch (_) {}
  }

  // Window ---------------------------------------------------------------------

  @override
  Future<void> showWindow({String? activationToken}) => _window.show(activationToken: activationToken);
  @override
  Future<void> hideWindow() => _window.hide();
  @override
  Future<bool> isWindowVisible() => _window.isVisible();
  @override
  Future<void> setPreventClose(bool prevent) => _window.setPreventClose(prevent);

  @override
  Future<void> quit() async {
    await dispose();
    await _window.quit();
  }

  // Tray badge -------------------------------------------------------------------

  @override
  Future<void> setUnreadCount(int count) async {
    if (count == _unread) return;
    _unread = count;
    if (!_trayRegistered) return;
    try {
      await _tray.setIcon(await _trayPixmaps(count));
      await _tray.setTooltip(AppConfig.appName, count == 0 ? 'No unread mail' : '$count unread');
    } catch (e) {
      _log.fine('Tray update failed: $e');
    }
  }

  static Future<List<TrayPixmap>> _trayPixmaps(int unread) async {
    return [
      for (final size in const [22, 32, 48, 64])
        TrayPixmap.fromRgba(
          await renderTrayIconRgba(
            size: size,
            unread: unread,
            badge: const Color(0xFFE5484D),
          ),
          size,
          size,
        ),
    ];
  }

  // Notifications ----------------------------------------------------------------

  @override
  Future<void> notify(MailNotification n) async {
    if (!_notifications.isAvailable) return;
    final single = n.threadId != null;
    final id = await _notifications.show(NotificationRequest(
      summary: n.title,
      body: n.body,
      image: n.avatarRgba == null
          ? null
          : NotificationImage.rgba(Uint8List.fromList(n.avatarRgba!), width: n.avatarSize, height: n.avatarSize),
      appIcon: AppConfig.appId,
      actions: [
        const NotificationAction('default', 'Open'),
        if (single) const NotificationAction('archive', 'Archive'),
        NotificationAction('read', single ? 'Mark as read' : 'Mark all as read'),
      ],
      category: 'email.arrived',
      urgency: NotificationUrgency.normal,
      desktopEntry: AppConfig.appId,
      soundName: n.sound ? 'message-new-email' : null,
      suppressSound: !n.sound,
    ));
    _posted[id] = n;
    if (_posted.length > 200) _posted.remove(_posted.keys.first);
  }

  void _onNotificationEvent(NotificationEvent event) {
    switch (event) {
      case NotificationActionInvoked(:final id, :final key, :final activationToken):
        final n = _posted.remove(id);
        if (n == null) {
          _events.add(ShowWindowEvent(activationToken: activationToken));
          return;
        }
        if (key == 'default') {
          _events.add(n.threadId != null
              ? OpenThreadEvent(n.accountId, n.threadId!, activationToken: activationToken)
              : ShowWindowEvent(activationToken: activationToken));
        } else {
          _events.add(NotificationActionEvent(key, n.accountId, n.messageIds, n.threadIds));
          unawaited(_notifications.close(id).catchError((_) {}));
        }
      case NotificationClosed(:final id):
        _posted.remove(id);
      default:
        break;
    }
  }

  // Autostart ----------------------------------------------------------------------

  @override
  Future<bool> isAutostartEnabled() async {
    try {
      return await _autostart.isEnabled();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setAutostart(bool enabled) => enabled ? _autostart.enable() : _autostart.disable();

  // Default mail app -----------------------------------------------------------------

  static const _desktopId = '${AppConfig.appId}.desktop';

  @override
  Future<List<String>> takeOpenUris() => _window.takeOpenUris();

  @override
  Future<DefaultMailAppStatus> defaultMailAppStatus() async {
    // The sandbox sees neither the host's mimeapps.list nor its launchers.
    if (_env.isFlatpak) return DefaultMailAppStatus.unsupported;
    try {
      return switch (_mimeApps.handlerEntryStatus(_desktopId, mailtoSchemeHandler)) {
        HandlerEntryStatus.missing => DefaultMailAppStatus.notInstalled,
        HandlerEntryStatus.missingMimeType => DefaultMailAppStatus.outdatedEntry,
        HandlerEntryStatus.ok => _mimeApps.defaultFor(mailtoSchemeHandler) == _desktopId
            ? DefaultMailAppStatus.isDefault
            : DefaultMailAppStatus.notDefault,
      };
    } catch (e) {
      _log.warning('Reading default applications failed: $e');
      return DefaultMailAppStatus.unsupported;
    }
  }

  @override
  Future<void> makeDefaultMailApp() => _mimeApps.setDefault(mailtoSchemeHandler, _desktopId);

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    await Future.wait<void>([
      _tray.dispose().catchError((_) {}),
      _notifications.dispose().catchError((_) {}),
    ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
  }
}

/// [WindowFrame] over the GTK runner's window channel. [LinuxDesktop] feeds
/// it the window's state.
final class _LinuxWindowFrame extends WindowFrame {
  _LinuxWindowFrame(this._window, {required bool tiling}) : defaultStyle = tiling ? TitleBar.none : TitleBar.plume;

  final LinuxWindow _window;

  @override
  final TitleBar defaultStyle;

  bool _maximized = false;
  var _buttons = parseDecorationLayout('');

  @override
  bool get maximized => _maximized;
  @override
  List<WindowButton> get leading => _buttons.$1;
  @override
  List<WindowButton> get trailing => _buttons.$2;

  @override
  Future<void> apply(TitleBar style) => _window.setSystemTitleBar(style == TitleBar.system);
  @override
  Future<void> startMove() => _window.startMove();
  @override
  Future<void> showMenu() => _window.showWindowMenu();
  @override
  Future<void> minimize() => _window.minimize();
  @override
  Future<void> toggleMaximize() => _window.toggleMaximize();

  void _update({bool? maximized, String? layout}) {
    final buttons = layout == null ? _buttons : parseDecorationLayout(layout);
    if ((maximized ?? _maximized) == _maximized &&
        listEquals(buttons.$1, _buttons.$1) &&
        listEquals(buttons.$2, _buttons.$2)) {
      return;
    }
    _maximized = maximized ?? _maximized;
    _buttons = buttons;
    notifyListeners();
  }
}

/// Splits a GTK decoration layout such as `icon:minimize,maximize,close` into
/// the window buttons before the title and those after it. Entries Plume has
/// no button for (icon, menu, appmenu, spacer) are skipped; an empty layout
/// is GTK's default.
@visibleForTesting
(List<WindowButton>, List<WindowButton>) parseDecorationLayout(String layout) {
  List<WindowButton> side(String names) => [
        for (final name in names.split(',')) ?WindowButton.values.asNameMap()[name.trim()],
      ];
  final sides = (layout.trim().isEmpty ? 'menu:minimize,maximize,close' : layout).split(':');
  return (side(sides.first), sides.length > 1 ? side(sides[1]) : const []);
}

/// Whether the Linux integration should be used (not under `flutter test`).
bool get linuxDesktopSupported => Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST');
