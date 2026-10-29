import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_mime/plume_mime.dart' show MailtoLink;
import 'package:url_launcher/url_launcher.dart';

import '../../state/mail.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../compose/compose_host.dart';
import 'mail_document.dart';
import 'mail_renderer.dart';
import 'message_card.dart' show messageCardColor;
import 'rendered_mail.dart';

/// Inline image bytes, by `accountId/messageId/contentId`.
final _inlineImageProvider =
    FutureProvider.autoDispose.family<Uint8List?, ({String accountId, String messageId, AttachmentInfo info})>(
        (ref, args) async {
  try {
    return await ref.watch(engineProvider).attachment(args.accountId, args.messageId, args.info);
  } catch (_) {
    return null;
  }
});

/// Renders a message body.
///
/// HTML mail is laid out by a browser engine ([MailRenderer]) so it looks
/// as it does in other mail apps. Simple mail adapts to the app theme.
/// Designed HTML mail (newsletters, receipts) is shown on its own page
/// colour in both themes, because such mail hard-codes its colours and
/// breaks when inverted. Remote images are blocked until the user allows
/// them, since they reveal when a message was read.
class MessageBodyView extends ConsumerStatefulWidget {
  const MessageBodyView({super.key, required this.message});

  final Message message;

  @override
  ConsumerState<MessageBodyView> createState() => _MessageBodyViewState();
}

class _MessageBodyViewState extends ConsumerState<MessageBodyView> {
  bool _showImagesOnce = false;
  bool _showQuoted = false;

  /// Set when the engine failed on this message; it then falls back to the
  /// Flutter renderer.
  bool _engineFailed = false;

  String? _remoteCheckedFor;
  bool _hasRemote = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final body = ref.watch(bodyProvider((accountId: m.accountId, messageId: m.id)));
    return body.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: LoadingIndicator(size: 40)),
      ),
      error: (e, _) => _ErrorBody(
        error: e,
        onRetry: () => ref.invalidate(bodyProvider((accountId: m.accountId, messageId: m.id))),
      ),
      data: (body) {
        if (body == null || body.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(m.snippet.isEmpty ? '(This message has no content)' : m.snippet),
          );
        }
        return _buildBody(context, body);
      },
    );
  }

  Widget _buildBody(BuildContext context, MessageBody body) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final sender = widget.message.from?.email.toLowerCase();
    final trusted = settings.remoteImages == RemoteImages.always ||
        _showImagesOnce ||
        (sender != null && settings.trustedImageSenders.contains(sender));

    final html = body.html;
    if (html == null || html.trim().isEmpty) {
      return _PlainBody(text: body.text ?? '', showQuoted: _showQuoted, onToggleQuoted: _toggleQuoted);
    }

    final split = _splitQuoted(html);
    final visibleHtml = _showQuoted || split.quoted == null ? html : split.main;
    final renderer = ref.watch(mailRendererProvider);

    if (renderer != null && renderer.available && !_engineFailed) {
      if (_remoteCheckedFor != visibleHtml) {
        _remoteCheckedFor = visibleHtml;
        _hasRemote = buildMailDocument(visibleHtml, allowRemote: false).hasRemoteContent;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasRemote && !trusted)
            _ImagesBanner(onShow: () => setState(() => _showImagesOnce = true), sender: sender),
          _EngineBody(
            renderer: renderer,
            message: widget.message,
            html: visibleHtml,
            inlineParts: body.inlineParts,
            allowRemote: trusted,
            onOpenLink: _openLink,
            onFailed: () => setState(() => _engineFailed = true),
          ),
          if (split.quoted != null) _QuotedToggle(shown: _showQuoted, onTap: _toggleQuoted),
        ],
      );
    }

    final designed = _isDesigned(html);
    final hasRemote = _remoteImage.hasMatch(html);

    final widgetBody = HtmlWidget(
      visibleHtml,
      key: ValueKey('$designed$trusted$_showQuoted'),
      textStyle: theme.textTheme.bodyLarge?.copyWith(
        color: designed ? const Color(0xFF1F1F1F) : theme.colorScheme.onSurface,
        height: 1.55,
      ),
      renderMode: RenderMode.column,
      factoryBuilder: () => _MailWidgetFactory(
        allowRemote: trusted,
        inlineParts: body.inlineParts,
        resolveCid: _resolveCid,
      ),
      customStylesBuilder: (element) {
        if (designed) return null;
        // Keep quoted history visually quiet in adaptive mode.
        if (element.localName == 'blockquote') {
          return {'margin': '0 0 0 4px', 'padding-left': '12px', 'border-left': '3px solid #8888'};
        }
        return null;
      },
      onTapUrl: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return false;
        _openLink(uri);
        return true;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasRemote && !trusted) _ImagesBanner(onShow: () => setState(() => _showImagesOnce = true), sender: sender),
        if (designed)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: Corners.all(Corners.large),
              border: theme.brightness == Brightness.light ? Border.all(color: theme.colorScheme.outlineVariant) : null,
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(12),
            child: Theme(
              data: theme.copyWith(colorScheme: theme.colorScheme.copyWith(brightness: Brightness.light)),
              child: SelectionArea(child: widgetBody),
            ),
          )
        else
          SelectionArea(child: widgetBody),
        if (split.quoted != null) _QuotedToggle(shown: _showQuoted, onTap: _toggleQuoted),
      ],
    );
  }

  void _toggleQuoted() => setState(() => _showQuoted = !_showQuoted);

  /// Opens a link from the message: `mailto:` in a new message here, web
  /// links in the browser. Others (including the renderer's own scheme,
  /// which relative links resolve to) are ignored.
  void _openLink(Uri uri) {
    switch (uri.scheme.toLowerCase()) {
      case 'mailto':
        final link = MailtoLink.tryParse(uri.toString());
        if (link != null) ref.read(composeProvider.notifier).mailto(link);
      case 'http' || 'https':
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      case 'tel' || 'sms' || 'geo' || 'webcal':
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  Widget _resolveCid(String cid) {
    final info = widget.message.attachments.where((a) => a.contentId == cid).firstOrNull;
    if (info == null) return const SizedBox.shrink();
    final bytes = ref.watch(_inlineImageProvider((accountId: widget.message.accountId, messageId: widget.message.id, info: info)));
    return bytes.when(
      data: (b) => b == null ? const SizedBox.shrink() : Image.memory(b, fit: BoxFit.contain),
      loading: () => const SizedBox(height: 48, child: Center(child: LoadingIndicator(size: 28))),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

final _remoteImage = RegExp(r'''<img[^>]+src\s*=\s*["']?https?://''', caseSensitive: false);
final _designMarkers = RegExp(r'bgcolor\s*=|background(-color)?\s*:|<table[^>]*width\s*=\s*"?[3-9]\d\d', caseSensitive: false);

bool _isDesigned(String html) => _designMarkers.allMatches(html).length >= 2;

/// Splits off quoted history (Gmail, Apple Mail, Outlook markers) so long
/// threads read cleanly; the history stays one click away.
({String main, String? quoted}) _splitQuoted(String html) {
  const markers = [
    '<div class="gmail_quote',
    '<blockquote type="cite"',
    '<div id="appendonsend"',
    '<div id="divRplyFwdMsg"',
    '<div class="moz-cite-prefix"',
  ];
  var cut = -1;
  for (final m in markers) {
    final i = html.indexOf(m);
    if (i > 0 && (cut < 0 || i < cut)) cut = i;
  }
  if (cut < 0) return (main: html, quoted: null);
  return (main: html.substring(0, cut), quoted: html.substring(cut));
}

/// HTML rendered by the [MailRenderer] at the available width, re-rendered
/// when the width, theme or image setting changes (showing the previous
/// rendering, scaled, until the new one is ready).
class _EngineBody extends ConsumerStatefulWidget {
  const _EngineBody({
    required this.renderer,
    required this.message,
    required this.html,
    required this.inlineParts,
    required this.allowRemote,
    required this.onOpenLink,
    required this.onFailed,
  });

  final MailRenderer renderer;
  final Message message;
  final String html;
  final Map<String, Uint8List> inlineParts;
  final bool allowRemote;
  final ValueChanged<Uri> onOpenLink;
  final VoidCallback onFailed;

  @override
  ConsumerState<_EngineBody> createState() => _EngineBodyState();
}

/// Everything a rendering depends on.
typedef _RenderParams = ({
  String key,
  String content,
  double width,
  double devicePixelRatio,
  Color background,
  Color text,
  Color link,
  double fontSize,
});

class _EngineBodyState extends ConsumerState<_EngineBody> {
  MailRenderLease? _shownLease;
  MailRendering? _shown;
  String? _shownKey;
  String? _shownContent;

  MailRenderLease? _pendingLease;
  String? _pendingKey;
  Timer? _start;

  /// Shows progress once the first rendering takes a moment.
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _shown == null) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _slowTimer?.cancel();
    _pendingLease?.release();
    _shownLease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final m = widget.message;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.floorToDouble();
      final background = messageCardColor(scheme);
      final fontSize = theme.textTheme.bodyLarge?.fontSize ?? 16;
      // What is rendered and how, apart from the width.
      final content = [
        m.accountId,
        m.id,
        widget.html.length,
        widget.html.hashCode,
        widget.allowRemote,
        background.toARGB32(),
        scheme.onSurface.toARGB32(),
        scheme.primary.toARGB32(),
        fontSize,
      ].join('|');
      _request((
        key: '$content|$width|$dpr',
        content: content,
        width: width,
        devicePixelRatio: dpr,
        background: background,
        text: scheme.onSurface,
        link: scheme.primary,
        fontSize: fontSize,
      ));

      final shown = _shown;
      if (shown == null) {
        return SizedBox(
          height: 48,
          child: _slow ? const Center(child: LoadingIndicator(size: 32)) : null,
        );
      }
      final rendered = RenderedMail(rendering: shown, width: width, onOpenLink: widget.onOpenLink);
      if (!shown.designed) return rendered;
      return Container(
        decoration: BoxDecoration(color: shown.background, borderRadius: Corners.all(Corners.large)),
        foregroundDecoration: theme.brightness == Brightness.light
            ? BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: Corners.all(Corners.large))
            : null,
        clipBehavior: Clip.antiAlias,
        child: rendered,
      );
    });
  }

  /// Starts rendering [p] unless it is shown or on its way. Called during
  /// layout, so it only schedules work.
  void _request(_RenderParams p) {
    if (p.key == _pendingKey) return;
    if (p.key == _shownKey) {
      _cancelPending();
      return;
    }
    _cancelPending();
    _pendingKey = p.key;
    // While a window is being resized, wait for the width to settle; the
    // current rendering is scaled meanwhile.
    final resizing = _shown != null && p.content == _shownContent;
    _start = Timer(resizing ? const Duration(milliseconds: 150) : Duration.zero, () => _begin(p));
  }

  void _cancelPending() {
    _start?.cancel();
    _start = null;
    _pendingLease?.release();
    _pendingLease = null;
    _pendingKey = null;
  }

  void _begin(_RenderParams p) {
    if (!mounted || p.key != _pendingKey) return;
    final lease = _pendingLease = widget.renderer.lease(p.key, () => _buildRequest(p));
    lease.rendering.then((rendering) {
      if (!mounted || !identical(lease, _pendingLease)) return;
      setState(() {
        _shownLease?.release();
        _shownLease = lease;
        _shown = rendering;
        _shownKey = p.key;
        _shownContent = p.content;
        _pendingLease = null;
        _pendingKey = null;
      });
    }, onError: (Object error) {
      if (!mounted || !identical(lease, _pendingLease) || error is MailRenderCancelled) return;
      _cancelPending();
      widget.onFailed();
    });
  }

  Future<MailRenderRequest> _buildRequest(_RenderParams p) async {
    final document = buildMailDocument(
      widget.html,
      allowRemote: widget.allowRemote,
      inlineParts: await _inlineParts(),
    );
    return MailRenderRequest(
      html: document.html,
      width: p.width,
      devicePixelRatio: p.devicePixelRatio,
      background: p.background,
      text: p.text,
      link: p.link,
      fontSize: p.fontSize,
      lineHeight: 1.55,
    );
  }

  /// The parts the HTML references by Content-ID, downloading those the
  /// provider did not return with the body.
  Future<Map<String, InlinePart>> _inlineParts() async {
    final ids = referencedContentIds(widget.html);
    if (ids.isEmpty) return const {};
    final m = widget.message;
    final engine = ref.read(engineProvider);
    final provided = {for (final e in widget.inlineParts.entries) normalizeContentId(e.key): e.value};
    final parts = <String, InlinePart>{};
    await Future.wait([
      for (final id in ids)
        () async {
          final info = m.attachments
              .where((a) => a.contentId != null && normalizeContentId(a.contentId!) == id)
              .firstOrNull;
          var bytes = provided[id];
          if (bytes == null && info != null) {
            try {
              bytes = await engine.attachment(m.accountId, m.id, info);
            } catch (_) {
              // Shown as a missing image.
            }
          }
          if (bytes != null) parts[id] = (mimeType: _imageType(info?.mimeType, bytes), bytes: bytes);
        }(),
    ]);
    return parts;
  }

  static String _imageType(String? declared, Uint8List bytes) {
    if (declared != null && declared.startsWith('image/')) return declared;
    bool starts(List<int> magic) {
      if (bytes.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts(const [0x47, 0x49, 0x46])) return 'image/gif';
    if (bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') return 'image/webp';
    return declared ?? 'image/png';
  }
}

class _MailWidgetFactory extends WidgetFactory {
  _MailWidgetFactory({required this.allowRemote, required this.inlineParts, required this.resolveCid});

  final bool allowRemote;
  final Map<String, Uint8List> inlineParts;
  final Widget Function(String cid) resolveCid;

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url;
    if (url.startsWith('cid:')) {
      final cid = Uri.decodeComponent(url.substring(4)).replaceAll(RegExp('[<>]'), '');
      final bytes = inlineParts[cid];
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
      return resolveCid(cid);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final w = src.width ?? 0, h = src.height ?? 0;
      // Tracking pixels and spacers vanish either way.
      if ((w > 0 && w <= 2) || (h > 0 && h <= 2)) return const SizedBox.shrink();
      if (!allowRemote) return _BlockedImage(width: w > 0 ? w : null, height: h > 0 ? h : null, alt: src.image?.alt);
    }
    return super.buildImageWidget(tree, src);
  }
}

class _BlockedImage extends StatelessWidget {
  const _BlockedImage({this.width, this.height, this.alt});

  final double? width;
  final double? height;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width?.clamp(24, 600),
      height: (height ?? 48).clamp(24, 160),
      decoration: BoxDecoration(color: const Color(0x14000000), borderRadius: Corners.all(Corners.small)),
      alignment: Alignment.center,
      child: alt == null || alt!.isEmpty
          ? Icon(Symbols.image_rounded, size: 20, color: scheme.outline)
          : Padding(
              padding: const EdgeInsets.all(4),
              child: Text(alt!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12)),
            ),
    );
  }
}

class _ImagesBanner extends ConsumerWidget {
  const _ImagesBanner({required this.onShow, required this.sender});

  final VoidCallback onShow;
  final String? sender;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: LayoutBuilder(builder: (context, constraints) {
            final message = Row(
              children: [
                Icon(Symbols.hide_image_rounded, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Images are hidden so the sender can’t tell you opened this.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            );
            final buttons = [
              TextButton(onPressed: onShow, child: const Text('Show images')),
              if (sender != null)
                TextButton(
                  onPressed: () => ref.read(settingsProvider.notifier).update(
                      (s) => s.copyWith(trustedImageSenders: {...s.trustedImageSenders, sender!})),
                  child: const Text('Always from sender'),
                ),
            ];
            // Narrow panes put the buttons under the message.
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: message),
                  Wrap(alignment: WrapAlignment.end, children: buttons),
                ],
              );
            }
            return Row(children: [Expanded(child: message), ...buttons]);
          }),
        ),
      ),
    );
  }
}

class _QuotedToggle extends StatelessWidget {
  const _QuotedToggle({required this.shown, required this.onTap});

  final bool shown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Tooltip(
          message: shown ? 'Hide quoted text' : 'Show quoted text',
          child: Material(
            color: scheme.surfaceContainerHighest,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Icon(shown ? Symbols.unfold_less_rounded : Symbols.more_horiz_rounded, size: 20, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain-text bodies: linkified, with quoted lines collapsed.
class _PlainBody extends StatelessWidget {
  const _PlainBody({required this.text, required this.showQuoted, required this.onToggleQuoted});

  final String text;
  final bool showQuoted;
  final VoidCallback onToggleQuoted;

  static final _link = RegExp(r'(https?://[^\s<>"]+[^\s<>".,;:!?)\]])|([\w.+-]+@[\w-]+\.[\w.-]+)');
  static final _quoteStart = RegExp(r'^(>|On .+wrote:$|-----Original Message-----)', multiLine: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = _quoteStart.firstMatch(text);
    final cut = match?.start ?? -1;
    final main = cut > 0 && !showQuoted ? text.substring(0, cut).trimRight() : text;

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _link.allMatches(main)) {
      if (m.start > last) spans.add(TextSpan(text: main.substring(last, m.start)));
      final value = m.group(0)!;
      final uri = m.group(1) != null ? Uri.parse(value) : Uri(scheme: 'mailto', path: value);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
            child: Text(value, style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
              height: 1.55,
            )),
          ),
        ),
      ));
      last = m.end;
    }
    if (last < main.length) spans.add(TextSpan(text: main.substring(last)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(TextSpan(children: spans), style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
        if (cut > 0) _QuotedToggle(shown: showQuoted, onTap: onToggleQuoted),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = error is TransientException;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(offline ? Symbols.cloud_off_rounded : Symbols.error_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(offline ? 'You’re offline. This message hasn’t been downloaded yet.' : 'Couldn’t load this message.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
          IconButton(
            tooltip: 'Copy error',
            onPressed: () => Clipboard.setData(ClipboardData(text: '$error')),
            icon: const Icon(Symbols.content_copy_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
