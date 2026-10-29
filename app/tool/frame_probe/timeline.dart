// Records the VM timeline of a running profile build for a few seconds and
// prints where each thread's time went, busiest first. Not part of the app.
//
//   dart run tool/frame_probe/timeline.dart <vm-service-uri> [seconds]
//
// The URI is the "Dart VM service is listening on" line a profile build
// prints at startup.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final http = Uri.parse(args[0]);
  final seconds = args.length > 1 ? int.parse(args[1]) : 5;
  final socket = await WebSocket.connect(
    http.replace(scheme: 'ws', path: '${http.path}ws').toString(),
  );
  final replies = <int, Completer<Map<String, Object?>>>{};
  socket.listen((message) {
    final reply = jsonDecode(message as String) as Map<String, Object?>;
    replies.remove(int.tryParse('${reply['id']}'))?.complete(reply);
  });
  var nextId = 0;
  Future<Map<String, Object?>> call(String method, [Map<String, Object?> params = const {}]) {
    final id = nextId++;
    socket.add(jsonEncode({'jsonrpc': '2.0', 'id': '$id', 'method': method, 'params': params}));
    return (replies[id] = Completer()).future;
  }

  await call('setVMTimelineFlags', {
    'recordedStreams': ['Dart', 'Embedder', 'GC'],
  });
  await call('clearVMTimeline');
  await Future<void>.delayed(Duration(seconds: seconds));
  final reply = await call('getVMTimeline');
  await socket.close();
  final events = ((reply['result'] as Map)['traceEvents'] as List).cast<Map<String, Object?>>();

  // Time per thread and event, from complete ("X") and begin/end pairs.
  final threads = <Object?, String>{};
  final total = <(Object?, String), double>{};
  final count = <(Object?, String), int>{};
  final open = <(Object?, String), List<num>>{};
  for (final e in events) {
    final key = (e['tid'], e['name'] as String? ?? '?');
    switch (e['ph']) {
      case 'M' when e['name'] == 'thread_name':
        threads[e['tid']] = (e['args'] as Map)['name'] as String;
      case 'X':
        total[key] = (total[key] ?? 0) + (e['dur'] as num) / 1000;
        count[key] = (count[key] ?? 0) + 1;
      case 'B':
        (open[key] ??= []).add(e['ts'] as num);
      case 'E' when open[key]?.isNotEmpty ?? false:
        total[key] = (total[key] ?? 0) + ((e['ts'] as num) - open[key]!.removeLast()) / 1000;
        count[key] = (count[key] ?? 0) + 1;
    }
  }

  final rows = total.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('ms per s  count  thread / event (over $seconds s)');
  for (final MapEntry(key: (tid, name), :value) in rows.take(40)) {
    stdout.writeln(
      '${(value / seconds).toStringAsFixed(1).padLeft(8)}  '
      '${count[(tid, name)].toString().padLeft(5)}  '
      '${(threads[tid] ?? '$tid').padRight(20)} $name',
    );
  }
}
