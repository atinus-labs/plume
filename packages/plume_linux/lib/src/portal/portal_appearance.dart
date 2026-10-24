import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';

import '../dbus/bus.dart';

final _log = Logger('plume_linux.portal.appearance');

/// `org.freedesktop.appearance color-scheme`.
enum ColorSchemePreference {
  noPreference,
  dark,
  light;

  static ColorSchemePreference fromValue(int v) => switch (v) {
    1 => dark,
    2 => light,
    _ => noPreference,
  };
}

/// `org.freedesktop.appearance contrast`.
enum ContrastPreference {
  noPreference,
  high;

  static ContrastPreference fromValue(int v) => v == 1 ? high : noPreference;
}

/// The system accent colour, channels in 0..1 (sRGB).
class AccentColor {
  const AccentColor(this.red, this.green, this.blue);

  final double red;
  final double green;
  final double blue;

  /// Parses `(ddd)`; out-of-range values mean "unset" and return `null`.
  static AccentColor? fromDBus(DBusValue value) {
    final v = unwrapVariant(value);
    if (v is! DBusStruct || v.children.length != 3) return null;
    final channels = <double>[];
    for (final c in v.children) {
      if (c is! DBusDouble) return null;
      if (c.value.isNaN || c.value < 0 || c.value > 1) return null;
      channels.add(c.value);
    }
    return AccentColor(channels[0], channels[1], channels[2]);
  }

  /// 0xFFRRGGBB, convenient for `Color(argb)`.
  int toArgb32() {
    int ch(double d) => (d * 255).round().clamp(0, 255);
    return 0xFF000000 | ch(red) << 16 | ch(green) << 8 | ch(blue);
  }

  @override
  bool operator ==(Object other) =>
      other is AccentColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'AccentColor($red, $green, $blue)';
}

/// A snapshot of the appearance settings.
class AppearanceSettings {
  const AppearanceSettings({
    this.colorScheme = ColorSchemePreference.noPreference,
    this.accentColor,
    this.contrast = ContrastPreference.noPreference,
  });

  final ColorSchemePreference colorScheme;

  /// `null` when unset or unsupported by the portal backend.
  final AccentColor? accentColor;
  final ContrastPreference contrast;

  AppearanceSettings copyWith({
    ColorSchemePreference? colorScheme,
    AccentColor? Function()? accentColor,
    ContrastPreference? contrast,
  }) => AppearanceSettings(
    colorScheme: colorScheme ?? this.colorScheme,
    accentColor: accentColor != null ? accentColor() : this.accentColor,
    contrast: contrast ?? this.contrast,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.colorScheme == colorScheme &&
      other.accentColor == accentColor &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(colorScheme, accentColor, contrast);

  @override
  String toString() =>
      'AppearanceSettings(colorScheme: ${colorScheme.name}, '
      'accent: $accentColor, contrast: ${contrast.name})';
}

/// Reads `org.freedesktop.appearance` from the Settings portal and follows
/// `SettingChanged`.
///
/// Uses `ReadOne` (Settings v2) and falls back to the deprecated `Read`
/// (which wraps the value in an extra variant). Without a portal every value
/// is "no preference" and [isAvailable] is false.
class PortalAppearance {
  PortalAppearance({DBusClient? bus, this.callTimeout = defaultCallTimeout})
    : _bus = BusHandle.session(bus);

  static const portalName = 'org.freedesktop.portal.Desktop';
  static final portalPath = DBusObjectPath('/org/freedesktop/portal/desktop');
  static const settingsInterface = 'org.freedesktop.portal.Settings';
  static const namespace = 'org.freedesktop.appearance';

  final Duration callTimeout;
  final BusHandle _bus;
  final _changes = StreamController<AppearanceSettings>.broadcast();
  StreamSubscription<DBusSignal>? _subscription;
  Future<bool>? _init;
  bool _available = false;
  bool _useReadOne = true;
  bool _disposed = false;
  AppearanceSettings _current = const AppearanceSettings();

  bool get isAvailable => _available;
  AppearanceSettings get current => _current;
  ColorSchemePreference get colorScheme => _current.colorScheme;
  AccentColor? get accentColor => _current.accentColor;
  ContrastPreference get contrast => _current.contrast;

  /// Emits the full settings whenever one of them changes.
  Stream<AppearanceSettings> get changes => _changes.stream;

  /// Reads the current values and subscribes to changes. Never throws.
  Future<bool> initialize() => _init ??= _initialize();

  Future<bool> _initialize() async {
    if (!await _bus.connect(timeout: callTimeout)) return false;
    if (!await isNameAvailable(_bus.client, portalName, timeout: callTimeout)) {
      _log.info('No desktop portal; appearance defaults to no preference');
      return false;
    }
    _subscription = listenSignals(
      DBusSignalStream(
        _bus.client,
        sender: portalName,
        interface: settingsInterface,
        name: 'SettingChanged',
        path: portalPath,
        signature: DBusSignature('ssv'),
      ),
      _onSettingChanged,
      _log,
    );

    final scheme = await _read('color-scheme');
    final accent = await _read('accent-color');
    final contrast = await _read('contrast');
    _available = scheme != null || accent != null || contrast != null;
    _current = AppearanceSettings(
      colorScheme: _scheme(scheme),
      accentColor: accent == null ? null : AccentColor.fromDBus(accent),
      contrast: _contrast(contrast),
    );
    _log.info('Portal appearance: $_current');
    return _available;
  }

  static ColorSchemePreference _scheme(DBusValue? v) => v is DBusUint32
      ? ColorSchemePreference.fromValue(v.value)
      : .noPreference;

  static ContrastPreference _contrast(DBusValue? v) =>
      v is DBusUint32 ? ContrastPreference.fromValue(v.value) : .noPreference;

  /// Reads one key, unwrapped; `null` when unset/unsupported.
  Future<DBusValue?> _read(String key) async {
    final args = [const DBusString(namespace), DBusString(key)];
    if (_useReadOne) {
      try {
        final r = await _call('ReadOne', args);
        return unwrapVariant(r.returnValues[0]);
      } on DBusUnknownMethodException {
        _log.fine('Settings.ReadOne missing; falling back to Read');
        _useReadOne = false;
      } catch (e) {
        if (_isNotFound(e)) return null;
        _log.fine('ReadOne($key) failed: $e');
        return null;
      }
    }
    try {
      final r = await _call('Read', args);
      // `Read` returns v containing v.
      return unwrapVariant(r.returnValues[0]);
    } catch (e) {
      if (!_isNotFound(e)) _log.fine('Read($key) failed: $e');
      return null;
    }
  }

  static bool _isNotFound(Object e) =>
      dbusErrorName(e) == 'org.freedesktop.portal.Error.NotFound';

  Future<DBusMethodSuccessResponse> _call(
    String method,
    List<DBusValue> args,
  ) => _bus.client
      .callMethod(
        destination: portalName,
        path: portalPath,
        interface: settingsInterface,
        name: method,
        values: args,
        replySignature: DBusSignature('v'),
      )
      .timeout(callTimeout);

  void _onSettingChanged(DBusSignal s) {
    if (s.values[0].asString() != namespace) return;
    final value = unwrapVariant(s.values[2]);
    final AppearanceSettings next;
    switch (s.values[1].asString()) {
      case 'color-scheme':
        next = _current.copyWith(colorScheme: _scheme(value));
      case 'accent-color':
        next = _current.copyWith(
          accentColor: () => AccentColor.fromDBus(value),
        );
      case 'contrast':
        next = _current.copyWith(contrast: _contrast(value));
      default:
        return;
    }
    _available = true;
    if (next == _current) return;
    _current = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _changes.close();
    await _bus.close();
  }
}
