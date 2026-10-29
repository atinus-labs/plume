import 'dart:async';

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

  void newMessage({List<Address> to = const []}) {
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

  void reply(Message m, {required bool all}) {
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
    );
  }

  void forward(Message m) {
    _open(
      ComposeRequest(
        id: _next++,
        mode: ComposeMode.forward,
        accountId: m.accountId,
        subject: _prefixed('Fwd:', m.subject),
        quoted: m,
        forwardFrom: m,
      ),
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

  /// Whether window [id] closed by sending, which it leaves differently.
  bool wasSent(int id) => _sent.contains(id);

  void close(int id, {bool sent = false}) {
    if (sent) _sent.add(id);
    state = [
      for (final r in state)
        if (r.id != id) r,
    ];
  }

  void _open(ComposeRequest request) {
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

  void _onClosed(List<ComposeRequest>? previous, List<ComposeRequest> next) {
    final notifier = ref.read(composeProvider.notifier);
    for (final r in previous ?? const <ComposeRequest>[]) {
      if (next.any((n) => n.id == r.id)) continue;
      setState(() {
        _closing[r.id] = _Closing(
          r,
          sent: notifier.wasSent(r.id),
          maximized: _lastMaximized == r.id,
          slot: _slots[r.id],
        );
      });
      Timer(_Exit.duration, () {
        if (mounted) setState(() => _closing.remove(r.id));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(composeProvider, _onClosed);
    final requests = ref.watch(composeProvider);
    final maximized = ref.watch(maximizedComposeProvider);
    _lastMaximized = maximized;
    bool alive(int id) => requests.any((r) => r.id == id) || _closing.containsKey(id);
    _keys.removeWhere((id, _) => !alive(id));
    _dragOffsets.removeWhere((id, _) => !requests.any((r) => r.id == id));
    _slots.removeWhere((id, _) => !alive(id));
    if (requests.isEmpty && _closing.isEmpty) return const SizedBox.shrink();
    GlobalKey keyFor(int id) =>
        _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'compose-$id'));
    final docked = requests.where((r) => r.id != maximized).toList();
    final big = requests.where((r) => r.id == maximized).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cls = WindowClass.of(width);
          final dockLeft = settings.mailListOnRight;
          final railExpanded = settings.railExpanded && width >= 1180;
          final railWidth = switch (cls) {
            WindowClass.compact => 0.0,
            WindowClass.medium => 88.0,
            _ => railExpanded ? 272.0 : 88.0,
          };
          final leftOffset = railWidth + 16.0;

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
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(r.id),
                    tween: Tween(end: base),
                    duration: Spring.spatial.duration,
                    curve: Spring.spatial.curve,
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
                    child: ComposePanel(
                      key: keyFor(r.id),
                      request: r,
                      maximized: false,
                      dockLeft: dockLeft,
                      onDrag: (delta) {
                        setState(() {
                          _dragOffsets[r.id] =
                              (_dragOffsets[r.id] ?? Offset.zero) + delta;
                        });
                      },
                    ),
                  );
                }(),
              ],
              for (final c in _closing.values.where((c) => !c.maximized && c.slot != null))
                Positioned(
                  key: ValueKey(c.request.id),
                  left: c.slot!.left,
                  right: c.slot!.right,
                  bottom: c.slot!.bottom,
                  child: _Exit(
                    sent: c.sent,
                    alignment: dockLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                    child: ComposePanel(
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
              for (final c in _closing.values.where((c) => c.maximized))
                Positioned.fill(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _Exit(
                        sent: c.sent,
                        alignment: Alignment.center,
                        child: ComposePanel(
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
  const _Closing(this.request, {required this.sent, required this.maximized, required this.slot});

  final ComposeRequest request;
  final bool sent;
  final bool maximized;
  final ({double? left, double? right, double bottom})? slot;
}

/// A compose window on its way out. Sent mail lifts away; a closed draft
/// sinks back towards the corner it came from.
class _Exit extends StatefulWidget {
  const _Exit({required this.sent, required this.alignment, required this.child});

  final bool sent;
  final Alignment alignment;
  final Widget child;

  static const duration = Duration(milliseconds: 220);

  @override
  State<_Exit> createState() => _ExitState();
}

class _ExitState extends State<_Exit> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: _Exit.duration)..forward();

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
