import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'mail_renderer.dart';

/// Shows a [MailRendering] at [width]: the engine's pixels, with invisible
/// text laid over the words for selection and copying, and the links.
class RenderedMail extends StatefulWidget {
  const RenderedMail({super.key, required this.rendering, required this.width, required this.onOpenLink});

  final MailRendering rendering;
  final double width;
  final ValueChanged<Uri> onOpenLink;

  @override
  State<RenderedMail> createState() => _RenderedMailState();
}

class _RenderedMailState extends State<RenderedMail> {
  final _layer = GlobalKey();
  late final _selection = _MailSelectionDelegate(_separatorBefore);

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// CSS pixels to logical pixels.
  double get _scale => widget.width / widget.rendering.viewportWidth;

  /// The separator of the run a selected fragment of text belongs to.
  String _separatorBefore(Selectable selectable) {
    final box = _layer.currentContext?.findRenderObject();
    if (box is! RenderBox) return '';
    final origin = MatrixUtils.transformPoint(selectable.getTransformTo(box), Offset.zero) / _scale;
    MailTextRun? best;
    var bestDistance = double.infinity;
    for (final run in widget.rendering.runs) {
      final distance = (run.rect.topLeft - origin).distanceSquared;
      if (distance < bestDistance) {
        best = run;
        bestDistance = distance;
      }
    }
    return best?.separator ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final rendering = widget.rendering;
    final scale = _scale;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Rect place(Rect r) => Rect.fromLTWH(r.left * scale, r.top * scale, r.width * scale, r.height * scale);

    return SizedBox(
      width: widget.width,
      height: rendering.heightFor(widget.width),
      child: SelectionArea(
        child: SelectionContainer(
          delegate: _selection,
          child: Stack(
            key: _layer,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _TilesPainter(rendering, devicePixelRatio: dpr)),
                ),
              ),
              for (final run in rendering.runs) Positioned.fromRect(rect: place(run.rect), child: _TextRun(run: run)),
              for (final link in rendering.links)
                for (final rect in link.rects)
                  Positioned.fromRect(
                    rect: place(rect),
                    child: _LinkArea(link: link, onOpen: () => widget.onOpenLink(link.uri)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the tiles edge to edge, scaled to the widget's width.
class _TilesPainter extends CustomPainter {
  _TilesPainter(this.rendering, {required this.devicePixelRatio});

  final MailRendering rendering;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / rendering.pixelWidth;
    // At one image pixel per device pixel, sampling would only blur.
    final exact = (k * devicePixelRatio - 1).abs() < 0.01;
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = exact ? FilterQuality.none : FilterQuality.medium;
    var top = 0.0;
    for (final tile in rendering.tiles) {
      final height = tile.height * k;
      canvas.drawImageRect(
        tile,
        Rect.fromLTWH(0, 0, tile.width.toDouble(), tile.height.toDouble()),
        Rect.fromLTWH(0, top, size.width, height),
        paint,
      );
      top += height;
    }
  }

  @override
  bool shouldRepaint(_TilesPainter old) => old.rendering != rendering || old.devicePixelRatio != devicePixelRatio;
}

/// A run of invisible text stretched over the same words in the image, so
/// selection highlights land on them.
class _TextRun extends StatelessWidget {
  const _TextRun({required this.run});

  final MailTextRun run;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: Text(
          run.text,
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: const Color(0x00000000),
            fontSize: run.fontSize,
            fontWeight: FontWeight.values[((run.fontWeight / 100).round() - 1).clamp(0, 8)],
            fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
            fontFamily: run.families.firstOrNull,
            fontFamilyFallback: run.families.skip(1).toList(),
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _LinkArea extends StatelessWidget {
  const _LinkArea({required this.link, required this.onOpen});

  final MailLink link;
  final VoidCallback onOpen;

  /// What hovering shows: where the link really goes.
  String get _target {
    final uri = link.uri;
    final text = uri.scheme == 'mailto' ? uri.path : uri.toString();
    return text.length > 160 ? '${text.substring(0, 157)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _target,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onOpen),
      ),
    );
  }
}

/// Copies selected runs joined by their separators (line breaks, tabs),
/// rather than run together.
class _MailSelectionDelegate extends StaticSelectionContainerDelegate {
  _MailSelectionDelegate(this.separatorBefore);

  final String Function(Selectable selectable) separatorBefore;

  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    var any = false;
    for (final selectable in selectables) {
      final text = selectable.getSelectedContent()?.plainText;
      if (text == null || text.isEmpty) continue;
      if (any) buffer.write(separatorBefore(selectable));
      buffer.write(text);
      any = true;
    }
    return any ? SelectedContent(plainText: buffer.toString().trimRight()) : null;
  }
}
