import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/avatars.dart';
import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../actions.dart';
import '../common/empty_state.dart';
import '../common/logo.dart';
import '../common/shortcut_echo.dart';
import '../compose/compose_host.dart';
import 'message_card.dart';

/// The reading pane. Moving to an older conversation slides the new one up
/// from below and a newer one down from above, matching where it sits in
/// the list; anything else fades through. The toolbar and the reply toolbar
/// stay put while conversations change under them.
class ReaderPane extends ConsumerStatefulWidget {
  const ReaderPane({super.key, this.showBack = false});

  /// Single-pane layouts show a back button instead of the list.
  final bool showBack;

  @override
  ConsumerState<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends ConsumerState<ReaderPane> {
  ThreadKey? _last;
  int _direction = 0;
  final _chrome = _Chrome();

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBack = widget.showBack;
    // In single-pane layouts the reader slides away when closed; it keeps
    // the conversation on it while it goes instead of flashing empty.
    final open = ref.watch(openThreadProvider) ?? (showBack ? _last : null);
    if (open != _last) {
      final list = ref.read(visibleThreadsProvider).value ?? const <ThreadSummary>[];
      final from = _last == null ? -1 : list.indexWhere((t) => keyOf(t) == _last);
      final to = open == null ? -1 : list.indexWhere((t) => keyOf(t) == open);
      _direction = from < 0 || to < 0 ? 0 : (to - from).sign;
      _last = open;
      // A conversation starts at the top.
      _chrome.reset();
    }
    // Present while a conversation is open; it fades as a whole when the
    // reader empties, but not between conversations.
    Widget chrome(Widget Function(ThreadKey open) build) => AnimatedSwitcher(
          duration: kSwitchDuration,
          child: open == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : KeyedSubtree(key: const ValueKey('chrome'), child: build(open)),
        );
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: kSwitchDuration,
            transitionBuilder: _direction == 0 ? fadeThrough : sharedAxis(direction: _direction, distance: 40),
            child: open == null
                ? const _NothingOpen(key: ValueKey('empty'))
                : _ThreadView(key: ValueKey(open), threadKey: open, chrome: _chrome),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: chrome((open) => _Toolbar(threadKey: open, chrome: _chrome, showBack: showBack)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(child: chrome((open) => _ReplyBar(threadKey: open, chrome: _chrome))),
        ),
      ],
    );
  }
}

/// What the reader's toolbars show about the conversation under them.
class _Chrome {
  /// Content has scrolled under the toolbar: it fills, like an M3 top app
  /// bar in its scrolled state.
  final scrolled = ValueNotifier(false);

  /// The subject has scrolled away, so the toolbar shows it instead.
  final titleInBar = ValueNotifier(false);

  /// The reply toolbar steps aside while reading down and comes back on the
  /// way up or at the end of the conversation, where replying is next.
  final replyBar = ValueNotifier(true);

  void reset() {
    scrolled.value = false;
    titleInBar.value = false;
    replyBar.value = true;
  }

  void dispose() {
    scrolled.dispose();
    titleInBar.dispose();
    replyBar.dispose();
  }
}

class _NothingOpen extends ConsumerWidget {
  const _NothingOpen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider(ref.watch(viewProvider).toFilter())).value ?? 0;
    return EmptyState(
      illustration: const PlumeLogo(size: 112),
      title: unread > 0 ? '$unread unread' : 'No conversation selected',
      message: 'Pick a conversation from the list. Use J and K to move between them.',
    );
  }
}

class _ThreadView extends ConsumerWidget {
  const _ThreadView({super.key, required this.threadKey, required this.chrome});

  final ThreadKey threadKey;
  final _Chrome chrome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(threadDetailProvider(threadKey));
    final account = ref.watch(accountMapProvider)[threadKey.accountId];
    return detail.when(
      loading: () => const Center(child: LoadingIndicator(delay: Duration(milliseconds: 400))),
      error: (e, _) => EmptyState(icon: Symbols.error_rounded, title: 'Couldn’t open conversation', message: '$e'),
      data: (thread) {
        if (thread == null) {
          return const EmptyState(icon: Symbols.inbox_rounded, title: 'This conversation is gone', message: 'It was moved or deleted.');
        }
        return _ThreadBody(thread: thread, myEmail: account?.email ?? '', chrome: chrome);
      },
    );
  }
}

class _ThreadBody extends ConsumerStatefulWidget {
  const _ThreadBody({required this.thread, required this.myEmail, required this.chrome});

  final ThreadDetail thread;
  final String myEmail;
  final _Chrome chrome;

  @override
  ConsumerState<_ThreadBody> createState() => _ThreadBodyState();
}

const _toolbarHeight = 64.0;

class _ThreadBodyState extends ConsumerState<_ThreadBody> {
  final _scroll = ScrollController();
  final _subjectKey = GlobalKey();
  double _lastOffset = 0;

  /// Older read messages folded into one row in long conversations.
  bool _unfolded = false;
  Set<String> _folded = const {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // A conversation on its way out no longer drives the toolbars.
    if (ref.read(openThreadProvider) != keyOf(widget.thread.summary)) return;
    final chrome = widget.chrome;
    final p = _scroll.position;
    final offset = p.pixels;
    chrome.scrolled.value = offset > 1;
    final subject = _subjectKey.currentContext?.findRenderObject() as RenderBox?;
    chrome.titleInBar.value = offset > (subject?.hasSize == true ? subject!.size.height - 8 : 56);
    final delta = offset - _lastOffset;
    _lastOffset = offset;
    if (offset < 48 || p.extentAfter < 48) {
      chrome.replyBar.value = true;
    } else if (delta > 2) {
      chrome.replyBar.value = false;
    } else if (delta < -2) {
      chrome.replyBar.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final myEmail = widget.myEmail;
    final theme = Theme.of(context);
    final summary = thread.summary;
    final key = keyOf(summary);
    final mailboxes = ref.watch(mailboxesProvider(summary.accountId)).value ?? const <Mailbox>[];
    final labelChips = mailboxes
        .where((m) =>
            summary.mailboxIds.contains(m.id) &&
            !m.hidden &&
            !const {MailboxRole.category, MailboxRole.important, MailboxRole.sent, MailboxRole.drafts}.contains(m.role))
        .toList();
    final messages = thread.messages;
    final latest = latestMessage(thread);
    final folders = ref.watch(usesFoldersProvider(summary.accountId));
    final subject = summary.subject.isEmpty ? '(no subject)' : summary.subject;

    // Long conversations fold the run of read messages after the first one,
    // keeping the opening, the unread and the latest in view.
    if (!_unfolded && messages.length > 4) {
      var end = 1;
      while (end < messages.length - 2 && messages[end].isRead) {
        end++;
      }
      final run = messages.sublist(1, end);
      _folded = run.length >= 2 ? {for (final m in run) m.id} : const {};
    }
    final showFold = !_unfolded && _folded.isNotEmpty;
    final shown = [
      for (final m in messages)
        if (!showFold || !_folded.contains(m.id)) m,
    ];
    final cardCount = shown.length + (showFold ? 1 : 0);

    var index = 0;
    return SelectionContainer.disabled(
      child: Scrollbar(
        controller: _scroll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, _toolbarHeight + 2, 16, 112),
          children: [
            Padding(
              key: _subjectKey,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    subject,
                    style: theme.textTheme.headlineSmallEmphasized,
                  ),
                  if (labelChips.isNotEmpty || summary.isFlagged) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in labelChips) _LabelChip(mailbox: m, onRemove: m.kind == MailboxKind.user && !folders
                            ? () => applyLabels(ref, [key], remove: {m.id})
                            : null),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            for (final m in shown) ...[
              if (showFold && index == 1)
                _FoldedMessages(
                  messages: [for (final f in messages) if (_folded.contains(f.id)) f],
                  index: index++,
                  count: cardCount,
                  onTap: () => setState(() => _unfolded = true),
                ),
              Presence(
                key: ValueKey(m.id),
                appear: _unfolded && _folded.contains(m.id),
                child: m.isDraft
                    ? DraftCard(message: m, index: index++, count: cardCount, myEmail: myEmail)
                    : MessageCard(
                        message: m,
                        index: index++,
                        count: cardCount,
                        myEmail: myEmail,
                        initiallyExpanded: m == latest || !m.isRead,
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The newest message in [thread] that is not a draft: the one a reply
/// answers. Null for a conversation of drafts only.
Message? latestMessage(ThreadDetail thread) => thread.messages.where((m) => !m.isDraft).lastOrNull;

/// The reader's top toolbar. It stays in place while conversations change,
/// showing the last one until the next has loaded.
class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({required this.threadKey, required this.chrome, required this.showBack});

  final ThreadKey threadKey;
  final _Chrome chrome;
  final bool showBack;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  ThreadSummary? _summary;

  @override
  Widget build(BuildContext context) {
    final summary = _summary = ref.watch(threadDetailProvider(widget.threadKey)).value?.summary ?? _summary;
    if (summary == null) return const SizedBox(height: _toolbarHeight);
    final showBack = widget.showBack;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = keyOf(summary);
    final view = ref.watch(viewProvider);
    final mailboxes = ref.watch(mailboxesProvider(summary.accountId)).value ?? const <Mailbox>[];
    final list = ref.watch(visibleThreadsProvider).value ?? const <ThreadSummary>[];
    final position = list.indexWhere((t) => keyOf(t) == key);
    final inTrash = view.kind == ViewKind.trash;
    final inSpam = view.kind == ViewKind.junk;
    final inInbox = summary.mailboxIds.any((id) => mailboxes.any((m) => m.id == id && m.role == MailboxRole.inbox));
    final folders = ref.watch(usesFoldersProvider(summary.accountId));
    final subject = summary.subject.isEmpty ? '(no subject)' : summary.subject;

    final labels = mailboxes.where((m) => m.kind == MailboxKind.user && !m.hidden).toList();
    void spam() => applyThreadAction(ref, MailAction.markSpam, [key]);
    void unread() => applyThreadAction(ref, MailAction.markUnread, [key]);
    final bar = LayoutBuilder(builder: (context, constraints) {
      // Narrow windows keep archive and delete in reach and move the rest
      // into a menu, so the subject keeps room.
      final narrow = constraints.maxWidth < 600;
      return Container(
        height: _toolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (showBack)
              IconButton(
                tooltip: 'Back',
                onPressed: () => ref.read(openThreadProvider.notifier).close(),
                icon: const Icon(Symbols.arrow_back_rounded),
              ),
            if (inTrash)
              _ToolButton(Symbols.restore_from_trash_rounded, 'Restore', () => applyThreadAction(ref, MailAction.restore, [key]))
            else if (inSpam)
              _ToolButton(Symbols.report_off_rounded, 'Not spam', () => applyThreadAction(ref, MailAction.markNotSpam, [key]))
            else if (inInbox)
              _ToolButton(Symbols.archive_rounded, 'Archive (E)', () => applyThreadAction(ref, MailAction.archive, [key]), shortcut: ShortcutTarget.archive)
            else
              _ToolButton(Symbols.move_to_inbox_rounded, 'Move to Inbox', () => applyThreadAction(ref, MailAction.moveToInbox, [key])),
            if (inTrash || inSpam)
              _ToolButton(Symbols.delete_forever_rounded, 'Delete forever', () => applyThreadAction(ref, MailAction.deleteForever, [key]))
            else
              _ToolButton(Symbols.delete_rounded, 'Delete (#)', () => applyThreadAction(ref, MailAction.trash, [key]), shortcut: ShortcutTarget.delete),
            if (narrow)
              MenuAnchor(
                menuChildren: [
                  if (!inSpam && !inTrash)
                    MenuItemButton(leadingIcon: const Icon(Symbols.report_rounded), onPressed: spam, child: const Text('Report spam')),
                  MenuItemButton(
                      leadingIcon: const Icon(Symbols.mark_email_unread_rounded), onPressed: unread, child: const Text('Mark as unread')),
                  if (folders)
                    SubmenuButton(
                      leadingIcon: const Icon(Symbols.drive_file_move_rounded),
                      menuChildren: _moveItems(ref, summary, ref.watch(moveTargetsProvider(summary.accountId))),
                      child: const Text('Move to'),
                    )
                  else if (labels.isNotEmpty)
                    SubmenuButton(
                      leadingIcon: const Icon(Symbols.label_rounded),
                      menuChildren: _labelItems(ref, summary, labels),
                      child: const Text('Labels'),
                    ),
                ],
                builder: (context, controller, _) => IconButton(
                  tooltip: 'More',
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  icon: const Icon(Symbols.more_vert_rounded),
                ),
              )
            else ...[
              if (!inSpam && !inTrash) _ToolButton(Symbols.report_rounded, 'Report spam (!)', spam, shortcut: ShortcutTarget.spam),
              _ToolButton(Symbols.mark_email_unread_rounded, 'Mark as unread (Shift+U)', unread, shortcut: ShortcutTarget.unread),
              if (folders)
                _MoveMenu(summary: summary, targets: ref.watch(moveTargetsProvider(summary.accountId)))
              else
                _LabelMenu(summary: summary, labels: labels),
            ],
            // The subject moves up here once it has scrolled out of view.
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: widget.chrome.titleInBar,
                builder: (context, inBar, _) => AnimatedSlide(
                  offset: inBar ? Offset.zero : const Offset(0, 0.35),
                  duration: Spring.standard.duration,
                  curve: Spring.standard.curve,
                  child: AnimatedOpacity(
                    opacity: inBar ? 1 : 0,
                    duration: Spring.effects.duration,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMediumEmphasized),
                    ),
                  ),
                ),
              ),
            ),
            if (position >= 0) ...[
              if (!narrow)
                AnimatedCount(
                  position + 1,
                  format: (n) => '$n of ${list.length}',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              _ToolButton(Symbols.chevron_left_rounded, 'Newer (K)', position > 0 ? () => stepThread(ref, -1) : null, shortcut: ShortcutTarget.newer),
              _ToolButton(Symbols.chevron_right_rounded, 'Older (J)', position < list.length - 1 ? () => stepThread(ref, 1) : null, shortcut: ShortcutTarget.older),
            ],
          ],
        ),
      );
    });

    // One step above the cards, so they read as passing underneath.
    final fill = scheme.brightness == Brightness.light ? scheme.surfaceContainer : scheme.surfaceContainerHigh;
    return ValueListenableBuilder(
      valueListenable: widget.chrome.scrolled,
      builder: (context, scrolled, child) => SpringBuilder(
        value: scrolled ? 1 : 0,
        spring: Spring.effects,
        builder: (context, t, child) => ColoredBox(color: fill.withValues(alpha: unit(t)), child: child),
        child: child,
      ),
      child: bar,
    );
  }
}

/// Reply, reply all and forward for the latest message, floating over the
/// bottom of the reader.
class _ReplyBar extends ConsumerStatefulWidget {
  const _ReplyBar({required this.threadKey, required this.chrome});

  final ThreadKey threadKey;
  final _Chrome chrome;

  @override
  ConsumerState<_ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends ConsumerState<_ReplyBar> {
  Message? _latest;

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(threadDetailProvider(widget.threadKey)).value;
    // A conversation of drafts only has nothing to reply to; its drafts
    // carry their own Edit button.
    final latest = _latest = thread == null ? _latest : latestMessage(thread);
    if (latest == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: widget.chrome.replyBar,
      builder: (context, visible, child) {
        // While a compose window is open the toolbar has become it:
        // it fades in place, so a window shrinking back lands on it.
        final composing = ref.watch(composeOnScreenProvider);
        return IgnorePointer(
          ignoring: !visible || composing,
          child: SpringBuilder(
            value: visible ? 1 : 0,
            spring: visible ? Spring.spatial : Spring.standard,
            builder: (context, t, child) => SpringBuilder(
              value: composing ? 0 : 1,
              spring: Spring.effectsFast,
              builder: (context, shown, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 96),
                child: Opacity(opacity: unit(t) * unit(shown), child: child),
              ),
              child: child,
            ),
            child: child,
          ),
        );
      },
      child: ComposeAnchor(
        source: ComposeSource.reply,
        child: FloatingToolbar(
          vibrant: true,
          children: [
            _ReplyButton(icon: Symbols.reply_rounded, label: 'Reply', onPressed: () => ref.read(composeProvider.notifier).reply(latest, all: false)),
            _ReplyButton(icon: Symbols.reply_all_rounded, label: 'Reply all', onPressed: () => ref.read(composeProvider.notifier).reply(latest, all: true)),
            _ReplyButton(icon: Symbols.forward_rounded, label: 'Forward', onPressed: () => ref.read(composeProvider.notifier).forward(latest)),
          ],
        ),
      ),
    );
  }
}

/// The folded run of older messages: who wrote them and how many, opening
/// them in place when clicked.
class _FoldedMessages extends ConsumerWidget {
  const _FoldedMessages({required this.messages, required this.index, required this.count, required this.onTap});

  final List<Message> messages;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = messageCardColor(scheme);
    final senders = <String, Address>{
      for (final m in messages.reversed)
        if (m.from != null) m.from!.email.toLowerCase(): m.from!,
    }.values.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: card,
        shape: RoundedRectangleBorder(borderRadius: groupedRadius(index, count, outer: Corners.extraLarge, inner: Corners.small)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 32.0 + 14 * (senders.length - 1),
                  height: 32,
                  child: Stack(
                    children: [
                      for (var i = senders.length - 1; i >= 0; i--)
                        Positioned(
                          left: 14.0 * i,
                          child: DecoratedBox(
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: card, width: 2)),
                            child: MorphAvatar(
                              name: senders[i].displayName,
                              colorKey: senders[i].email,
                              image: ref.watch(senderAvatarProvider(senders[i].email)).value,
                              size: 28,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text('${messages.length} older messages', style: theme.textTheme.labelLargeEmphasized.copyWith(color: scheme.primary)),
                const SizedBox(width: 4),
                Icon(Symbols.unfold_more_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(this.icon, this.tooltip, this.onPressed, {this.shortcut});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// The keyboard shortcut for this button, which presses it on screen too.
  final ShortcutTarget? shortcut;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
    final target = shortcut;
    return target == null ? button : ShortcutEcho(target: target, child: button);
  }
}

class _ReplyButton extends StatelessWidget {
  const _ReplyButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimaryContainer),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.mailbox, this.onRemove});

  final Mailbox mailbox;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = mailbox.color == null
        ? (container: scheme.surfaceContainerHighest, onContainer: scheme.onSurfaceVariant)
        : tonalPair(harmonize(Color(mailbox.color!), scheme), scheme.brightness);
    return Container(
      padding: EdgeInsets.fromLTRB(10, 3, onRemove == null ? 10 : 4, 3),
      decoration: BoxDecoration(color: tones.container, borderRadius: Corners.all(Corners.small)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mailbox.name, style: theme.textTheme.labelMedium?.copyWith(color: tones.onContainer)),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(padding: const EdgeInsets.all(2), child: Icon(Symbols.close_rounded, size: 14, color: tones.onContainer)),
            ),
        ],
      ),
    );
  }
}

/// "Move to" for folder-based accounts, where a conversation lives in one
/// folder instead of carrying labels.
class _MoveMenu extends ConsumerWidget {
  const _MoveMenu({required this.summary, required this.targets});

  final ThreadSummary summary;
  final List<Mailbox> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _moveItems(ref, summary, targets);
    if (items.isEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      menuChildren: items,
      builder: (context, controller, _) => IconButton(
        tooltip: 'Move to',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Symbols.drive_file_move_rounded),
      ),
    );
  }
}

class _LabelMenu extends ConsumerWidget {
  const _LabelMenu({required this.summary, required this.labels});

  final ThreadSummary summary;
  final List<Mailbox> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      menuChildren: _labelItems(ref, summary, labels),
      builder: (context, controller, _) => IconButton(
        tooltip: 'Labels (L)',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Symbols.label_rounded),
      ),
    );
  }
}

List<Widget> _moveItems(WidgetRef ref, ThreadSummary summary, List<Mailbox> targets) => [
      for (final folder in targets.where((m) => !summary.mailboxIds.contains(m.id)))
        MenuItemButton(
          leadingIcon: Icon(switch (folder.role) {
            MailboxRole.inbox => Symbols.inbox_rounded,
            MailboxRole.archive => Symbols.archive_rounded,
            _ => Symbols.folder_rounded,
          }),
          onPressed: () => unawaited(moveThreads(ref, [summary], folder)),
          child: Text(folder.name),
        ),
    ];

List<Widget> _labelItems(WidgetRef ref, ThreadSummary summary, List<Mailbox> labels) => [
      for (final label in labels)
        CheckboxMenuButton(
          value: summary.mailboxIds.contains(label.id),
          onChanged: (checked) => applyLabels(ref, [keyOf(summary)],
              add: checked == true ? {label.id} : const {}, remove: checked == true ? const {} : {label.id}),
          child: Text(label.name),
        ),
    ];
