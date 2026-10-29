import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../platform/linux/linux_desktop.dart' show linuxDesktopSupported;
import 'mail_scripts.dart';

final _log = Logger('plume.reader.renderer');

/// The engine that renders HTML mail, or null where there is none (tests,
/// platforms without the GTK runner). Readers fall back to a Flutter
/// renderer then.
final mailRendererProvider = Provider<MailRenderer?>((ref) => linuxDesktopSupported ? MailRenderer() : null);

/// What to render.
final class MailRenderRequest {
  const MailRenderRequest({
    required this.html,
    required this.width,
    required this.devicePixelRatio,
    required this.background,
    required this.text,
    required this.link,
    required this.fontSize,
    required this.lineHeight,
  });

  /// A document from `buildMailDocument`.
  final String html;

  /// Layout width in logical pixels.
  final double width;
  final double devicePixelRatio;

  /// Colours for simple mail, which takes the app's look. Designed mail
  /// keeps its own.
  final ui.Color background;
  final ui.Color text;
  final ui.Color link;
  final double fontSize;
  final double lineHeight;
}

/// A rendered message: its pixels, in tiles from top to bottom, and the
/// text and links to overlay on them. Geometry is in CSS pixels of the
/// rendered layout; [viewportWidth] of them span the image's width.
final class MailRendering {
  MailRendering({
    required this.tiles,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.viewportWidth,
    required this.designed,
    required this.background,
    required this.runs,
    required this.links,
  });

  final List<ui.Image> tiles;
  final int pixelWidth;
  final int pixelHeight;
  final double viewportWidth;

  /// Whether the message paints its own backgrounds (newsletters,
  /// receipts) and is shown on its own page colour, [background].
  final bool designed;
  final ui.Color background;
  final List<MailTextRun> runs;
  final List<MailLink> links;

  int get pixels => pixelWidth * pixelHeight;

  /// Height for a given display [width].
  double heightFor(double width) => pixelHeight * width / pixelWidth;

  void dispose() {
    for (final tile in tiles) {
      tile.dispose();
    }
  }
}

/// Text from one line of a text node, for selecting and copying.
final class MailTextRun {
  const MailTextRun({
    required this.text,
    required this.rect,
    required this.separator,
    required this.fontSize,
    required this.fontWeight,
    required this.italic,
    required this.families,
  });

  final String text;
  final ui.Rect rect;

  /// What separates this run from the previous one when copied: nothing,
  /// a line or paragraph break, or a tab between table cells.
  final String separator;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final List<String> families;
}

final class MailLink {
  const MailLink({required this.uri, required this.title, required this.rects});

  final Uri uri;
  final String title;
  final List<ui.Rect> rects;
}

/// Thrown to callers waiting on a render that nobody needs any more.
final class MailRenderCancelled implements Exception {
  const MailRenderCancelled();
}

/// A claim on a rendering. Renders nobody holds may be cancelled (while in
/// progress) or evicted from the cache (when done).
final class MailRenderLease {
  MailRenderLease._(this._renderer, this._key, this._entry);

  final MailRenderer _renderer;
  final String _key;
  final _Entry _entry;
  var _released = false;

  Future<MailRendering> get rendering => _entry.future;

  void release() {
    if (_released) return;
    _released = true;
    _renderer._release(_key, _entry);
  }
}

class _Entry {
  late final Future<MailRendering> future;
  MailRendering? value;
  int? id;
  var holders = 0;
  var cancelled = false;
}

/// Renders HTML mail through the GTK runner's WebKit engine
/// (`plume/mail_renderer`), caching recent results.
class MailRenderer {
  MailRenderer([this._channel = const MethodChannel('plume/mail_renderer')]);

  final MethodChannel _channel;

  /// Renderings kept for messages that are no longer shown, by count and
  /// by total pixels.
  static const _cacheEntries = 16;
  static const _cachePixels = 48 * 1024 * 1024;

  /// Pixels of one rendering; taller messages are rendered at a lower
  /// resolution.
  static const _maxPixels = 24 * 1024 * 1024;

  /// Least recently used first.
  final _entries = <String, _Entry>{};
  var _nextId = 1;
  var _available = true;
  var _warm = false;

  /// False once the runner turned out not to implement the channel.
  bool get available => _available;

  /// Starts the web engine ahead of the first message.
  void warmUp() {
    if (_warm || !_available) return;
    _warm = true;
    unawaited(_channel.invokeMethod<void>('warmUp').catchError((Object e) {
      if (e is MissingPluginException) _available = false;
    }));
  }

  /// Returns a lease on the rendering cached under [key], starting it with
  /// [request] if there is none.
  MailRenderLease lease(String key, Future<MailRenderRequest> Function() request) {
    var entry = _entries.remove(key);
    if (entry == null) {
      final created = entry = _Entry();
      created.future = _render(key, created, request)..ignore();
    }
    _entries[key] = entry;
    entry.holders++;
    return MailRenderLease._(this, key, entry);
  }

  void _release(String key, _Entry entry) {
    entry.holders--;
    if (entry.holders > 0) return;
    if (entry.value == null) {
      // Nobody waits for it any more.
      entry.cancelled = true;
      if (identical(_entries[key], entry)) _entries.remove(key);
      final id = entry.id;
      if (id != null) unawaited(_channel.invokeMethod<void>('cancel', {'id': id}).catchError((Object _) {}));
    }
    _trim();
  }

  /// Evicts the least recently used renderings nobody holds.
  void _trim() {
    var count = 0, pixels = 0;
    for (final e in _entries.values) {
      if (e.holders == 0 && e.value != null) {
        count++;
        pixels += e.value!.pixels;
      }
    }
    final evict = <String>[];
    for (final MapEntry(:key, value: e) in _entries.entries) {
      if (count <= _cacheEntries && pixels <= _cachePixels) break;
      if (e.holders > 0 || e.value == null) continue;
      evict.add(key);
      count--;
      pixels -= e.value!.pixels;
    }
    for (final key in evict) {
      _entries.remove(key)!.value!.dispose();
    }
  }

  Future<MailRendering> _render(String key, _Entry entry, Future<MailRenderRequest> Function() build) async {
    try {
      final request = await build();
      if (entry.cancelled) throw const MailRenderCancelled();
      final id = entry.id = _nextId++;
      final Map<Object?, Object?>? result;
      try {
        result = await _channel.invokeMapMethod<Object?, Object?>('render', {
          'id': id,
          'html': request.html,
          'width': request.width,
          'scale': request.devicePixelRatio,
          'background': request.background.toARGB32(),
          'maxPixels': _maxPixels,
          'prepare': prepareMailScript,
          'collect': collectMailScript,
          'options': jsonEncode({
            'theme': {
              'background': _css(request.background),
              'text': _css(request.text),
              'link': _css(request.link),
            },
            'fontSize': request.fontSize,
            'lineHeight': request.lineHeight,
            'padding': 12,
          }),
        });
      } on PlatformException catch (e) {
        if (e.code == 'cancelled') throw const MailRenderCancelled();
        rethrow;
      } on MissingPluginException {
        _available = false;
        rethrow;
      }
      final rendering = await _decode(result!);
      if (entry.cancelled) {
        rendering.dispose();
        throw const MailRenderCancelled();
      }
      _log.fine('Rendered ${rendering.pixelWidth}×${rendering.pixelHeight} in ${result['elapsedMs']} ms');
      entry.value = rendering;
      _trim();
      return rendering;
    } catch (e) {
      if (identical(_entries[key], entry)) _entries.remove(key);
      if (e is! MailRenderCancelled) _log.warning('Couldn’t render a message', e);
      rethrow;
    }
  }

  static Future<MailRendering> _decode(Map<Object?, Object?> map) async {
    final width = map['width']! as int;
    final height = map['height']! as int;
    final tileRows = map['tileRows']! as int;
    final tiles = (map['tiles']! as List<Object?>).cast<Uint8List>();
    final images = await Future.wait([
      for (var i = 0; i < tiles.length; i++) _image(tiles[i], width, math.min(tileRows, height - i * tileRows)),
    ]);
    final prepared = jsonDecode(map['prepared']! as String) as Map<String, Object?>;
    final collected = jsonDecode(map['collected']! as String) as Map<String, Object?>;

    ui.Rect rect(Object? value) {
      final r = (value! as List<Object?>).cast<num>();
      return ui.Rect.fromLTWH(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble());
    }

    return MailRendering(
      tiles: images,
      pixelWidth: width,
      pixelHeight: height,
      viewportWidth: (map['viewportWidth']! as num).toDouble(),
      designed: prepared['designed'] == true,
      background: _parseColor(prepared['background'] as String?) ?? const ui.Color(0xFFFFFFFF),
      runs: [
        for (final run in (collected['runs']! as List<Object?>).cast<Map<String, Object?>>())
          MailTextRun(
            text: run['t']! as String,
            rect: rect(run['r']),
            separator: run['b'] as String? ?? '',
            fontSize: (run['s'] as num? ?? 16).toDouble(),
            fontWeight: run['w'] as int? ?? 400,
            italic: run['i'] == true,
            families: (run['f'] as List<Object?>? ?? const []).cast<String>(),
          ),
      ],
      links: [
        for (final link in (collected['links']! as List<Object?>).cast<Map<String, Object?>>())
          if (Uri.tryParse(link['h']! as String) case final uri?)
            MailLink(
              uri: uri,
              title: link['t'] as String? ?? '',
              rects: [for (final r in link['r']! as List<Object?>) rect(r)],
            ),
      ],
    );
  }

  static Future<ui.Image> _image(Uint8List pixels, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  static String _css(ui.Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static ui.Color? _parseColor(String? css) {
    if (css == null || !css.startsWith('#') || css.length != 7) return null;
    final value = int.tryParse(css.substring(1), radix: 16);
    return value == null ? null : ui.Color(0xFF000000 | value);
  }
}
