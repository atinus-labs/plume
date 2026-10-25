import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('plume_linux.mime_apps');

/// The MIME type desktops use for the handler of `mailto:` links.
const mailtoSchemeHandler = 'x-scheme-handler/mailto';

/// Whether the installed desktop entry can be chosen as a handler.
enum HandlerEntryStatus {
  /// No `<id>.desktop` in any applications directory: the app is not
  /// installed (e.g. a development build), so no desktop can launch it.
  missing,

  /// Installed, but its `MimeType=` lacks the type. Desktops (KDE's Default
  /// Applications page, GNOME Settings, `xdg-open`) only offer apps that
  /// declare the type, so the entry is out of date.
  missingMimeType,

  /// Installed and declares the type.
  ok,
}

/// Default applications as defined by the XDG MIME Applications
/// Specification (`mimeapps.list`), which GIO, KDE, `xdg-open`,
/// xdg-desktop-portal and browsers all honour.
///
/// Lookup order, first match wins:
///  1. `$XDG_CONFIG_HOME/<desktop>-mimeapps.list`, `$XDG_CONFIG_HOME/mimeapps.list`
///  2. the same in each `$XDG_CONFIG_DIRS`
///  3. `$XDG_DATA_HOME/applications/[<desktop>-]mimeapps.list`
///  4. the same in each `$XDG_DATA_DIRS/applications`
///
/// `<desktop>` is each `XDG_CURRENT_DESKTOP` entry, lower-cased.
class MimeApps {
  MimeApps({
    Map<String, String>? environment,
    String? configHome,
    List<String>? configDirs,
    String? dataHome,
    List<String>? dataDirs,
    this.refreshKdeCache = true,
  }) : _env = environment ?? Platform.environment,
       _configHomeOverride = configHome,
       _configDirsOverride = configDirs,
       _dataHomeOverride = dataHome,
       _dataDirsOverride = dataDirs;

  /// Whether [setDefault] rebuilds KDE's service cache afterwards.
  final bool refreshKdeCache;

  final Map<String, String> _env;
  final String? _configHomeOverride;
  final List<String>? _configDirsOverride;
  final String? _dataHomeOverride;
  final List<String>? _dataDirsOverride;

  String get _home => _env['HOME'] ?? '/';

  String get configHome =>
      _configHomeOverride ?? _absolute(_env['XDG_CONFIG_HOME']) ?? p.join(_home, '.config');

  List<String> get configDirs => _configDirsOverride ?? _dirList(_env['XDG_CONFIG_DIRS'], const ['/etc/xdg']);

  String get dataHome =>
      _dataHomeOverride ?? _absolute(_env['XDG_DATA_HOME']) ?? p.join(_home, '.local', 'share');

  List<String> get dataDirs =>
      _dataDirsOverride ?? _dirList(_env['XDG_DATA_DIRS'], const ['/usr/local/share', '/usr/share']);

  /// Lower-cased `XDG_CURRENT_DESKTOP` entries, most specific first.
  List<String> get desktops => [
    for (final d in (_env['XDG_CURRENT_DESKTOP'] ?? '').split(':'))
      if (d.trim().isNotEmpty) d.trim().toLowerCase(),
  ];

  /// The file that [setDefault] writes.
  String get userListPath => p.join(configHome, 'mimeapps.list');

  /// Every `mimeapps.list` in lookup order, whether or not it exists.
  List<String> get listPaths {
    final dirs = [
      configHome,
      ...configDirs,
      p.join(dataHome, 'applications'),
      for (final d in dataDirs) p.join(d, 'applications'),
    ];
    return [
      for (final dir in dirs) ...[
        for (final desktop in desktops) p.join(dir, '$desktop-mimeapps.list'),
        p.join(dir, 'mimeapps.list'),
      ],
    ];
  }

  /// Applications directories in precedence order.
  List<String> get applicationDirs => [
    p.join(dataHome, 'applications'),
    for (final d in dataDirs) p.join(d, 'applications'),
  ];

  /// The path of the installed desktop entry [desktopId] (e.g.
  /// `org.atinus.plume.desktop`), or null if it is not installed.
  String? findDesktopEntry(String desktopId) {
    for (final dir in applicationDirs) {
      final direct = File(p.join(dir, desktopId));
      if (direct.existsSync()) return direct.path;
      // `vendor-app.desktop` may live at `vendor/app.desktop`.
      final dash = desktopId.indexOf('-');
      if (dash > 0) {
        final nested = File(p.join(dir, desktopId.substring(0, dash), desktopId.substring(dash + 1)));
        if (nested.existsSync()) return nested.path;
      }
    }
    return null;
  }

  /// Whether [desktopId] is installed and declares [mimeType].
  HandlerEntryStatus handlerEntryStatus(String desktopId, String mimeType) {
    final path = findDesktopEntry(desktopId);
    if (path == null) return HandlerEntryStatus.missing;
    try {
      final types = desktopEntryList(File(path).readAsStringSync(), 'MimeType');
      return types.contains(mimeType) ? HandlerEntryStatus.ok : HandlerEntryStatus.missingMimeType;
    } on FileSystemException catch (e) {
      _log.fine('Reading $path: $e');
      return HandlerEntryStatus.missing;
    }
  }

  /// The configured default application for [mimeType]: the first installed
  /// entry in the first `[Default Applications]` line that names one. Null if
  /// nothing is configured, in which case desktops fall back to any app that
  /// declares the type.
  String? defaultFor(String mimeType) {
    for (final path in listPaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final String contents;
      try {
        contents = file.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      for (final id in readMimeAppsEntry(contents, _defaultSection, mimeType)) {
        if (findDesktopEntry(id) != null) return id;
      }
    }
    return null;
  }

  /// Makes [desktopId] the default for [mimeType] in the user's
  /// `mimeapps.list`, the way desktop settings panels do: it becomes the
  /// `[Default Applications]` entry and the first `[Added Associations]`
  /// entry, and is dropped from `[Removed Associations]`. Desktop-specific
  /// user lists that name another default are updated too, since they take
  /// precedence. Symlinked lists (dotfile managers) are written through.
  Future<void> setDefault(String mimeType, String desktopId) async {
    await _edit(userListPath, (contents) {
      var next = writeMimeAppsEntry(contents, _defaultSection, mimeType, (_) => [desktopId]);
      next = writeMimeAppsEntry(next, _addedSection, mimeType, (ids) => [desktopId, ...ids.where((i) => i != desktopId)]);
      return writeMimeAppsEntry(next, _removedSection, mimeType, (ids) => ids.where((i) => i != desktopId).toList());
    }, create: true);

    for (final desktop in desktops) {
      await _edit(p.join(configHome, '$desktop-mimeapps.list'), (contents) {
        if (readMimeAppsEntry(contents, _defaultSection, mimeType).isEmpty) return contents;
        return writeMimeAppsEntry(contents, _defaultSection, mimeType, (_) => [desktopId]);
      }, create: false);
    }
    _log.info('$desktopId is now the default for $mimeType');
    if (refreshKdeCache) await _refreshKdeCache();
  }

  /// KDE reads associations through its sycoca cache. kded rebuilds it when
  /// files change, but kded is often missing outside Plasma (KDE apps and
  /// System Settings on Hyprland, sway...), so rebuild it now.
  Future<void> _refreshKdeCache() async {
    for (final tool in const ['kbuildsycoca6', 'kbuildsycoca5']) {
      try {
        await Process.start(tool, const [], mode: ProcessStartMode.detached);
        return;
      } on ProcessException {
        // Not installed; try the next one.
      }
    }
  }

  Future<void> _edit(String path, String Function(String) update, {required bool create}) async {
    var file = File(path);
    final exists = await file.exists();
    if (!exists && !create) return;
    if (exists) file = File(await file.resolveSymbolicLinks());
    final before = exists ? await file.readAsString() : '';
    final after = update(before);
    if (exists && after == before) return;
    await file.parent.create(recursive: true);
    // Write-then-rename so a crash never leaves a truncated list.
    final tmp = File('${file.path}.tmp-$pid');
    await tmp.writeAsString(after, flush: true);
    await tmp.rename(file.path);
  }

  static String? _absolute(String? path) => path != null && p.isAbsolute(path) ? path : null;

  static List<String> _dirList(String? value, List<String> fallback) {
    final dirs = (value ?? '').split(':').where(p.isAbsolute).toList();
    return dirs.isEmpty ? fallback : dirs;
  }
}

const _defaultSection = 'Default Applications';
const _addedSection = 'Added Associations';
const _removedSection = 'Removed Associations';

/// The semicolon-separated desktop ids for [key] in [section] of a
/// `mimeapps.list`.
List<String> readMimeAppsEntry(String contents, String section, String key) {
  String? current;
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      current = line.substring(1, line.length - 1);
      continue;
    }
    if (current != section || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0 || line.substring(0, eq).trim() != key) continue;
    return _splitList(line.substring(eq + 1));
  }
  return const [];
}

/// Rewrites [key] in [section] with `update(currentIds)`, keeping every other
/// line, comment and section as they were. An empty result removes the key.
String writeMimeAppsEntry(String contents, String section, String key, List<String> Function(List<String>) update) {
  final lines = contents.isEmpty ? <String>[] : contents.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  var sectionStart = -1;
  var sectionEnd = lines.length;
  var keyLine = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      if (sectionStart >= 0) {
        sectionEnd = i;
        break;
      }
      if (line.substring(1, line.length - 1) == section) sectionStart = i;
      continue;
    }
    if (sectionStart < 0 || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq >= 0 && line.substring(0, eq).trim() == key) keyLine = i;
  }

  final current = keyLine >= 0 ? _splitList(lines[keyLine].substring(lines[keyLine].indexOf('=') + 1)) : <String>[];
  final ids = update(current);
  final entry = ids.isEmpty ? null : '$key=${ids.join(';')};';

  if (keyLine >= 0) {
    if (entry == null) {
      lines.removeAt(keyLine);
    } else {
      lines[keyLine] = entry;
    }
  } else if (entry != null) {
    if (sectionStart >= 0) {
      // After the section's last entry, before any blank separator lines.
      var insertAt = sectionEnd;
      while (insertAt > sectionStart + 1 && lines[insertAt - 1].trim().isEmpty) {
        insertAt--;
      }
      lines.insert(insertAt, entry);
    } else {
      if (lines.isNotEmpty && lines.last.trim().isNotEmpty) lines.add('');
      lines
        ..add('[$section]')
        ..add(entry);
    }
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// The values of a list key (`MimeType=`, `Categories=`) in the
/// `[Desktop Entry]` group of a desktop file.
List<String> desktopEntryList(String contents, String key) {
  var inMain = false;
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inMain = line == '[Desktop Entry]';
      continue;
    }
    if (!inMain) continue;
    final eq = line.indexOf('=');
    if (eq >= 0 && line.substring(0, eq).trim() == key) return _splitList(line.substring(eq + 1));
  }
  return const [];
}

List<String> _splitList(String value) => [
  for (final part in value.split(';'))
    if (part.trim().isNotEmpty) part.trim(),
];
