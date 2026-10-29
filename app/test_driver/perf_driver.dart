import 'dart:io';
import 'dart:math' as math;

import 'package:integration_test/integration_test_driver.dart';

/// Prints how many frames of each motion missed the display's frame budget
/// and writes the full report to build/perf/motion_perf.json.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        await writeResponseData(data, testOutputFilename: 'motion_perf', destinationDirectory: 'build/perf');
        final window = data['window'] as Map<String, dynamic>? ?? const {};
        final rate = (window['refresh_rate'] as num?)?.toDouble() ?? 0;
        final hz = rate > 0 ? rate : 60.0;
        final budget = 1000 / hz;
        stdout.writeln('\nWindow ${window['width']}×${window['height']} @${hz.round()} Hz, '
            'budget ${budget.toStringAsFixed(1)} ms per frame (build and raster each)\n');
        stdout.writeln('${'motion'.padRight(22)}${'frames'.padLeft(7)}${'missed'.padLeft(8)}'
            '${'build p90/worst'.padLeft(18)}${'raster p90/worst'.padLeft(19)}');
        for (final MapEntry(:key, :value) in data.entries) {
          if (key == 'window' || value is! Map<String, dynamic>) continue;
          if (key == 'idle') {
            stdout.writeln('${'idle'.padRight(22)}${value['running_animations']} animations running');
            continue;
          }
          if (value.containsKey('traceEvents')) {
            _printBuildCosts(key, (value['traceEvents'] as List).cast<Map<String, dynamic>>());
            continue;
          }
          final build = (value['frame_build_times'] as List).cast<int>();
          final raster = (value['frame_rasterizer_times'] as List).cast<int>();
          var missed = 0;
          for (var i = 0; i < math.min(build.length, raster.length); i++) {
            if (build[i] / 1000 > budget || raster[i] / 1000 > budget) missed++;
          }
          String ms(String k) => (value[k] as num).toStringAsFixed(1);
          stdout.writeln('${key.padRight(22)}${'${value['frame_count']}'.padLeft(7)}${'$missed'.padLeft(8)}'
              '${'${ms('90th_percentile_frame_build_time_millis')}/${ms('worst_frame_build_time_millis')}'.padLeft(18)}'
              '${'${ms('90th_percentile_frame_rasterizer_time_millis')}/${ms('worst_frame_rasterizer_time_millis')}'.padLeft(19)}');
        }
      },
    );

/// The widgets that took the most time to build, by their own time
/// (excluding their children's).
void _printBuildCosts(String title, List<Map<String, dynamic>> events) {
  final own = <String, int>{};
  final counts = <String, int>{};
  final stacks = <Object?, List<(String, int, int)>>{};
  final timed = events.where((e) => e['ts'] is num).toList()
    ..sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
  for (final e in timed) {
    final stack = stacks.putIfAbsent(e['tid'], () => []);
    final ts = (e['ts'] as num).toInt();
    switch (e['ph']) {
      case 'B':
        stack.add((e['name'] as String, ts, 0));
      case 'E' when stack.isNotEmpty:
        final (name, start, children) = stack.removeLast();
        final total = ts - start;
        own[name] = (own[name] ?? 0) + total - children;
        counts[name] = (counts[name] ?? 0) + 1;
        if (stack.isNotEmpty) {
          final (pName, pStart, pChildren) = stack.removeLast();
          stack.add((pName, pStart, pChildren + total));
        }
    }
  }
  final top = own.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('\n$title: most build time by widget (own ms, count)');
  for (final e in top.take(30)) {
    stdout.writeln('  ${(e.value / 1000).toStringAsFixed(1).padLeft(8)}  ${'${counts[e.key]}'.padLeft(6)}  ${e.key}');
  }
}
