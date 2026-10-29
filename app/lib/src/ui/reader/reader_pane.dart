import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/avatars.dart';
import '../../state/navigation.dart';
import '../actions.dart';
import '../common/empty_state.dart';
import '../common/logo.dart';
import '../compose/compose_host.dart';
import 'message_card.dart';

/// The reading pane. Moving to an older conversation slides the new one up
/// from below and a newer one down from above, matching where it sits in
/// the list; anything else fades through.
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
    }
    return AnimatedSwitcher(
      duration: kSwitchDuration,
      transitionBuilder: _direction == 0 ? fadeThrough : sharedAxis(direction: _direction, distance: 40),
      child: open == null
          ? const _NothingOpen(key: ValueKey('empty'))
          : ThreadView(key: ValueKey(open), threadKey: open, showBack: showBack),
    );
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

class ThreadView extends ConsumerWidget {
  const ThreadView({super.key, required this.threadKey, this.showBack = false});

  final ThreadKey threadKey;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(threadDetailProvider(threadKey));
    final account = ref.watch(accountMapProvider)[threadKey.accountId];
    return detail.when(
      loading: () => const Center(child: LoadingIndicator()),
      error: (e, _) => EmptyState(icon: Symbols.error_rounded, title: 'Couldn’t open conversation', message: '$e'),
      data: (thread) {
        if (thread == null) {
          return const EmptyState(icon: Symbols.inbox_rounded, title: 'This conversation is gone', message: 'It was moved or deleted.');
        }
        return _ThreadBody(thread: thread, myEmail: account?.email ?? '', showBack: showBack);
      },
    );
  }
}

class _ThreadBody extends ConsumerStatefulWidget {
  const _ThreadBody({required this.thread, required this.myEmail, required this.showBack});

  final ThreadDetail thread;
  final String myEmail;
  final bool showBack;

  @override
  ConsumerState<_ThreadBody> createState() => _ThreadBodyState();
}

const _toolbarHeight = 64.0;

class _ThreadBodyState extends ConsumerState<_ThreadBody> {
  final _scroll = ScrollController();
  final _subjectKey = GlobalKey();

  /// Content has scrolled under the toolbar: it fills, like an M3 top app
  /// bar in its scrolled state.
  final _scrolled = ValueNotifier(false);

  /// The subject has scrolled away, so the toolbar shows it instead.
  final _titleInBar = ValueNotifier(false);

  /// The reply toolbar steps aside while reading down and comes back on the
  /// way up or at the end of the conversation, where replying is next.
  final _replyBar = ValueNotifier(true);
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
    _scrolled.dispose();
    _titleInBar.dispose();
    _replyBar.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scroll.position;
    final offset = p.pixels;
    _scrolled.value = offset > 1;
    final subject = _subjectKey.currentContext?.findRenderObject() as RenderBox?;
    _titleInBar.value = offset > (subject?.hasSize == true ? subject!.size.height - 8 : 56);
    final delta = offset - _lastOffset;
    _lastOffset = offset;
    if (offset < 48 || p.extentAfter < 48) {
      _replyBar.value = true;
    } else if (delta > 2) {
      _replyBar.value = false;
    } else if (delta < -2) {
      _replyBar.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final myEmail = widget.myEmail;
    final showBack = widget.showBack;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = thread.summary;
    final key = keyOf(summary);
    final view = ref.watch(viewProvider);
    final mailboxes = ref.watch(mailboxesProvider(summary.accountId)).value ?? const <Mailbox>[];
    final labelChips = mailboxes
        .where((m) =>
            summary.mailboxIds.contains(m.id) &&
            !m.hidden &&
            !const {MailboxRole.category, MailboxRole.important, MailboxRole.sent, MailboxRole.drafts}.contains(m.role))
        .toList();
    final messages = thread.messages.where((m) => !m.isDraft || thread.messages.length == 1).toList();
    final list = ref.watch(visibleThreadsProvider).value ?? const <ThreadSummary>[];
    final position = list.indexWhere((t) => keyOf(t) == key);
    final inTrash = view.kind == ViewKind.trash;
    final inSpam = view.kind == ViewKind.junk;
    final inInbox = summary.mailboxIds.any((id) => mailboxes.any((m) => m.id == id && m.role == MailboxRole.inbox));
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

    final toolbar = Container(
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
            _ToolButton(Symbols.archive_rounded, 'Archive (E)', () => applyThreadAction(ref, MailAction.archive, [key]))
          else
            _ToolButton(Symbols.move_to_inbox_rounded, 'Move to Inbox', () => applyThreadAction(ref, MailAction.moveToInbox, [key])),
          if (inTrash || inSpam)
            _ToolButton(Symbols.delete_forever_rounded, 'Delete forever', () => applyThreadAction(ref, MailAction.deleteForever, [key]))
          else
            _ToolButton(Symbols.delete_rounded, 'Delete (#)', () => applyThreadAction(ref, MailAction.trash, [key])),
          if (!inSpam && !inTrash)
            _ToolButton(Symbols.report_rounded, 'Report spam (!)', () => applyThreadAction(ref, MailAction.markSpam, [key])),
          _ToolButton(Symbols.mark_email_unread_rounded, 'Mark as unread (Shift+U)', () => applyThreadAction(ref, MailAction.markUnread, [key])),
          if (folders)
            _MoveMenu(summary: summary, targets: ref.watch(moveTargetsProvider(summary.accountId)))
          else
            _LabelMenu(summary: summary, labels: mailboxes.where((m) => m.kind == MailboxKind.user && !m.hidden).toList()),
          // The subject moves up here once it has scrolled out of view.
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _titleInBar,
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
            AnimatedCount(
              position + 1,
              format: (n) => '$n of ${list.length}',
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            _ToolButton(Symbols.chevron_left_rounded, 'Newer (K)', position > 0 ? () => stepThread(ref, -1) : null),
            _ToolButton(Symbols.chevron_right_rounded, 'Older (J)', position < list.length - 1 ? () => stepThread(ref, 1) : null),
          ],
        ],
      ),
    );

    // One step above the cards, so they read as passing underneath.
    final fill = scheme.brightness == Brightness.light ? scheme.surfaceContainer : scheme.surfaceContainerHigh;
    var index = 0;
    return Stack(
      children: [
        Positioned.fill(
          child: SelectionContainer.disabled(
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
                      child: MessageCard(
                        message: m,
                        index: index++,
                        count: cardCount,
                        myEmail: myEmail,
                        initiallyExpanded: m == messages.last || !m.isRead,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ValueListenableBuilder(
            valueListenable: _scrolled,
            builder: (context, scrolled, child) => SpringBuilder(
              value: scrolled ? 1 : 0,
              spring: Spring.effects,
              builder: (context, t, child) => ColoredBox(color: fill.withValues(alpha: unit(t)), child: child),
              child: child,
            ),
            child: toolbar,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: _replyBar,
              builder: (context, visible, child) => IgnorePointer(
                ignoring: !visible,
                child: SpringBuilder(
                  value: visible ? 1 : 0,
                  spring: visible ? Spring.spatial : Spring.standard,
                  builder: (context, t, child) => Transform.translate(
                    offset: Offset(0, (1 - t) * 96),
                    child: Opacity(opacity: unit(t), child: child),
                  ),
                  child: child,
                ),
              ),
              child: FloatingToolbar(
                vibrant: true,
                children: [
                  _ReplyButton(icon: Symbols.reply_rounded, label: 'Reply', onPressed: () => ref.read(composeProvider.notifier).reply(messages.last, all: false)),
                  _ReplyButton(icon: Symbols.reply_all_rounded, label: 'Reply all', onPressed: () => ref.read(composeProvider.notifier).reply(messages.last, all: true)),
                  _ReplyButton(icon: Symbols.forward_rounded, label: 'Forward', onPressed: () => ref.read(composeProvider.notifier).forward(messages.last)),
                ],
              ),
            ),
          ),
        ),
      ],
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
  const _ToolButton(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
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
    final choices = targets.where((m) => !summary.mailboxIds.contains(m.id)).toList();
    if (choices.isEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      menuChildren: [
        for (final folder in choices)
          MenuItemButton(
            leadingIcon: Icon(switch (folder.role) {
              MailboxRole.inbox => Symbols.inbox_rounded,
              MailboxRole.archive => Symbols.archive_rounded,
              _ => Symbols.folder_rounded,
            }),
            onPressed: () => unawaited(moveThreads(ref, [summary], folder)),
            child: Text(folder.name),
          ),
      ],
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
    final key = keyOf(summary);
    return MenuAnchor(
      menuChildren: [
        for (final label in labels)
          CheckboxMenuButton(
            value: summary.mailboxIds.contains(label.id),
            onChanged: (checked) => applyLabels(ref, [key],
                add: checked == true ? {label.id} : const {}, remove: checked == true ? const {} : {label.id}),
            child: Text(label.name),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Labels (L)',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Symbols.label_rounded),
      ),
    );
  }
}
