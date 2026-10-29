import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plume/src/platform/linux/graphics_engine.dart';

void main() {
  late Directory dir;
  File file() => File(p.join(dir.path, GraphicsEngineSetting.fileName));

  setUp(() => dir = Directory.systemTemp.createTempSync('plume_graphics_engine'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('Impeller unless Skia was chosen', () {
    expect(GraphicsEngineSetting.load(dir.path).value, isFalse);
    file().writeAsStringSync('impeller\n');
    expect(GraphicsEngineSetting.load(dir.path).value, isFalse);
    file().writeAsStringSync('skia\n');
    expect(GraphicsEngineSetting.load(dir.path).value, isTrue);
  });

  test('a choice is saved for the runner and applies after a restart', () async {
    final setting = GraphicsEngineSetting.load(dir.path);
    await setting.choose(skia: true);
    expect(setting.value, isTrue);
    expect(setting.changed, isTrue);
    // linux/runner/my_application.cc reads exactly this.
    expect(file().readAsStringSync().trim(), 'skia');

    final relaunched = GraphicsEngineSetting.load(dir.path);
    expect(relaunched.skiaAtLaunch, isTrue);
    expect(relaunched.changed, isFalse);
    await relaunched.choose(skia: false);
    expect(file().existsSync(), isFalse);
    expect(relaunched.changed, isTrue);
  });
}
