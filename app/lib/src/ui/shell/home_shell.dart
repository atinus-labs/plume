import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../actions.dart';
import '../compose/compose_host.dart';
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
    final desktop = ref.watch(desktopProvider);
    final settings = ref.watch(settingsProvider);
    final surfaces = PlumeSurfaces.of(context);
    final open = ref.watch(openThreadProvider);

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
                if (desktop.drawsWindowControls) const WindowTitleBar(),
                const StatusBanner(),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final cls = WindowClass.of(constraints.maxWidth);
                    final top = desktop.drawsWindowControls ? 0.0 : 8.0;
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
                              child: open == null ? const ThreadListPane() : const Pane(child: ReaderPane(showBack: true)),
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: EdgeInsets.only(top: top),
                      child: open == null
                          ? ThreadListPane(onOpenDrawer: () => _scaffold.currentState?.openDrawer())
                          : const Pane(radius: 0, child: ReaderPane(showBack: true)),
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
    final primary = FocusManager.instance.primaryFocus;
    final typing = primary?.context?.findAncestorWidgetOfExactType<EditableText>() != null ||
        primary?.context?.widget is EditableText;
    if (typing) return KeyEventResult.ignored;
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

    bool handled(void Function() f) {
      f();
      return true;
    }

    final shift = keyboard.isShiftPressed;
    final result = switch ((ch, event.logicalKey)) {
      ('c', _) => handled(() => ref.read(composeProvider.notifier).newMessage()),
      ('/', _) => handled(() => ref.read(searchFocusProvider).requestFocus()),
      ('j', _) || (_, LogicalKeyboardKey.arrowDown) when !shift => handled(() => stepThread(ref, 1)),
      ('k', _) || (_, LogicalKeyboardKey.arrowUp) when !shift => handled(() => stepThread(ref, -1)),
      ('e', _) => handled(() => applyThreadAction(ref, MailAction.archive, targets())),
      ('#', _) => handled(() => applyThreadAction(ref, MailAction.trash, targets())),
      ('!', _) => handled(() => applyThreadAction(ref, MailAction.markSpam, targets())),
      ('s', _) => handled(() {
          final t = openSummary();
          applyThreadAction(ref, t?.isFlagged == true ? MailAction.unflag : MailAction.flag, targets());
        }),
      ('U', _) => handled(() => applyThreadAction(ref, MailAction.markUnread, targets())),
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
