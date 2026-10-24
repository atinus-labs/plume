import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../actions.dart';
import '../common/empty_state.dart';
import '../compose/compose_host.dart';
import 'message_card.dart';

/// The reading pane. Cross-fades between conversations with a short
/// shared-axis style motion.
class ReaderPane extends ConsumerWidget {
  const ReaderPane({super.key, this.showBack = false});

  /// Single-pane layouts show a back button instead of the list.
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openThreadProvider);
    return AnimatedSwitcher(
      duration: Spring.standard.duration,
      switchInCurve: Spring.standard.curve,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
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
      icon: Symbols.mail_rounded,
      shape: Shapes.cookie12,
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

class _ThreadBody extends ConsumerWidget {
  const _ThreadBody({required this.thread, required this.myEmail, required this.showBack});

  final ThreadDetail thread;
  final String myEmail;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
          const Spacer(),
          if (position >= 0) ...[
            Text('${position + 1} of ${list.length}', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            _ToolButton(Symbols.chevron_left_rounded, 'Newer (K)', position > 0 ? () => stepThread(ref, -1) : null),
            _ToolButton(Symbols.chevron_right_rounded, 'Older (J)', position < list.length - 1 ? () => stepThread(ref, 1) : null),
          ],
        ],
      ),
    );

    return Stack(
      children: [
        Column(
          children: [
            toolbar,
            Expanded(
              child: SelectionContainer.disabled(
                child: Scrollbar(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              summary.subject.isEmpty ? '(no subject)' : summary.subject,
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
                      for (var i = 0; i < messages.length; i++)
                        MessageCard(
                          key: ValueKey(messages[i].id),
                          message: messages[i],
                          index: i,
                          count: messages.length,
                          myEmail: myEmail,
                          initiallyExpanded: i == messages.length - 1 || !messages[i].isRead,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(
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
      ],
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
