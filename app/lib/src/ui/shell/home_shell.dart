import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../services/window_frame.dart';
import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../actions.dart';
import '../common/shortcut_echo.dart';
import '../compose/compose_host.dart';
import '../reader/mail_renderer.dart';
import '../reader/reader_pane.dart';
import '../search/search_field.dart';
import '../settings/settings_page.dart';
import '../threads/thread_list_pane.dart';
import 'status_banner.dart';
import 'title_bar.dart';

/// The main window: navigation rail, message list and reading pane, adapting
/// to the window size class.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _focus = FocusNode(debugLabel: 'shell');

  @override
  void initState() {
    super.initState();
    // Start the mail renderer's web engine before the first message opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(mailRendererProvider)?.warmUp();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _openSettings() {
    unawaited(Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: Spring.standard.duration,
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const SettingsPage(),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Spring.standard.curve)),
          child: child,
        ),
      ),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final titleBar = ref.watch(titleBarProvider);
    final settings = ref.watch(settingsProvider);
    final surfaces = PlumeSurfaces.of(context);
    // Only whether one is open: moving between conversations leaves the
    // shell alone.
    final open = ref.watch(openThreadProvider.select((k) => k != null));

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKey(event),
      child: Scaffold(
        key: _scaffold,
        backgroundColor: surfaces.window,
        drawer: Drawer(
          width: 300,
          child: SafeArea(child: NavRailDrawer(onOpenSettings: _openSettings)),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (titleBar == TitleBar.plume) const WindowTitleBar(),
                const StatusBanner(),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final cls = WindowClass.of(constraints.maxWidth);
                    final top = titleBar == TitleBar.plume ? 0.0 : 8.0;
                    if (cls >= WindowClass.expanded) {
                      final railExpanded = settings.railExpanded && constraints.maxWidth >= 1180;
                      final maxList = (constraints.maxWidth - (railExpanded ? 272 : 88) - 380).clamp(320.0, 640.0);
                      final listWidth = settings.listWidth.clamp(320.0, maxList);
                      final onRight = settings.mailListOnRight;
                      return Padding(
                        padding: EdgeInsets.only(top: top, bottom: 8, right: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NavRailHost(expanded: railExpanded, onOpenSettings: _openSettings),
                            if (!onRight) ...[
                              SizedBox(width: listWidth, child: const ThreadListPane()),
                              _ResizeHandle(
                                onDrag: (dx) => ref.read(settingsProvider.notifier).update(
                                    (s) => s.copyWith(listWidth: (listWidth + dx).clamp(320.0, maxList))),
                              ),
                              const Expanded(child: Pane(child: ReaderPane())),
                            ] else ...[
                              const Expanded(child: Pane(child: ReaderPane())),
                              _ResizeHandle(
                                onDrag: (dx) => ref.read(settingsProvider.notifier).update(
                                    (s) => s.copyWith(listWidth: (listWidth - dx).clamp(320.0, maxList))),
                              ),
                              SizedBox(width: listWidth, child: const ThreadListPane()),
                            ],
                          ],
                        ),
                      );
                    }
                    if (cls == WindowClass.medium) {
                      return Padding(
                        padding: EdgeInsets.only(top: top, bottom: 8, right: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NavRailHost(expanded: false, onOpenSettings: _openSettings),
                            Expanded(
                              child: _ListDetail(
                                showDetail: open,
                                list: const ThreadListPane(),
                                detail: const Pane(child: ReaderPane(showBack: true)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    // Without a rail, compose is a floating button over the list.
                    final media = MediaQuery.of(context);
                    return Padding(
                      padding: EdgeInsets.only(top: top),
                      child: _ListDetail(
                        showDetail: open,
                        list: Stack(
                          children: [
                            MediaQuery(
                              data: media.copyWith(padding: media.padding.copyWith(bottom: media.padding.bottom + 72)),
                              child: ThreadListPane(onOpenDrawer: () => _scaffold.currentState?.openDrawer()),
                            ),
                            Positioned(
                              right: 16,
                              bottom: 16 + media.padding.bottom,
                              child: ComposeAnchor(
                                source: ComposeSource.compose,
                                child: ShortcutEcho(
                                  target: ShortcutTarget.compose,
                                  shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
                                  child: FloatingActionButton(
                                    tooltip: 'Compose (C)',
                                    onPressed: () => ref.read(composeProvider.notifier).newMessage(),
                                    child: const Icon(Symbols.edit_rounded),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        detail: const Pane(radius: 0, child: ReaderPane(showBack: true)),
                      ),
                    );
                  }),
                ),
              ],
            ),
            const ComposeHost(),
          ],
        ),
      ),
    );
  }

  /// Gmail-compatible single-key shortcuts. Ignored while typing.
  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_typing()) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) {
      if (keyboard.isControlPressed && event.logicalKey == LogicalKeyboardKey.comma) {
        _openSettings();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final ch = event.character;
    final open = ref.read(openThreadProvider);
    final selection = ref.read(selectionProvider);
    final list = ref.read(visibleThreadsProvider).value ?? const <ThreadSummary>[];
    List<ThreadKey> targets() {
      if (selection.isNotEmpty) return list.where((t) => selection.contains(t.key)).map(keyOf).toList();
      return [?open];
    }

    ThreadSummary? openSummary() => list.where((t) => keyOf(t) == open).firstOrNull;

    Future<Message?> lastMessage() async {
      if (open == null) return null;
      final detail = await ref.read(storeProvider).watchThread(open.accountId, open.threadId).first;
      return detail?.messages.lastOrNull;
    }

    bool handled(void Function() f, [ShortcutTarget? echo]) {
      f();
      if (echo != null) ref.read(shortcutEchoProvider.notifier).echo(echo);
      return true;
    }

    final shift = keyboard.isShiftPressed;
    final result = switch ((ch, event.logicalKey)) {
      ('c', _) => handled(() => ref.read(composeProvider.notifier).newMessage(), ShortcutTarget.compose),
      ('/', _) => handled(() => ref.read(searchFocusProvider).requestFocus()),
      ('j', _) || (_, LogicalKeyboardKey.arrowDown) when !shift => handled(() => stepThread(ref, 1), ShortcutTarget.older),
      ('k', _) || (_, LogicalKeyboardKey.arrowUp) when !shift => handled(() => stepThread(ref, -1), ShortcutTarget.newer),
      ('e', _) => handled(() => applyThreadAction(ref, MailAction.archive, targets()), ShortcutTarget.archive),
      ('#', _) => handled(() => applyThreadAction(ref, MailAction.trash, targets()), ShortcutTarget.delete),
      ('!', _) => handled(() => applyThreadAction(ref, MailAction.markSpam, targets()), ShortcutTarget.spam),
      ('s', _) => handled(() {
          final t = openSummary();
          applyThreadAction(ref, t?.isFlagged == true ? MailAction.unflag : MailAction.flag, targets());
        }),
      ('U', _) => handled(() => applyThreadAction(ref, MailAction.markUnread, targets()), ShortcutTarget.unread),
      ('I', _) => handled(() => applyThreadAction(ref, MailAction.markRead, targets())),
      ('x', _) => handled(() {
          if (open != null) ref.read(selectionProvider.notifier).toggle('${open.accountId}/${open.threadId}');
        }),
      ('r', _) => handled(() async {
          final m = await lastMessage();
          if (m != null) ref.read(composeProvider.notifier).reply(m, all: false);
        }),
      ('a', _) => handled(() async {
          final m = await lastMessage();
          if (m != null) ref.read(composeProvider.notifier).reply(m, all: true);
        }),
      ('f', _) => handled(() async {
          final m = await lastMessage();
          if (m != null) ref.read(composeProvider.notifier).forward(m);
        }),
      (_, LogicalKeyboardKey.enter) when open == null && list.isNotEmpty => handled(() => openThread(ref, list.first)),
      (_, LogicalKeyboardKey.escape) => handled(() {
          if (selection.isNotEmpty) {
            ref.read(selectionProvider.notifier).clear();
          } else if (ref.read(searchProvider).active) {
            ref.read(searchProvider.notifier).clear();
          } else {
            ref.read(openThreadProvider.notifier).close();
          }
        }),
      (_, LogicalKeyboardKey.f5) => handled(() => ref.read(engineProvider).syncAll()),
      _ => false,
    };
    return result ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Whether focus is somewhere that takes typed text: a text field or the
  /// message body, which is a text input client but not an [EditableText].
  static bool _typing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    bool takesText(Element e) => e is StatefulElement && e.state is TextInputClient;
    var typing = takesText(context as Element);
    if (!typing) {
      context.visitAncestorElements((e) => !(typing = takesText(e)));
    }
    return typing;
  }
}

/// List and reader sharing one pane on narrow windows. Opening a
/// conversation moves forward along the horizontal axis; back reverses it.
class _ListDetail extends StatelessWidget {
  const _ListDetail({required this.showDetail, required this.list, required this.detail});

  final bool showDetail;
  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: kSwitchDuration,
        transitionBuilder: sharedAxis(axis: Axis.horizontal, direction: showDetail ? 1 : -1),
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: KeyedSubtree(key: ValueKey(showDetail), child: showDetail ? detail : list),
      );
}

/// The draggable divider between list and reading pane.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        child: SizedBox(
          width: 16,
          child: Center(
            child: SpringBuilder(
              value: active ? 1 : 0,
              spring: Spring.spatialFast,
              builder: (context, t, _) => Container(
                width: 4,
                height: 40 + 24 * t,
                decoration: BoxDecoration(
                  color: Color.lerp(scheme.outlineVariant.withValues(alpha: 0), _dragging ? scheme.onSurface : scheme.outline, unit(t)),
                  borderRadius: Corners.all(Corners.full),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
