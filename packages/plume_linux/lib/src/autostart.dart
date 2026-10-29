import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'dbus/bus.dart';
import 'desktop_environment.dart';

final _log = Logger('plume_linux.autostart');

/// Thrown when the Background portal refuses or fails a request.
class AutostartException implements Exception {
  const AutostartException(this.message);
  final String message;

  @override
  String toString() => 'AutostartException: $message';
}

/// Start-at-login management.
///
/// Outside Flatpak this writes `$XDG_CONFIG_HOME/autostart/<appId>.desktop`.
/// Inside Flatpak it asks `org.freedesktop.portal.Background` (which writes
/// the host-side file for us) and remembers the granted state in the
/// sandbox's config dir, since the host file is not visible from inside.
///
/// Bare compositors (Hyprland, sway, niri, river, ...) only run XDG autostart
/// entries when the session uses systemd's `xdg-desktop-autostart.target`
/// (e.g. uwsm). Check [compositorHonorsXdgAutostart] (refined by
/// [probeXdgAutostartSupport]) and show [compositorAutostartSnippet] to the
/// user when it is false.
class Autostart {
  Autostart({
    this.appId = 'org.atinus.plume',
    this.appName = 'Plume',
    String? executable,
    this.arguments = const ['--background'],
    this.iconName,
    this.comment = 'Check mail in the background',
    DesktopEnvironment? environment,
    String? configHome,
    bool? isFlatpak,
    DBusClient? bus,
    this.callTimeout = defaultCallTimeout,
  }) : // Inside an AppImage the binary lives in a mount that is gone after
       // exit; $APPIMAGE is the file to start instead.
       executable = executable ?? Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable,
       environment = environment ?? DesktopEnvironment.current(),
       _configHomeOverride = configHome,
       _isFlatpakOverride = isFlatpak,
       _injectedBus = bus;

  final String appId;
  final String appName;
  final String executable;
  final List<String> arguments;

  /// Defaults to [appId].
  final String? iconName;
  final String comment;
  final DesktopEnvironment environment;
  final Duration callTimeout;
  final String? _configHomeOverride;
  final bool? _isFlatpakOverride;
  final DBusClient? _injectedBus;
  bool? _probedHonors;

  bool get isFlatpak => _isFlatpakOverride ?? environment.isFlatpak;

  String get configHome {
    final override = _configHomeOverride;
    if (override != null) return override;
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && p.isAbsolute(xdg)) return xdg;
    return p.join(Platform.environment['HOME'] ?? '/', '.config');
  }

  /// `$XDG_CONFIG_HOME/autostart/<appId>.desktop`.
  String get desktopFilePath =>
      p.join(configHome, 'autostart', '$appId.desktop');

  /// Where the Flatpak path remembers the last granted state.
  String get _portalStatePath =>
      p.join(configHome, appId, 'autostart-requested');

  /// The command line that autostart runs.
  List<String> get commandLine => [executable, ...arguments];

  /// Contents of the autostart `.desktop` file.
  String desktopFileContents() {
    final exec = commandLine.map(quoteExecArgument).join(' ');
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Version=1.5',
      'Name=${_escapeValue(appName)}',
      'Comment=${_escapeValue(comment)}',
      'Exec=$exec',
      'Icon=${_escapeValue(iconName ?? appId)}',
      'Terminal=false',
      'StartupNotify=false',
      'X-GNOME-Autostart-enabled=true',
      '',
    ].join('\n');
  }

  /// Whether autostart is on.
  Future<bool> isEnabled() async {
    if (isFlatpak) {
      final f = File(_portalStatePath);
      return await f.exists() && (await f.readAsString()).trim() == 'true';
    }
    final f = File(desktopFilePath);
    if (!await f.exists()) return false;
    return isDesktopEntryEnabled(await f.readAsString());
  }

  /// Turns autostart on. Throws [AutostartException] if the portal denies it.
  Future<void> enable() => _set(true);

  /// Turns autostart off.
  Future<void> disable() => _set(false);

  Future<void> _set(bool enabled) async {
    if (isFlatpak) {
      final granted = await _requestBackground(enabled);
      final state = File(_portalStatePath);
      await state.parent.create(recursive: true);
      await state.writeAsString('${granted && enabled}\n');
      if (enabled && !granted) {
        throw const AutostartException('Autostart was not granted');
      }
      return;
    }
    final f = File(desktopFilePath);
    if (enabled) {
      await f.parent.create(recursive: true);
      // Write-then-rename so a crash never leaves a truncated entry.
      final tmp = File('${f.path}.tmp-$pid');
      await tmp.writeAsString(desktopFileContents(), flush: true);
      await tmp.rename(f.path);
      _log.info('Autostart enabled: ${f.path}');
    } else if (await f.exists()) {
      await f.delete();
      _log.info('Autostart disabled: removed ${f.path}');
    }
  }

  /// Best-effort guess whether the session runs XDG autostart entries.
  ///
  /// True for full desktops (KDE, GNOME, XFCE, Cinnamon, ...). False for bare
  /// compositors/window managers unless uwsm or an active
  /// `xdg-desktop-autostart.target` was detected (see
  /// [probeXdgAutostartSupport]).
  bool get compositorHonorsXdgAutostart {
    if (_probedHonors != null) return _probedHonors!;
    return _heuristicHonors;
  }

  bool get _heuristicHonors {
    if (environment.isFullDesktop) return true;
    if (environment.hasUwsm) return true;
    if (environment.isTilingCompositor) return false;
    // Unknown stacking compositors (labwc, wayfire, openbox): most rely on
    // the user's own startup script too.
    return environment.primary == null;
  }

  /// Refines [compositorHonorsXdgAutostart] by asking the systemd user
  /// manager whether `xdg-desktop-autostart.target` is active (uwsm, or a
  /// user who starts it from their compositor config). Returns the refined
  /// value; never throws.
  Future<bool> probeXdgAutostartSupport() async {
    if (_heuristicHonors) return _probedHonors = true;
    if (isFlatpak) return false;
    final bus = BusHandle.session(_injectedBus);
    try {
      if (!await bus.connect(timeout: callTimeout)) return false;
      final client = bus.client;
      final unit = await client
          .callMethod(
            destination: 'org.freedesktop.systemd1',
            path: DBusObjectPath('/org/freedesktop/systemd1'),
            interface: 'org.freedesktop.systemd1.Manager',
            name: 'GetUnit',
            values: [const DBusString('xdg-desktop-autostart.target')],
            replySignature: DBusSignature('o'),
          )
          .timeout(callTimeout);
      final state = await client
          .callMethod(
            destination: 'org.freedesktop.systemd1',
            path: unit.returnValues[0].asObjectPath(),
            interface: 'org.freedesktop.DBus.Properties',
            name: 'Get',
            values: [
              const DBusString('org.freedesktop.systemd1.Unit'),
              const DBusString('ActiveState'),
            ],
            replySignature: DBusSignature('v'),
          )
          .timeout(callTimeout);
      final active = unwrapVariant(state.returnValues[0]).asString();
      _log.fine('xdg-desktop-autostart.target is $active');
      return _probedHonors = active == 'active' || active == 'activating';
    } catch (e) {
      // GetUnit fails with NoSuchUnit when the target was never loaded.
      _log.fine('systemd autostart probe: $e');
      return _probedHonors = false;
    } finally {
      await bus.close();
    }
  }

  /// A config line for the user's compositor, for when XDG autostart is not
  /// honoured. `null` when there is no known syntax.
  String? get compositorAutostartSnippet {
    final cmd = commandLine.map(_shellQuote).join(' ');
    if (environment.isHyprland) return 'exec-once = $cmd';
    if (environment.isSway || environment.isI3) {
      return 'exec ${environment.isI3 ? '--no-startup-id ' : ''}$cmd';
    }
    if (environment.isNiri) {
      // KDL strings: escape backslashes and quotes.
      final args = commandLine.map(
        (a) => '"${a.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
      );
      return 'spawn-at-startup ${args.join(' ')}';
    }
    if (environment.isRiver) return 'riverctl spawn ${_shellQuote(cmd)}';
    return null;
  }

  Future<bool> _requestBackground(bool autostart) async {
    final bus = BusHandle.session(_injectedBus);
    StreamSubscription<DBusSignal>? sub;
    try {
      if (!await bus.connect(timeout: callTimeout)) {
        throw const AutostartException('No session bus');
      }
      final client = bus.client;
      final token = 'plume${Random().nextInt(1 << 31)}';
      final sender = client.uniqueName.substring(1).replaceAll('.', '_');
      final handle = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$sender/$token',
      );
      final response = Completer<(int, Map<String, DBusValue>)>();
      sub =
          DBusSignalStream(
            client,
            sender: 'org.freedesktop.portal.Desktop',
            interface: 'org.freedesktop.portal.Request',
            name: 'Response',
            path: handle,
            signature: DBusSignature('ua{sv}'),
          ).listen((s) {
            if (!response.isCompleted) {
              response.complete((
                s.values[0].asUint32(),
                s.values[1].asStringVariantDict(),
              ));
            }
          }, onError: (Object _) {});
      // The Response must not be emitted before our match rule is active.
      await flushMatchRules(client, timeout: callTimeout);
      await client
          .callMethod(
            destination: 'org.freedesktop.portal.Desktop',
            path: DBusObjectPath('/org/freedesktop/portal/desktop'),
            interface: 'org.freedesktop.portal.Background',
            name: 'RequestBackground',
            values: [
              const DBusString(''),
              DBusDict.stringVariant({
                'handle_token': DBusString(token),
                'reason': DBusString(comment),
                'autostart': DBusBoolean(autostart),
                'commandline': DBusArray.string(commandLine),
                'dbus-activatable': const DBusBoolean(false),
              }),
            ],
            replySignature: DBusSignature('o'),
          )
          .timeout(callTimeout);
      // The user may be shown a dialog; allow time to answer.
      final (code, results) = await response.future.timeout(
        const Duration(minutes: 2),
      );
      if (code != 0) return false;
      final granted = results['autostart'];
      return granted is DBusBoolean ? granted.value : autostart;
    } on AutostartException {
      rethrow;
    } catch (e) {
      throw AutostartException('Background portal request failed: $e');
    } finally {
      await sub?.cancel();
      await bus.close();
    }
  }
}

/// Whether a desktop entry (autostart file contents) is enabled: not
/// `Hidden=true` and not `X-GNOME-Autostart-enabled=false`.
bool isDesktopEntryEnabled(String contents) {
  var inMain = false;
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inMain = line == '[Desktop Entry]';
      continue;
    }
    if (!inMain) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim().toLowerCase();
    if (key == 'Hidden' && value == 'true') return false;
    if (key == 'X-GNOME-Autostart-enabled' && value == 'false') return false;
  }
  return true;
}

/// Quotes one argument for a desktop entry `Exec=` key, including the
/// string-value escaping layer, per the Desktop Entry Specification.
String quoteExecArgument(String arg) {
  final escapedPercent = arg.replaceAll('%', '%%');
  final needsQuotes =
      arg.isEmpty || RegExp(r'''[\s"'\\><~|&;$*?#()`]''').hasMatch(arg);
  if (!needsQuotes) return escapedPercent;
  // Inside double quotes, ", `, $ and \ are escaped with a backslash; the
  // string-value layer then doubles every backslash.
  final quoted = escapedPercent.replaceAllMapped(
    RegExp(r'["`$\\]'),
    (m) => '\\${m[0]}',
  );
  return '"${quoted.replaceAll(r'\', r'\\')}"';
}

String _escapeValue(String v) => v
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\t', r'\t')
    .replaceAll('\r', r'\r');

String _shellQuote(String arg) {
  if (RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(arg)) return arg;
  return "'${arg.replaceAll("'", r"'\''")}'";
}
