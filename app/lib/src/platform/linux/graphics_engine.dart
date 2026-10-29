import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Whether Flutter draws with Skia ("Compatible") instead of Impeller, which
/// can run better on some graphics chips; on Intel integrated graphics Skia
/// has rasterised frames faster.
///
/// The runner picks the engine before Flutter starts
/// (linux/runner/my_application.cc), so the choice can't live in the settings
/// database: it's a file next to it holding `skia`, and changing it applies
/// on the next launch.
final class GraphicsEngineSetting extends ValueNotifier<bool> {
  GraphicsEngineSetting._(this._file, bool skia)
      : skiaAtLaunch = skia,
        super(skia);

  /// Reads the setting from Plume's data directory.
  factory GraphicsEngineSetting.load(String dataDir) {
    final file = File(p.join(dataDir, fileName));
    var skia = false;
    try {
      skia = file.readAsStringSync().trim() == 'skia';
    } on FileSystemException {
      // Never chosen: Impeller.
    }
    return GraphicsEngineSetting._(file, skia);
  }

  static const fileName = 'graphics-engine';

  final File _file;

  /// Whether this run draws with Skia.
  final bool skiaAtLaunch;

  /// Whether the choice only applies after a restart.
  bool get changed => value != skiaAtLaunch;

  Future<void> choose({required bool skia}) async {
    if (skia) {
      await _file.writeAsString('skia\n');
    } else if (await _file.exists()) {
      await _file.delete();
    }
    value = skia;
  }
}
