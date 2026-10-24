import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

import '../dbus/bus.dart';
import 'introspection.dart';
import 'tray_menu.dart';
import 'tray_pixmap.dart';

final _log = Logger('plume_linux.tray');

/// `Status` property values.
enum TrayStatus {
  /// Hidden by most hosts (or moved into an overflow area).
  passive('Passive'),
  active('Active'),

  /// Hosts highlight the item and show the attention icon if provided.
  needsAttention('NeedsAttention');

  const TrayStatus(this.dbusValue);
  final String dbusValue;
}

/// `Category` property values.
enum TrayCategory {
  applicationStatus('ApplicationStatus'),
  communications('Communications'),
  systemServices('SystemServices'),
  hardware('Hardware');

  const TrayCategory(this.dbusValue);
  final String dbusValue;
}

/// Initial tray state for [StatusNotifierTray.start].
class TrayConfig {
  const TrayConfig({
    this.id = 'org.atinus.plume',
    this.title = 'Plume',
    this.category = TrayCategory.communications,
    this.status = TrayStatus.active,
    this.iconName = '',
    this.iconPixmaps = const [],
    this.attentionIconName = '',
    this.attentionIconPixmaps = const [],
    this.iconThemePath = '',
    this.tooltipTitle,
    this.tooltipBody = '',
    this.menu = const [],
  });

  /// Stable identifier (`Id` property); hosts use it to remember placement.
  final String id;
  final String title;
  final TrayCategory category;
  final TrayStatus status;

  /// Themed icon name. Most hosts prefer it over pixmaps when it resolves.
  final String iconName;
  final List<TrayPixmap> iconPixmaps;
  final String attentionIconName;
  final List<TrayPixmap> attentionIconPixmaps;

  /// Extra icon theme directory for [iconName] lookups.
  final String iconThemePath;

  /// Defaults to [title].
  final String? tooltipTitle;
  final String tooltipBody;
  final List<TrayMenuItem> menu;
}

/// Events from the tray host.
sealed class TrayEvent {
  const TrayEvent();
}

/// Primary click (usually left). Coordinates are screen positions as given
/// by the host (0,0 on Wayland hosts that don't know them).
final class TrayActivated extends TrayEvent {
  const TrayActivated(this.x, this.y, {this.activationToken});
  final int x;
  final int y;

  /// XDG activation token from `ProvideXdgActivationToken`, when the host
  /// supplies one (KDE Plasma does). Pass it to the window's `show`.
  final String? activationToken;

  @override
  String toString() => 'TrayActivated($x, $y, token: $activationToken)';
}

/// Secondary click (usually middle).
final class TraySecondaryActivated extends TrayEvent {
  const TraySecondaryActivated(this.x, this.y, {this.activationToken});
  final int x;
  final int y;
  final String? activationToken;

  @override
  String toString() => 'TraySecondaryActivated($x, $y)';
}

/// The host asked the app to show its own context menu. Rare: hosts show
/// the exported dbusmenu themselves.
final class TrayContextMenuRequested extends TrayEvent {
  const TrayContextMenuRequested(this.x, this.y);
  final int x;
  final int y;

  @override
  String toString() => 'TrayContextMenuRequested($x, $y)';
}

/// A menu entry was clicked; [id] is the [TrayMenuItem.id].
final class TrayMenuItemSelected extends TrayEvent {
  const TrayMenuItemSelected(this.id, {this.activationToken});
  final String id;
  final String? activationToken;

  @override
  String toString() => 'TrayMenuItemSelected($id)';
}

enum TrayScrollOrientation { vertical, horizontal }

final class TrayScrolled extends TrayEvent {
  const TrayScrolled(this.delta, this.orientation);
  final int delta;
  final TrayScrollOrientation orientation;

  @override
  String toString() => 'TrayScrolled($delta, ${orientation.name})';
}

/// The item became visible to a tray host (registered with a watcher that
/// has a host) or stopped being visible (watcher/host exited).
final class TrayAvailabilityChanged extends TrayEvent {
  const TrayAvailabilityChanged(this.available);
  final bool available;

  @override
  String toString() => 'TrayAvailabilityChanged($available)';
}

/// A pure-Dart StatusNotifierItem with a `com.canonical.dbusmenu` menu.
///
/// Owns `org.kde.StatusNotifierItem-<pid>-<n>`, exports `/StatusNotifierItem`
/// and `/MenuBar`, and registers with `org.kde.StatusNotifierWatcher`. When
/// the watcher restarts (e.g. the bar is reloaded) the item re-registers.
///
/// Works with KDE Plasma, GNOME + AppIndicator extension, XFCE, Cinnamon,
/// waybar, quickshell, ironbar, etc. Hosts that only support XEmbed need a
/// bridge such as `snixembed` or `xembedsniproxy`.
class StatusNotifierTray {
  StatusNotifierTray({DBusClient? bus, this.callTimeout = defaultCallTimeout})
    : _bus = BusHandle.session(bus);

  static const watcherName = 'org.kde.StatusNotifierWatcher';
  static const watcherInterface = 'org.kde.StatusNotifierWatcher';
  static const itemInterface = 'org.kde.StatusNotifierItem';
  static const menuInterface = 'com.canonical.dbusmenu';
  static final watcherPath = DBusObjectPath('/StatusNotifierWatcher');
  static final itemPath = DBusObjectPath('/StatusNotifierItem');
  static final menuPath = DBusObjectPath('/MenuBar');

  static int _counter = 0;

  final Duration callTimeout;
  final BusHandle _bus;
  final _events = StreamController<TrayEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _menu = DbusMenuModel();

  late _ItemState _state;
  _SniObject? _item;
  _MenuObject? _menuObject;
  String? _busName;
  bool _started = false;
  bool _disposed = false;
  bool _available = false;
  String? _pendingToken;
  Future<void> _registration = Future.value();

  /// Host events. Includes [TrayAvailabilityChanged].
  Stream<TrayEvent> get events => _events.stream;

  /// Whether the item is currently registered with a watcher that has a host.
  bool get isRegistered => _available;

  /// The owned bus name, once started.
  String? get busName => _busName;

  /// Whether a StatusNotifierWatcher with at least one host is running.
  /// Usable before [start].
  Future<bool> isAvailable() async {
    if (_disposed || !await _bus.connect(timeout: callTimeout)) return false;
    return _watcherHasHost();
  }

  /// Exports the item and registers it with the watcher.
  ///
  /// Returns false when there is no session bus, no watcher or no host. The
  /// item stays exported (unless there is no bus) and registers itself when a
  /// watcher appears later; watch for [TrayAvailabilityChanged]. Call
  /// [dispose] to remove the icon.
  Future<bool> start(TrayConfig config) async {
    if (_disposed) throw StateError('StatusNotifierTray was disposed');
    if (_started) throw StateError('StatusNotifierTray already started');
    _started = true;
    _state = _ItemState.fromConfig(config);
    _menu.update(config.menu);

    if (!await _bus.connect(timeout: callTimeout)) return false;
    final client = _bus.client;

    _item = _SniObject(this);
    _menuObject = _MenuObject(this);
    await client.registerObject(_item!);
    await client.registerObject(_menuObject!);

    _busName = await _acquireName(client);
    if (_busName == null) return false;

    _subscriptions
      ..add(
        client.nameOwnerChanged
            .where((e) => e.name == watcherName)
            .listen(_onWatcherOwnerChanged),
      )
      ..add(
        listenSignals(
          DBusSignalStream(
            client,
            sender: watcherName,
            interface: watcherInterface,
            name: 'StatusNotifierHostRegistered',
          ),
          (_) => _scheduleRegistration(),
          _log,
        ),
      )
      ..add(
        listenSignals(
          DBusSignalStream(
            client,
            sender: watcherName,
            interface: watcherInterface,
            name: 'StatusNotifierHostUnregistered',
          ),
          (_) => _scheduleRegistration(),
          _log,
        ),
      );

    _scheduleRegistration();
    await _registration;
    return _available;
  }

  Future<String?> _acquireName(DBusClient client) async {
    for (var attempt = 0; attempt < 16; attempt++) {
      final name = 'org.kde.StatusNotifierItem-$pid-${++_counter}';
      try {
        final reply = await client
            .requestName(name, flags: {DBusRequestNameFlag.doNotQueue})
            .timeout(callTimeout);
        if (reply == DBusRequestNameReply.primaryOwner ||
            reply == DBusRequestNameReply.alreadyOwner) {
          return name;
        }
      } catch (e) {
        _log.warning('RequestName($name) failed: $e');
        return null;
      }
    }
    return null;
  }

  void _onWatcherOwnerChanged(DBusNameOwnerChangedEvent e) {
    if (_disposed) return;
    if (e.newOwner == null) {
      _log.info('StatusNotifierWatcher left the bus');
      _setAvailable(false);
    } else {
      _log.info('StatusNotifierWatcher appeared (${e.newOwner}); registering');
      _scheduleRegistration(retry: true);
    }
  }

  /// Serialises (re-)registration attempts.
  void _scheduleRegistration({bool retry = false}) {
    _registration = _registration.then((_) => _register(retry: retry));
  }

  Future<void> _register({bool retry = false}) async {
    if (_disposed || _busName == null) return;
    final client = _bus.client;
    // A freshly started watcher may own its name before exporting its object.
    final attempts = retry ? 4 : 1;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(Duration(milliseconds: 250 * i));
      if (_disposed) return;
      if (!await isNameAvailable(
        client,
        watcherName,
        includeActivatable: false,
        timeout: callTimeout,
      )) {
        break;
      }
      try {
        await client
            .callMethod(
              destination: watcherName,
              path: watcherPath,
              interface: watcherInterface,
              name: 'RegisterStatusNotifierItem',
              values: [DBusString(_busName!)],
            )
            .timeout(callTimeout);
        _setAvailable(await _watcherHasHost());
        return;
      } catch (e) {
        _log.fine('RegisterStatusNotifierItem failed (attempt ${i + 1}): $e');
      }
    }
    _setAvailable(false);
  }

  Future<bool> _watcherHasHost() async {
    final client = _bus.client;
    if (!await isNameAvailable(
      client,
      watcherName,
      includeActivatable: false,
      timeout: callTimeout,
    )) {
      return false;
    }
    try {
      final reply = await client
          .callMethod(
            destination: watcherName,
            path: watcherPath,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'Get',
            values: [
              const DBusString(watcherInterface),
              const DBusString('IsStatusNotifierHostRegistered'),
            ],
            replySignature: DBusSignature('v'),
          )
          .timeout(callTimeout);
      return unwrapVariant(reply.returnValues[0]).asBoolean();
    } catch (e) {
      // Some watchers omit the property; a running watcher implies a host.
      _log.fine('IsStatusNotifierHostRegistered unavailable: $e');
      return true;
    }
  }

  void _setAvailable(bool value) {
    if (_available == value) return;
    _available = value;
    _log.info(value ? 'Tray item registered' : 'Tray item not visible');
    _emit(TrayAvailabilityChanged(value));
  }

  /// Sets the normal icon. Provide several pixmap sizes; [iconName] (themed)
  /// wins on hosts that can resolve it.
  Future<void> setIcon(List<TrayPixmap> pixmaps, {String? iconName}) async {
    _requireStarted();
    _state.iconPixmaps = List.unmodifiable(pixmaps);
    if (iconName != null) _state.iconName = iconName;
    await _item?.emitItemSignal('NewIcon');
    // The tooltip carries the icon too.
    await _item?.emitItemSignal('NewToolTip');
  }

  /// Sets the icon shown while [TrayStatus.needsAttention].
  Future<void> setAttentionIcon(
    List<TrayPixmap> pixmaps, {
    String? iconName,
  }) async {
    _requireStarted();
    _state.attentionIconPixmaps = List.unmodifiable(pixmaps);
    if (iconName != null) _state.attentionIconName = iconName;
    await _item?.emitItemSignal('NewAttentionIcon');
  }

  Future<void> setStatus(TrayStatus status) async {
    _requireStarted();
    if (_state.status == status) return;
    _state.status = status;
    await _item?.emitItemSignal('NewStatus', [DBusString(status.dbusValue)]);
  }

  Future<void> setTitle(String title) async {
    _requireStarted();
    if (_state.title == title) return;
    _state.title = title;
    await _item?.emitItemSignal('NewTitle');
  }

  Future<void> setTooltip(String title, [String body = '']) async {
    _requireStarted();
    if (_state.tooltipTitle == title && _state.tooltipBody == body) return;
    _state
      ..tooltipTitle = title
      ..tooltipBody = body;
    await _item?.emitItemSignal('NewToolTip');
  }

  /// Replaces the menu. Value-only changes (labels, enabled, checkmarks) are
  /// sent as `ItemsPropertiesUpdated`; structural ones as `LayoutUpdated`.
  Future<void> setMenu(List<TrayMenuItem> items) async {
    _requireStarted();
    final change = _menu.update(items);
    final obj = _menuObject;
    if (obj == null) return;
    switch (change) {
      case DbusMenuLayoutChanged(:final revision):
        await obj.emitMenuSignal('LayoutUpdated', [
          DBusUint32(revision),
          const DBusInt32(0),
        ]);
      case DbusMenuPropertiesChanged():
        await obj.emitMenuSignal('ItemsPropertiesUpdated', change.toDBus());
      case DbusMenuUnchanged():
        break;
    }
  }

  void _requireStarted() {
    if (!_started) throw StateError('Call start() first');
  }

  void _emit(TrayEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  String? _takeToken() {
    final t = _pendingToken;
    _pendingToken = null;
    return t;
  }

  /// Removes the icon, releases the name and closes an owned connection.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final client = _bus.client;
    try {
      if (_item != null) await client.unregisterObject(_item!);
      if (_menuObject != null) await client.unregisterObject(_menuObject!);
      if (_busName != null) {
        await client.releaseName(_busName!).timeout(callTimeout);
      }
    } catch (e) {
      _log.fine('Tray cleanup: $e');
    }
    _available = false;
    await _events.close();
    await _bus.close();
  }
}

class _ItemState {
  _ItemState.fromConfig(TrayConfig c)
    : id = c.id,
      category = c.category,
      title = c.title,
      status = c.status,
      iconName = c.iconName,
      iconPixmaps = List.unmodifiable(c.iconPixmaps),
      attentionIconName = c.attentionIconName,
      attentionIconPixmaps = List.unmodifiable(c.attentionIconPixmaps),
      iconThemePath = c.iconThemePath,
      tooltipTitle = c.tooltipTitle ?? c.title,
      tooltipBody = c.tooltipBody;

  final String id;
  final TrayCategory category;
  String title;
  TrayStatus status;
  String iconName;
  List<TrayPixmap> iconPixmaps;
  String attentionIconName;
  List<TrayPixmap> attentionIconPixmaps;
  final String iconThemePath;
  String tooltipTitle;
  String tooltipBody;

  Map<String, DBusValue> properties(DBusObjectPath menuPath) => {
    'Category': DBusString(category.dbusValue),
    'Id': DBusString(id),
    'Title': DBusString(title),
    'Status': DBusString(status.dbusValue),
    'WindowId': const DBusInt32(0),
    'IconThemePath': DBusString(iconThemePath),
    'Menu': menuPath,
    'ItemIsMenu': const DBusBoolean(false),
    'IconName': DBusString(iconName),
    'IconPixmap': TrayPixmap.listToDBus(iconPixmaps),
    'OverlayIconName': const DBusString(''),
    'OverlayIconPixmap': TrayPixmap.listToDBus(const []),
    'AttentionIconName': DBusString(attentionIconName),
    'AttentionIconPixmap': TrayPixmap.listToDBus(attentionIconPixmaps),
    'AttentionMovieName': const DBusString(''),
    'ToolTip': DBusStruct([
      DBusString(iconName),
      TrayPixmap.listToDBus(iconPixmaps),
      DBusString(tooltipTitle),
      DBusString(tooltipBody),
    ]),
  };
}

/// `/StatusNotifierItem`.
class _SniObject extends DBusObject {
  _SniObject(this.tray) : super(StatusNotifierTray.itemPath);

  final StatusNotifierTray tray;

  Future<void> emitItemSignal(
    String name, [
    List<DBusValue> values = const [],
  ]) async {
    if (client == null) return;
    try {
      await emitSignal(StatusNotifierTray.itemInterface, name, values);
    } catch (e) {
      _log.fine('Emitting $name failed: $e');
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [statusNotifierItemInterface];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != null &&
        call.interface != StatusNotifierTray.itemInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final v = call.values;
    int i(int n) => v[n].asInt32();
    switch ((call.name, call.signature.value)) {
      case ('Activate', 'ii'):
        tray._emit(
          TrayActivated(i(0), i(1), activationToken: tray._takeToken()),
        );
      case ('SecondaryActivate', 'ii'):
        tray._emit(
          TraySecondaryActivated(
            i(0),
            i(1),
            activationToken: tray._takeToken(),
          ),
        );
      case ('ContextMenu', 'ii'):
        tray._emit(TrayContextMenuRequested(i(0), i(1)));
      case ('Scroll', 'is'):
        tray._emit(
          TrayScrolled(
            i(0),
            v[1].asString().toLowerCase() == 'horizontal'
                ? TrayScrollOrientation.horizontal
                : TrayScrollOrientation.vertical,
          ),
        );
      case ('ProvideXdgActivationToken', 's'):
        tray._pendingToken = v[0].asString();
      case ('Activate' || 'SecondaryActivate' || 'ContextMenu' || 'Scroll', _):
      case ('ProvideXdgActivationToken', _):
        return DBusMethodErrorResponse.invalidArgs();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != StatusNotifierTray.itemInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = tray._state.properties(StatusNotifierTray.menuPath)[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != StatusNotifierTray.itemInterface) {
      return DBusGetAllPropertiesResponse(const {});
    }
    return DBusGetAllPropertiesResponse(
      tray._state.properties(StatusNotifierTray.menuPath),
    );
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async => DBusMethodErrorResponse.propertyReadOnly();
}

/// `/MenuBar` (`com.canonical.dbusmenu`).
class _MenuObject extends DBusObject {
  _MenuObject(this.tray) : super(StatusNotifierTray.menuPath);

  final StatusNotifierTray tray;

  DbusMenuModel get menu => tray._menu;

  static final _properties = <String, DBusValue>{
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const []),
  };

  Future<void> emitMenuSignal(String name, List<DBusValue> values) async {
    if (client == null) return;
    try {
      await emitSignal(StatusNotifierTray.menuInterface, name, values);
    } catch (e) {
      _log.fine('Emitting $name failed: $e');
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [dbusMenuInterface];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != null &&
        call.interface != StatusNotifierTray.menuInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final v = call.values;
    switch ((call.name, call.signature.value)) {
      case ('GetLayout', 'iias'):
        final layout = menu.layout(
          v[0].asInt32(),
          depth: v[1].asInt32(),
          propertyNames: v[2].asStringArray().toList(),
        );
        if (layout == null) {
          return DBusMethodErrorResponse.invalidArgs('Unknown menu id');
        }
        return DBusMethodSuccessResponse([DBusUint32(menu.revision), layout]);
      case ('GetGroupProperties', 'aias'):
        return DBusMethodSuccessResponse([
          menu.groupProperties(
            v[0].asInt32Array().toList(),
            propertyNames: v[1].asStringArray().toList(),
          ),
        ]);
      case ('GetProperty', 'is'):
        final value = menu.node(v[0].asInt32())?.properties[v[1].asString()];
        if (value == null) {
          return DBusMethodErrorResponse.invalidArgs('Unknown item/property');
        }
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      case ('Event', 'isvu'):
        if (!_handleEvent(v[0].asInt32(), v[1].asString())) {
          return DBusMethodErrorResponse.invalidArgs('Unknown menu id');
        }
        return DBusMethodSuccessResponse();
      case ('EventGroup', 'a(isvu)'):
        final errors = <int>[];
        for (final e in v[0].asArray()) {
          final s = e.asStruct();
          final id = s[0].asInt32();
          if (!_handleEvent(id, s[1].asString())) errors.add(id);
        }
        return DBusMethodSuccessResponse([DBusArray.int32(errors)]);
      case ('AboutToShow', 'i'):
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);
      case ('AboutToShowGroup', 'ai'):
        final errors = v[0]
            .asInt32Array()
            .where((id) => menu.node(id) == null)
            .toList();
        return DBusMethodSuccessResponse([
          DBusArray.int32(const []),
          DBusArray.int32(errors),
        ]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  bool _handleEvent(int id, String eventId) {
    final node = menu.node(id);
    if (node == null) return false;
    if (eventId == 'clicked' && node.key != null) {
      final enabled = node.properties['enabled'];
      if (enabled is DBusBoolean && !enabled.value) return true;
      tray._emit(
        TrayMenuItemSelected(node.key!, activationToken: tray._takeToken()),
      );
    }
    return true;
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == StatusNotifierTray.menuInterface
        ? _properties[name]
        : null;
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(
        interface == StatusNotifierTray.menuInterface ? _properties : const {},
      );

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async => DBusMethodErrorResponse.propertyReadOnly();
}
