import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:plume_linux/plume_linux.dart';

final _log = Logger('plume.linux.window');

/// A window edge or corner for [LinuxWindow.startResize].
enum LinuxWindowEdge {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Window state reported by the GTK runner.
///
/// These are the states the compositor configures, so they follow its
/// conventions: Hyprland reports every window as maximized and tiled (to
/// suppress client-side shadows), even when floating. Prefer
/// [LinuxWindow.isTilingCompositor] for layout decisions there.
final class LinuxWindowState {
  const LinuxWindowState({
    this.maximized = false,
    this.fullscreen = false,
    this.focused = false,
    this.visible = false,
    this.tiled = false,
  });

  factory LinuxWindowState._fromMap(Map<Object?, Object?> map) =>
      LinuxWindowState(
        maximized: map['maximized'] == true,
        fullscreen: map['fullscreen'] == true,
        focused: map['focused'] == true,
        visible: map['visible'] == true,
        tiled: map['tiled'] == true,
      );

  final bool maximized;
  final bool fullscreen;
  final bool focused;

  /// Mapped and not minimised.
  final bool visible;

  /// Tiled by the window manager (tiling compositors, GNOME edge snapping).
  /// Useful to drop rounded corners or resize affordances.
  final bool tiled;

  @override
  bool operator ==(Object other) =>
      other is LinuxWindowState &&
      other.maximized == maximized &&
      other.fullscreen == fullscreen &&
      other.focused == focused &&
      other.visible == visible &&
      other.tiled == tiled;

  @override
  int get hashCode =>
      Object.hash(maximized, fullscreen, focused, visible, tiled);

  @override
  String toString() =>
      'LinuxWindowState(maximized: $maximized, fullscreen: $fullscreen, '
      'focused: $focused, visible: $visible, tiled: $tiled)';
}

/// The running instance was activated again, typically because Plume was
/// launched a second time (the second process exits immediately). The runner
/// has already presented the window.
final class LinuxWindowActivation {
  const LinuxWindowActivation({this.activationToken});

  /// The xdg-activation token (Wayland) or startup id (X11) of the activating
  /// launch, if the launcher provided one.
  final String? activationToken;

  @override
  String toString() =>
      'LinuxWindowActivation(activationToken: $activationToken)';
}

/// Controls the main window through the GTK runner's `plume/window` channel.
///
/// Create one instance after `WidgetsFlutterBinding.ensureInitialized()`; it
/// installs the channel's call handler (only one handler can exist).
///
/// The runner starts hidden when launched with `--background`: the Dart
/// isolate runs but nothing renders until [show] is called. A second launch of
/// the app presents the window and emits [activated]. Links the app is asked
/// to open (`plume mailto:…`) are collected with [takeOpenUris] and [openUris].
class LinuxWindow {
  LinuxWindow({MethodChannel? channel, DesktopEnvironment? environment})
    : _channel = channel ?? const MethodChannel(channelName),
      environment = environment ?? DesktopEnvironment.current() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const channelName = 'plume/window';

  final MethodChannel _channel;

  /// The desktop this window runs on.
  final DesktopEnvironment environment;

  final _closeRequested = StreamController<void>.broadcast();
  final _activated = StreamController<LinuxWindowActivation>.broadcast();
  final _openUris = StreamController<List<String>>.broadcast();
  final _stateChanged = StreamController<LinuxWindowState>.broadcast();
  LinuxWindowState _state = const LinuxWindowState();

  /// Whether the session runs a tiling compositor (Hyprland, sway, niri, i3…)
  /// where minimise/maximise buttons and window shadows make little sense.
  bool get isTilingCompositor => environment.isTilingCompositor;

  /// The close button was pressed while [setPreventClose] was enabled. The
  /// runner has already hidden the window.
  Stream<void> get closeRequested => _closeRequested.stream;

  /// Another launch activated this instance; see [LinuxWindowActivation].
  Stream<LinuxWindowActivation> get activated => _activated.stream;

  /// `mailto:` links to open, received after [takeOpenUris] was called. The
  /// runner has already presented the window.
  Stream<List<String>> get openUris => _openUris.stream;

  /// Maximised/fullscreen/focus/visibility/tiling changes.
  Stream<LinuxWindowState> get stateChanged => _stateChanged.stream;

  /// The most recent state reported by the runner.
  LinuxWindowState get state => _state;

  /// Shows, raises and focuses the window. Pass the [activationToken] from a
  /// notification action or tray activation so Wayland compositors allow the
  /// focus change.
  Future<void> show({String? activationToken}) =>
      _invoke<void>('show', {'activationToken': activationToken});

  /// Hides the window. Rendering stops; Dart code keeps running.
  Future<void> hide() => _invoke<void>('hide');

  Future<bool> isVisible() async => await _invoke<bool>('isVisible') ?? false;

  /// Minimises the window. Tiling compositors usually ignore this.
  Future<void> minimize() => _invoke<void>('minimize');

  Future<void> toggleMaximize() => _invoke<void>('toggleMaximize');

  Future<bool> isMaximized() async =>
      await _invoke<bool>('isMaximized') ?? false;

  /// Starts an interactive move. Call while the primary button is held, e.g.
  /// from `onPanStart` of a custom title bar.
  Future<void> startMove() => _invoke<void>('startMove');

  /// Starts an interactive resize from [edge]. Call while the button is held.
  Future<void> startResize(LinuxWindowEdge edge) =>
      _invoke<void>('startResize', edge.name);

  /// When enabled, the window close button hides the window and emits
  /// [closeRequested] instead of quitting.
  Future<void> setPreventClose(bool preventClose) =>
      _invoke<void>('setPreventClose', preventClose);

  Future<void> setTitle(String title) => _invoke<void>('setTitle', title);

  /// Returns the links received so far, including the one the app was
  /// launched with, and has the runner send later ones through [openUris].
  /// Listen to [openUris] before calling this so none are missed.
  Future<List<String>> takeOpenUris() async {
    final uris = await _invoke<List<Object?>>('takeOpenUris');
    return [...?uris?.whereType<String>()];
  }

  /// Quits the application for real, regardless of [setPreventClose].
  Future<void> quit() => _invoke<void>('quit');

  /// Removes the channel handler and closes the streams.
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_closeRequested.close());
    unawaited(_activated.close());
    unawaited(_openUris.close());
    unawaited(_stateChanged.close());
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _log.warning('$method: no "$channelName" channel in this runner');
      return null;
    }
  }

  Future<Object?> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onCloseRequested':
        _closeRequested.add(null);
      case 'onActivated':
        final args = call.arguments;
        final token = args is Map ? args['activationToken'] : null;
        _activated.add(
          LinuxWindowActivation(
            activationToken: token is String ? token : null,
          ),
        );
      case 'onOpenUris':
        final args = call.arguments;
        if (args is List) _openUris.add([...args.whereType<String>()]);
      case 'onWindowStateChanged':
        final args = call.arguments;
        if (args is Map) {
          _state = LinuxWindowState._fromMap(args);
          _stateChanged.add(_state);
        }
      default:
        _log.fine('Unhandled window callback ${call.method}');
        throw MissingPluginException();
    }
    return null;
  }
}
