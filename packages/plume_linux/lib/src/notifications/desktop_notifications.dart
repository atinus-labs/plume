import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

import '../dbus/bus.dart';
import 'notification_request.dart';

final _log = Logger('plume_linux.notifications');

/// `GetServerInformation` result.
class NotificationServerInfo {
  const NotificationServerInfo({
    required this.name,
    required this.vendor,
    required this.version,
    required this.specVersion,
  });

  final String name;
  final String vendor;
  final String version;
  final String specVersion;

  @override
  String toString() => [
    name,
    if (version.isNotEmpty) version,
    '($vendor, spec $specVersion)',
  ].join(' ');
}

/// Why a notification was closed (`NotificationClosed` reason).
enum NotificationCloseReason {
  expired(1),
  dismissed(2),
  closedByCall(3),
  undefined(4);

  const NotificationCloseReason(this.value);
  final int value;

  static NotificationCloseReason fromValue(int v) => values.firstWhere(
    (r) => r.value == v,
    orElse: () => NotificationCloseReason.undefined,
  );
}

/// Events for notifications created by this [DesktopNotifications] instance.
sealed class NotificationEvent {
  const NotificationEvent(this.id);
  final int id;
}

/// An action button (or the body, for key `default`) was invoked.
///
/// [activationToken] is the XDG activation token (Wayland) or startup id
/// (X11) the server sent just before, if any; pass it to the window's
/// `show(activationToken:)` so focus is granted.
final class NotificationActionInvoked extends NotificationEvent {
  const NotificationActionInvoked(super.id, this.key, {this.activationToken});
  final String key;
  final String? activationToken;

  @override
  String toString() =>
      'NotificationActionInvoked($id, $key, token: $activationToken)';
}

final class NotificationClosed extends NotificationEvent {
  const NotificationClosed(super.id, this.reason);
  final NotificationCloseReason reason;

  @override
  String toString() => 'NotificationClosed($id, ${reason.name})';
}

/// KDE inline reply text.
final class NotificationReplied extends NotificationEvent {
  const NotificationReplied(super.id, this.text);
  final String text;

  @override
  String toString() => 'NotificationReplied($id, ${text.length} chars)';
}

/// Thrown by [DesktopNotifications.show] when no notification server is
/// reachable.
class NotificationsUnavailableException implements Exception {
  const NotificationsUnavailableException([this.message = '']);
  final String message;

  @override
  String toString() => 'NotificationsUnavailableException: $message';
}

/// Client for `org.freedesktop.Notifications`.
///
/// ```dart
/// final notifications = DesktopNotifications();
/// if (await notifications.initialize()) {
///   final id = await notifications.show(NotificationRequest(
///     summary: 'Ada Lovelace',
///     body: 'Re: Analytical engine <draft>',
///     category: NotificationCategories.emailArrived,
///     actions: [NotificationAction.byDefault(), NotificationAction('archive', 'Archive')],
///   ));
/// }
/// notifications.events.listen(...);
/// ```
///
/// Only signals for ids returned by [show] are surfaced. If the server
/// restarts, tracked notifications are reported as closed
/// ([NotificationCloseReason.undefined]) and capabilities are re-read when a
/// new server appears.
class DesktopNotifications {
  DesktopNotifications({
    DBusClient? bus,
    this.appName = 'Plume',
    this.desktopEntry = 'org.atinus.plume',
    this.callTimeout = defaultCallTimeout,
  }) : _bus = BusHandle.session(bus);

  static const busName = 'org.freedesktop.Notifications';
  static const interfaceName = 'org.freedesktop.Notifications';
  static final objectPath = DBusObjectPath('/org/freedesktop/Notifications');

  /// `app_name` sent with every notification.
  final String appName;

  /// Default `desktop-entry` hint (without `.desktop`).
  final String desktopEntry;

  final Duration callTimeout;

  /// How many live notification ids are tracked for signal filtering.
  static const maxTrackedIds = 1024;

  final BusHandle _bus;
  final _events = StreamController<NotificationEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Ids created by this instance and not yet closed.
  final _ids = <int>{};

  /// Activation tokens received ahead of their `ActionInvoked`.
  final _tokens = <int, String>{};

  /// Signals for ids we don't know yet, buffered while a `Notify` reply is
  /// in flight (a signal can overtake the reply's async continuation).
  final _early = <DBusSignal>[];
  int _inFlight = 0;

  Future<bool>? _init;
  bool _available = false;
  bool _disposed = false;
  Set<String> _capabilities = const {};
  NotificationServerInfo? _serverInfo;

  /// Whether a notification server is reachable (after [initialize]).
  bool get isAvailable => _available;

  /// Server capabilities (empty when unavailable).
  Set<String> get capabilities => _capabilities;

  /// Server identity, or `null` when unavailable.
  NotificationServerInfo? get serverInfo => _serverInfo;

  bool hasCapability(String capability) => _capabilities.contains(capability);
  bool get supportsActions => hasCapability(NotificationCapabilities.actions);
  bool get supportsBodyMarkup =>
      hasCapability(NotificationCapabilities.bodyMarkup);
  bool get supportsPersistence =>
      hasCapability(NotificationCapabilities.persistence);
  bool get supportsInlineReply =>
      hasCapability(NotificationCapabilities.inlineReply);

  /// Notification events for ids created by this instance.
  Stream<NotificationEvent> get events => _events.stream;

  /// Connects, subscribes to signals and reads capabilities. Safe to call
  /// repeatedly; returns [isAvailable]. Never throws.
  Future<bool> initialize() => _init ??= _initialize();

  Future<bool> _initialize() async {
    if (!await _bus.connect(timeout: callTimeout)) return false;
    final client = _bus.client;

    Stream<DBusSignal> signal(String name, String signature) =>
        DBusSignalStream(
          client,
          sender: busName,
          interface: interfaceName,
          name: name,
          path: objectPath,
          signature: DBusSignature(signature),
        );

    _subscriptions
      ..add(listenSignals(signal('ActionInvoked', 'us'), _onSignal, _log))
      ..add(listenSignals(signal('NotificationClosed', 'uu'), _onSignal, _log))
      ..add(listenSignals(signal('ActivationToken', 'us'), _onSignal, _log))
      ..add(listenSignals(signal('NotificationReplied', 'us'), _onSignal, _log))
      ..add(
        client.nameOwnerChanged
            .where((e) => e.name == busName)
            .listen(_onOwnerChanged),
      );

    await _probe();
    return _available;
  }

  Future<void> _probe() async {
    if (!await isNameAvailable(_bus.client, busName, timeout: callTimeout)) {
      _setUnavailable('no $busName on the session bus');
      return;
    }
    try {
      final caps = await _call('GetCapabilities', signature: 'as');
      final info = await _call('GetServerInformation', signature: 'ssss');
      final v = info.returnValues;
      _capabilities = Set.unmodifiable(caps.returnValues[0].asStringArray());
      _serverInfo = NotificationServerInfo(
        name: v[0].asString(),
        vendor: v[1].asString(),
        version: v[2].asString(),
        specVersion: v[3].asString(),
      );
      _available = true;
      _log.info('Notification server: $_serverInfo, caps: $_capabilities');
    } catch (e) {
      _setUnavailable('probe failed: $e');
    }
  }

  void _setUnavailable(String why) {
    if (_available) _log.info('Notifications unavailable: $why');
    _available = false;
    _capabilities = const {};
    _serverInfo = null;
  }

  void _onOwnerChanged(DBusNameOwnerChangedEvent e) {
    if (_disposed) return;
    if (e.oldOwner != null) {
      // The old server's notifications are gone with it.
      for (final id in _ids.toList()) {
        _emit(NotificationClosed(id, NotificationCloseReason.undefined));
      }
      _ids.clear();
      _tokens.clear();
    }
    if (e.newOwner == null) {
      _setUnavailable('server left the bus');
    } else {
      unawaited(_probe());
    }
  }

  Future<DBusMethodSuccessResponse> _call(
    String method, {
    List<DBusValue> values = const [],
    String? signature,
  }) => _bus.client
      .callMethod(
        destination: busName,
        path: objectPath,
        interface: interfaceName,
        name: method,
        values: values,
        replySignature: signature == null ? null : DBusSignature(signature),
      )
      .timeout(callTimeout);

  /// Shows (or replaces) a notification and returns its id.
  ///
  /// Throws [NotificationsUnavailableException] if no server is reachable, and
  /// rethrows D-Bus errors from the server.
  Future<int> show(NotificationRequest request) async {
    if (_disposed) throw StateError('DesktopNotifications was disposed');
    await initialize();
    if (!_available) {
      // A server may have appeared since; one cheap re-probe.
      if (await _bus.connect()) await _probe();
      if (!_available) throw const NotificationsUnavailableException();
    }
    final args = NotifyArguments.build(
      request,
      capabilities: _capabilities,
      appName: appName,
      defaultDesktopEntry: desktopEntry,
      specVersion: _serverInfo?.specVersion ?? '1.2',
    );
    _inFlight++;
    try {
      final reply = await _call(
        'Notify',
        values: args.toDBus(),
        signature: 'u',
      );
      final id = reply.returnValues[0].asUint32();
      _ids.add(id);
      // Servers that keep notifications in history may never report them
      // closed; bound the set (oldest first) for long-running sessions.
      if (_ids.length > maxTrackedIds) _ids.remove(_ids.first);
      _replayEarly(id);
      return id;
    } on TimeoutException {
      throw const NotificationsUnavailableException('Notify timed out');
    } finally {
      _inFlight--;
      if (_inFlight == 0) _early.clear();
    }
  }

  /// Closes a notification created by this instance.
  Future<void> close(int id) async {
    if (!_available || _disposed) return;
    try {
      await _call('CloseNotification', values: [DBusUint32(id)]);
    } catch (e) {
      _log.fine('CloseNotification($id) failed: $e');
    }
  }

  void _onSignal(DBusSignal s) {
    if (_disposed) return;
    final id = s.values[0].asUint32();
    if (!_ids.contains(id)) {
      if (_inFlight > 0 && _early.length < 64) _early.add(s);
      return;
    }
    switch (s.name) {
      case 'ActivationToken':
        _tokens[id] = s.values[1].asString();
      case 'ActionInvoked':
        _emit(
          NotificationActionInvoked(
            id,
            s.values[1].asString(),
            activationToken: _tokens.remove(id),
          ),
        );
      case 'NotificationReplied':
        _emit(NotificationReplied(id, s.values[1].asString()));
      case 'NotificationClosed':
        _ids.remove(id);
        _tokens.remove(id);
        _emit(
          NotificationClosed(
            id,
            NotificationCloseReason.fromValue(s.values[1].asUint32()),
          ),
        );
    }
  }

  void _replayEarly(int id) {
    if (_early.isEmpty) return;
    final mine = _early.where((s) => s.values[0].asUint32() == id).toList();
    _early.removeWhere(mine.contains);
    mine.forEach(_onSignal);
  }

  void _emit(NotificationEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  /// Stops listening and closes the connection if it was created here.
  /// Notifications already shown stay on screen.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _events.close();
    await _bus.close();
  }
}
