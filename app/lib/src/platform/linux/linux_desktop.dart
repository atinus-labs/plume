import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:logging/logging.dart';
import 'package:plume_linux/plume_linux.dart';

import '../../config.dart';
import '../../services/avatar_renderer.dart';
import '../../services/desktop.dart';
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
  bool _trayRegistered = false;
  bool _autostartHonored = false;
  int _unread = -1;
  bool _online = true;

  @override
  Stream<DesktopEvent> get events => _events.stream;

  @override
  bool get drawsWindowControls => !_env.isTilingCompositor;

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
      ..add(_window.stateChanged.listen((s) => _events.add(
          WindowStateEvent(visible: s.visible, focused: s.focused, maximized: s.maximized))));

    await Future.wait([
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
    try {
      if (await _portal.initialize()) {
        _current = _convert(_portal.current);
        _subs.add(_portal.changes.listen((s) {
          _current = _convert(s);
          _appearance.add(_current);
        }));
      }
    } catch (e) {
      _log.info('Appearance portal unavailable: $e');
    }
  }

  static SystemAppearance _convert(AppearanceSettings s) => SystemAppearance(
        brightness: switch (s.colorScheme) {
          ColorSchemePreference.dark => Brightness.dark,
          ColorSchemePreference.light => Brightness.light,
          ColorSchemePreference.noPreference => null,
        },
        accent: s.accentColor == null ? null : Color(s.accentColor!.toArgb32()),
        highContrast: s.contrast == ContrastPreference.high,
      );

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
  Future<void> minimize() => _window.minimize();
  @override
  Future<void> toggleMaximize() => _window.toggleMaximize();
  @override
  Future<void> startWindowMove() => _window.startMove();
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

/// Whether the Linux integration should be used (not under `flutter test`).
bool get linuxDesktopSupported => Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST');
