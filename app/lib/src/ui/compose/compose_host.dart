import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_mime/plume_mime.dart' show MailtoLink;

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/settings.dart';
import 'compose_panel.dart';

enum ComposeMode { fresh, reply, replyAll, forward }

/// The initial content of a compose window.
@immutable
final class ComposeRequest {
  const ComposeRequest({
    required this.id,
    required this.mode,
    this.accountId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.html,
    this.plainText = false,
    this.quoted,
    this.threadId,
    this.inReplyTo,
    this.references = const [],
    this.draftId,
    this.forwardFrom,
    this.attachments = const [],
  });

  final int id;
  final ComposeMode mode;
  final String? accountId;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;
  final String body;

  /// Formatted body; takes the place of [body] when set.
  final String? html;

  /// Compose in plain text: no formatting and no HTML part.
  final bool plainText;

  /// The original message, quoted below the reply.
  final Message? quoted;
  final String? threadId;
  final String? inReplyTo;
  final List<String> references;
  final String? draftId;

  /// For forwards: the message whose attachments come along.
  final Message? forwardFrom;
  final List<OutgoingAttachment> attachments;
}

/// Open compose windows.
final composeProvider = NotifierProvider<ComposeNotifier, List<ComposeRequest>>(
  ComposeNotifier.new,
);

class ComposeNotifier extends Notifier<List<ComposeRequest>> {
  int _next = 1;

  @override
  List<ComposeRequest> build() => const [];

  String? _defaultAccount() {
    final view = ref.read(viewProvider);
    if (view.accountId != null) return view.accountId;
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    return accounts.isEmpty ? null : accounts.first.id;
  }

  void newMessage({List<Address> to = const [], Rect? origin}) {
    // Only one blank message at a time; focus it instead of stacking.
    final blank = state
        .where((r) => r.mode == ComposeMode.fresh && r.to.isEmpty && to.isEmpty)
        .firstOrNull;
    if (blank != null) return;
    _open(
      ComposeRequest(
        id: _next++,
        mode: ComposeMode.fresh,
        accountId: _defaultAccount(),
        to: to,
      ),
      origin: origin ?? ComposeAnchor.rectOf(ComposeSource.compose),
    );
  }

  /// Opens a message prefilled from a `mailto:` link.
  void mailto(MailtoLink link) {
    if (link.isEmpty) return newMessage();
    _open(
      ComposeRequest(
        id: _next++,
        mode: ComposeMode.fresh,
        accountId: _defaultAccount(),
        to: link.to,
        cc: link.cc,
        bcc: link.bcc,
        subject: link.subject,
        body: link.body,
        inReplyTo: link.inReplyTo,
        references: [?link.inReplyTo],
      ),
    );
  }

  /// [origin] is the control that asked for the reply, in global
  /// coordinates; the reply toolbar when not given.
  void reply(Message m, {required bool all, Rect? origin}) {
    final account = ref.read(accountMapProvider)[m.accountId];
    final me = account?.email.toLowerCase() ?? '';
    bool notMe(Address a) => a.email.toLowerCase() != me;
    final fromMe = m.from != null && !notMe(m.from!);

    final to = fromMe ? m.to : (m.replyTo.isNotEmpty ? m.replyTo : [?m.from]);
    final cc = all
        ? [...m.to, ...m.cc]
              .where(notMe)
              .where(
                (a) => !to.any(
                  (t) => t.email.toLowerCase() == a.email.toLowerCase(),
                ),
              )
              .toList()
        : const <Address>[];
    _open(
      ComposeRequest(
        id: _next++,
        mode: all ? ComposeMode.replyAll : ComposeMode.reply,
        accountId: m.accountId,
        to: _dedupe(to),
        cc: _dedupe(cc),
        subject: _prefixed('Re:', m.subject),
        quoted: m,
        threadId: m.threadId,
        inReplyTo: m.messageIdHeader,
        references: [...m.references, ?m.messageIdHeader],
      ),
      origin: origin ?? ComposeAnchor.rectOf(ComposeSource.reply),
    );
  }

  void forward(Message m, {Rect? origin}) {
    _open(
      ComposeRequest(
        id: _next++,
        mode: ComposeMode.forward,
        accountId: m.accountId,
        subject: _prefixed('Fwd:', m.subject),
        quoted: m,
        forwardFrom: m,
      ),
      origin: origin ?? ComposeAnchor.rectOf(ComposeSource.reply),
    );
  }

  /// Re-opens a message taken back by undo-send or a failed send.
  void reopen(OutgoingMessage message) {
    _open(
      ComposeRequest(
        id: _next++,
        mode: message.threadId == null ? ComposeMode.fresh : ComposeMode.reply,
        accountId: message.accountId,
        to: message.to,
        cc: message.cc,
        bcc: message.bcc,
        subject: message.subject,
        body: message.textBody,
        html: message.htmlBody,
        plainText: message.htmlBody == null,
        threadId: message.threadId,
        inReplyTo: message.inReplyTo,
        references: message.references,
        draftId: message.draftId,
        attachments: message.attachments,
      ),
    );
  }

  final _sent = <int>{};
  final _origins = <int, Rect>{};

  /// Whether window [id] closed by sending, which it leaves differently.
  bool wasSent(int id) => _sent.contains(id);

  /// Where window [id] was opened from, once: the window grows out of it.
  Rect? takeOrigin(int id) => _origins.remove(id);

  void close(int id, {bool sent = false}) {
    if (sent) _sent.add(id);
    state = [
      for (final r in state)
        if (r.id != id) r,
    ];
  }

  void _open(ComposeRequest request, {Rect? origin}) {
    if (origin != null) _origins[request.id] = origin;
    // At most three docked windows, like other desktop clients.
    final kept = state.length >= 3 ? state.sublist(state.length - 2) : state;
    state = [...kept, request];
  }

  static List<Address> _dedupe(List<Address> list) {
    final seen = <String>{};
    return [
      for (final a in list)
        if (seen.add(a.email.toLowerCase())) a,
    ];
  }

  static String _prefixed(String prefix, String subject) {
    final s = subject.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith(prefix.toLowerCase()) ||
        (prefix == 'Fwd:' && lower.startsWith('fw:')))
      return s;
    return '$prefix $s';
  }
}

/// `On Tue, 14 Oct 2025 at 10:42, Maya Chen <maya@…> wrote:`
String attributionLine(Message m) {
  final date = DateFormat("EEE, d MMM y 'at' HH:mm").format(m.date.toLocal());
  return 'On $date, ${m.from?.format() ?? 'someone'} wrote:';
}

/// The compose window shown maximised, if any.
final maximizedComposeProvider = NotifierProvider<_MaximizedNotifier, int?>(
  _MaximizedNotifier.new,
);

class _MaximizedNotifier extends Notifier<int?> {
  @override
  int? build() {
    // Forget the maximised window once it closes.
    ref.listen(composeProvider, (_, next) {
      if (state != null && !next.any((r) => r.id == state)) state = null;
    });
    return null;
  }

  void set(int? id) => state = id;
}

/// Whether any compose window is on screen, counting one still on its way
/// out. The reader's reply toolbar steps aside meanwhile.
final composeOnScreenProvider = NotifierProvider<_OnScreenNotifier, bool>(_OnScreenNotifier.new);

class _OnScreenNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(composeProvider, (_, next) {
      if (next.isNotEmpty) state = true;
    });
    return ref.read(composeProvider).isNotEmpty;
  }

  void set(bool value) => state = value;
}

/// The controls compose windows come from.
enum ComposeSource { compose, reply }

/// Marks [child] as where windows of [source] come from: a new one grows out
/// of it and a draft closed without sending shrinks back into it.
class ComposeAnchor extends StatefulWidget {
  const ComposeAnchor({super.key, required this.source, required this.child});

  final ComposeSource source;
  final Widget child;

  static final _mounted = <ComposeSource, List<_ComposeAnchorState>>{};

  /// The bounds of the newest anchor for [source] on screen, in global
  /// coordinates.
  static Rect? rectOf(ComposeSource source) {
    for (final anchor in (_mounted[source] ?? const <_ComposeAnchorState>[]).reversed) {
      final box = anchor.context.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  @override
  State<ComposeAnchor> createState() => _ComposeAnchorState();
}

class _ComposeAnchorState extends State<ComposeAnchor> {
  @override
  void initState() {
    super.initState();
    ComposeAnchor._mounted.putIfAbsent(widget.source, () => []).add(this);
  }

  @override
  void dispose() {
    ComposeAnchor._mounted[widget.source]?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The bounds of [context]'s widget in global coordinates.
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Floating compose windows docked to the bottom-right corner. A maximised
/// window moves to the centre over a scrim; its state survives the move
/// because each panel has a global key.
class ComposeHost extends ConsumerStatefulWidget {
  const ComposeHost({super.key});

  @override
  ConsumerState<ComposeHost> createState() => _ComposeHostState();
}

class _ComposeHostState extends ConsumerState<ComposeHost> {
  static final _keys = <int, GlobalKey>{};
  final _dragOffsets = <int, Offset>{};

  /// Windows that just closed, kept on screen for their exit.
  final _closing = <int, _Closing>{};

  /// Where each docked window was last placed.
  final _slots = <int, ({double? left, double? right, double bottom})>{};
  int? _lastMaximized;
  bool _lastFullScreen = false;

  /// Windows already shown, and where new ones are growing from.
  final _seen = <int>{};
  final _origins = <int, Rect>{};

  void _onClosed(List<ComposeRequest>? previous, List<ComposeRequest> next) {
    final notifier = ref.read(composeProvider.notifier);
    for (final r in previous ?? const <ComposeRequest>[]) {
      if (next.any((n) => n.id == r.id)) continue;
      final sent = notifier.wasSent(r.id);
      final maximized = _lastMaximized == r.id;
      setState(() {
        _closing[r.id] = _Closing(
          r,
          sent: sent,
          maximized: maximized,
          fullScreen: _lastFullScreen,
          slot: _slots[r.id],
          // A draft closed without sending goes back into what opened it.
          target: sent || maximized
              ? null
              : ComposeAnchor.rectOf(r.mode == ComposeMode.fresh ? ComposeSource.compose : ComposeSource.reply),
        );
      });
      // In case the exit never gets to run, e.g. off screen.
      Timer(_Exit.longest, () => _onExited(r.id));
    }
  }

  /// The last window on screen is nearly back in its control.
  void _onLanding(int id) {
    if (!mounted || ref.read(composeProvider).isNotEmpty) return;
    if (_closing.keys.any((other) => other != id)) return;
    ref.read(composeOnScreenProvider.notifier).set(false);
  }

  void _onExited(int id) {
    if (!mounted || !_closing.containsKey(id)) return;
    setState(() => _closing.remove(id));
    if (_closing.isEmpty && ref.read(composeProvider).isEmpty) ref.read(composeOnScreenProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(composeProvider, _onClosed);
    final requests = ref.watch(composeProvider);
    final maximized = ref.watch(maximizedComposeProvider);
    _lastMaximized = maximized;
    final notifier = ref.read(composeProvider.notifier);
    for (final r in requests) {
      if (!_seen.add(r.id)) continue;
      final origin = notifier.takeOrigin(r.id);
      if (origin != null) _origins[r.id] = origin;
    }
    bool alive(int id) => requests.any((r) => r.id == id) || _closing.containsKey(id);
    _keys.removeWhere((id, _) => !alive(id));
    _dragOffsets.removeWhere((id, _) => !requests.any((r) => r.id == id));
    _slots.removeWhere((id, _) => !alive(id));
    _seen.removeWhere((id) => !alive(id));
    _origins.removeWhere((id, _) => !alive(id));
    if (requests.isEmpty && _closing.isEmpty) return const SizedBox.shrink();
    GlobalKey keyFor(int id) =>
        _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'compose-$id'));
    final docked = requests.where((r) => r.id != maximized).toList();
    final big = requests.where((r) => r.id == maximized).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final window = scheme.surfaceContainerLow;
    // The reply toolbar and the compact compose button share this colour.
    final control = scheme.primaryContainer;

    Widget grow(int id, Widget panel, {required double radius, EdgeInsets inset = EdgeInsets.zero}) => _Grow(
          key: ValueKey('grow-$id'),
          origin: _origins[id],
          inset: inset,
          radius: radius,
          from: control,
          to: window,
          child: panel,
        );

    Widget exit(_Closing c, Widget panel, {required Alignment alignment, required double radius, EdgeInsets inset = EdgeInsets.zero}) =>
        _Exit(
          sent: c.sent,
          alignment: alignment,
          target: c.target,
          inset: inset,
          radius: radius,
          from: window,
          to: control,
          onLanding: () => _onLanding(c.request.id),
          onDone: () => _onExited(c.request.id),
          child: panel,
        );

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cls = WindowClass.of(width);
          // Narrow windows give compose the whole window, one message at a
          // time; the others wait underneath.
          final fullScreen = cls == WindowClass.compact;
          _lastFullScreen = fullScreen;
          if (fullScreen) {
            final top = requests.lastOrNull;
            return Stack(
              children: [
                for (final r in requests)
                  Positioned.fill(
                    key: ValueKey(r.id),
                    child: Offstage(
                      offstage: r != top,
                      child: grow(
                        r.id,
                        radius: 0,
                        ComposePanel(
                          key: keyFor(r.id),
                          request: r,
                          maximized: false,
                          fullScreen: true,
                          animateIn: !_origins.containsKey(r.id),
                        ),
                      ),
                    ),
                  ),
                for (final c in _closing.values)
                  Positioned.fill(
                    key: ValueKey(c.request.id),
                    child: exit(
                      c,
                      alignment: Alignment.bottomCenter,
                      radius: 0,
                      ComposePanel(key: keyFor(c.request.id), request: c.request, maximized: false, fullScreen: true),
                    ),
                  ),
              ],
            );
          }

          final dockLeft = settings.mailListOnRight;
          final railExpanded = settings.railExpanded && width >= 1180;
          final railWidth = switch (cls) {
            WindowClass.compact => 0.0,
            WindowClass.medium => 88.0,
            _ => railExpanded ? 272.0 : 88.0,
          };
          final leftOffset = railWidth + 16.0;
          const dockInset = EdgeInsets.only(bottom: 16);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < docked.length; i++) ...[
                () {
                  final r = docked[i];
                  final drag = _dragOffsets[r.id] ?? Offset.zero;
                  final base = (dockLeft ? leftOffset : 16.0) +
                      (docked.length - 1 - i) * (560.0 + 12.0);
                  // When a neighbour closes, the rest slide over to fill
                  // the dock; dragging stays direct.
                  return SpringBuilder(
                    key: ValueKey(r.id),
                    value: base,
                    builder: (context, b, child) {
                      final slot = (
                        left: dockLeft ? b + drag.dx : null,
                        right: dockLeft ? null : b - drag.dx,
                        bottom: -drag.dy,
                      );
                      _slots[r.id] = slot;
                      return Positioned(
                        left: slot.left,
                        right: slot.right,
                        bottom: slot.bottom,
                        child: child!,
                      );
                    },
                    child: grow(
                      r.id,
                      radius: Corners.extraLarge,
                      inset: dockInset,
                      ComposePanel(
                        key: keyFor(r.id),
                        request: r,
                        maximized: false,
                        dockLeft: dockLeft,
                        animateIn: !_origins.containsKey(r.id),
                        onDrag: (delta) {
                          setState(() {
                            _dragOffsets[r.id] =
                                (_dragOffsets[r.id] ?? Offset.zero) + delta;
                          });
                        },
                      ),
                    ),
                  );
                }(),
              ],
              for (final c in _closing.values.where((c) => !c.maximized && !c.fullScreen && c.slot != null))
                Positioned(
                  key: ValueKey(c.request.id),
                  left: c.slot!.left,
                  right: c.slot!.right,
                  bottom: c.slot!.bottom,
                  child: exit(
                    c,
                    alignment: dockLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                    radius: Corners.extraLarge,
                    inset: dockInset,
                    ComposePanel(
                      key: keyFor(c.request.id),
                      request: c.request,
                      maximized: false,
                      dockLeft: dockLeft,
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: big == null,
                  child: AnimatedOpacity(
                    opacity: big == null ? 0 : 1,
                    duration: Spring.effects.duration,
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(maximizedComposeProvider.notifier).set(null),
                      child: ColoredBox(
                        color: scheme.scrim.withValues(alpha: 0.32),
                      ),
                    ),
                  ),
                ),
              ),
              if (big != null)
                Positioned.fill(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: ComposePanel(
                        key: keyFor(big.id),
                        request: big,
                        maximized: true,
                      ),
                    ),
                  ),
                ),
              for (final c in _closing.values.where((c) => c.maximized && !c.fullScreen))
                Positioned.fill(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: exit(
                        c,
                        alignment: Alignment.center,
                        radius: Corners.extraLarge,
                        ComposePanel(
                          key: keyFor(c.request.id),
                          request: c.request,
                          maximized: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _Closing {
  const _Closing(
    this.request, {
    required this.sent,
    required this.maximized,
    required this.fullScreen,
    required this.slot,
    required this.target,
  });

  final ComposeRequest request;
  final bool sent;
  final bool maximized;
  final bool fullScreen;
  final ({double? left, double? right, double bottom})? slot;

  /// What the window shrinks back into, in global coordinates.
  final Rect? target;
}

/// The frame of a window morphing to or from the control that opened it, at
/// progress [t]: from [control] (t = 0) to [window] (t = 1), in local
/// coordinates.
({Rect rect, double radius}) _morph(Rect control, Rect window, double windowRadius, double t) => (
      rect: Rect.lerp(control, window, t)!,
      radius: math.max(0, lerpDouble(control.shortestSide / 2, windowRadius, t)!),
    );

/// Paints the container of a morphing window: [child] (the window) clipped
/// to the current frame and faded by [content], over a box in the
/// container's colour.
Widget _paintMorph({
  required ({Rect rect, double radius}) frame,
  required Color color,
  required double content,
  required Widget child,
}) =>
    Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: frame.rect,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(frame.radius),
                boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.2 * color.a), blurRadius: 16, offset: const Offset(0, 4))],
              ),
            ),
          ),
        ),
        ClipRRect(
          key: const ValueKey('content'),
          clipper: _FrameClipper(frame),
          child: Opacity(opacity: unit(content), child: child),
        ),
      ],
    );

class _FrameClipper extends CustomClipper<RRect> {
  _FrameClipper(this.frame);

  final ({Rect rect, double radius}) frame;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(frame.rect, Radius.circular(frame.radius));

  @override
  bool shouldReclip(_FrameClipper oldClipper) => oldClipper.frame != frame;
}

/// A new compose window growing out of the control that opened it (an M3
/// container transform): the control's container stretches into the window,
/// changing colour on the way, and the window's content fades in once there
/// is room for it.
class _Grow extends StatefulWidget {
  const _Grow({
    super.key,
    required this.origin,
    required this.radius,
    required this.from,
    required this.to,
    required this.child,
    this.inset = EdgeInsets.zero,
  });

  /// The opening control, in global coordinates; null shows [child] as is.
  final Rect? origin;

  /// The window's corner radius.
  final double radius;
  final Color from;
  final Color to;

  /// Space around the window inside [child].
  final EdgeInsets inset;
  final Widget child;

  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> with SingleTickerProviderStateMixin {
  late final _t = AnimationController.unbounded(vsync: this, value: 0);

  /// The control and the window in local coordinates, once laid out.
  Rect? _control;
  Rect? _window;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.origin == null) {
      _done = true;
      return;
    }
    // The window's own position is only known after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || reduceMotion(context)) {
        setState(() => _done = true);
        return;
      }
      setState(() {
        _control = widget.origin!.shift(-box.localToGlobal(Offset.zero));
        _window = widget.inset.deflateRect(Offset.zero & box.size);
      });
      _t.animateWith(Spring.spatial.simulate(0, 1)).whenCompleteOrCancel(() {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final control = _control;
        final window = _window;
        // Measuring: the first frame is laid out but not shown.
        if (control == null || window == null) return Opacity(opacity: 0, child: child);
        final t = _t.value;
        return _paintMorph(
          frame: _morph(control, window, widget.radius, t),
          color: Color.lerp(widget.from, widget.to, unit(t / 0.6))!.withValues(alpha: unit(t / 0.12)),
          // The content waits until the container is most of the way there.
          content: (t - 0.35) / 0.45,
          child: child!,
        );
      },
    );
  }
}

/// A compose window on its way out. Sent mail lifts away; a draft closed
/// without sending shrinks back into the control that opened it, or sinks
/// towards the corner it came from when that control is gone.
class _Exit extends StatefulWidget {
  const _Exit({
    required this.sent,
    required this.alignment,
    required this.radius,
    required this.from,
    required this.to,
    required this.onDone,
    required this.child,
    this.onLanding,
    this.target,
    this.inset = EdgeInsets.zero,
  });

  final bool sent;
  final Alignment alignment;

  /// What to shrink back into, in global coordinates.
  final Rect? target;
  final EdgeInsets inset;
  final double radius;
  final Color from;
  final Color to;
  final VoidCallback onDone;

  /// Called once a shrinking window is nearly back, so the control it came
  /// from can reappear underneath and take over as it fades.
  final VoidCallback? onLanding;
  final Widget child;

  static const duration = Duration(milliseconds: 220);

  /// Upper bound on any exit.
  static Duration get longest => Spring.standard.duration + const Duration(milliseconds: 200);

  @override
  State<_Exit> createState() => _ExitState();
}

class _ExitState extends State<_Exit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Rect? _control;
  Rect? _window;

  bool get _shrinks => widget.target != null && !widget.sent;

  @override
  void initState() {
    super.initState();
    if (_shrinks) {
      _controller = AnimationController.unbounded(vsync: this, value: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize || reduceMotion(context)) return widget.onDone();
        setState(() {
          _control = widget.target!.shift(-box.localToGlobal(Offset.zero));
          _window = widget.inset.deflateRect(Offset.zero & box.size);
        });
        var landed = false;
        _controller.addListener(() {
          if (landed || _controller.value < 0.6) return;
          landed = true;
          widget.onLanding?.call();
        });
        _controller.animateWith(Spring.standard.simulate(0, 1)).whenCompleteOrCancel(widget.onDone);
      });
    } else {
      _controller = AnimationController(vsync: this, duration: _Exit.duration);
      _controller.forward().whenCompleteOrCancel(widget.onDone);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return IgnorePointer(
      child: ExcludeFocus(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (_shrinks) {
              final control = _control;
              final window = _window;
              if (control == null || window == null) return child!;
              final p = _controller.value;
              return _paintMorph(
                frame: _morph(control, window, widget.radius, 1 - p),
                // Opaque until the control is back underneath, then fading
                // into it.
                color: Color.lerp(widget.from, widget.to, unit((p - 0.2) / 0.5))!.withValues(alpha: unit((1 - p) / 0.25)),
                // The content leaves first, so the container can shrink.
                content: 1 - p / 0.3,
                child: child!,
              );
            }
            final t = Easing.emphasizedAccelerate.transform(_controller.value);
            final scale = still ? 1.0 : 1 - 0.06 * t;
            final dy = still ? 0.0 : (widget.sent ? -48.0 : 32.0) * t;
            return Opacity(
              opacity: 1 - unit(_controller.value / 0.8),
              child: Transform(
                alignment: widget.alignment,
                transform: Matrix4.identity()
                  ..translateByDouble(0, dy, 0, 1)
                  ..scaleByDouble(scale, scale, 1, 1),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
