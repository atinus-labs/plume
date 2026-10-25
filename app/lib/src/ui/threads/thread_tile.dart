import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/navigation.dart';
import '../../state/avatars.dart';
import '../actions.dart';
import '../common/format.dart';
import 'thread_menu.dart';

/// One conversation in the message list.
///
/// Rows form an M3 Expressive connected group per date section. The open
/// conversation springs into a fully rounded, tinted pill; hovering reveals
/// quick actions in place of the date.
class ThreadTile extends ConsumerStatefulWidget {
  const ThreadTile({
    super.key,
    required this.thread,
    required this.index,
    required this.groupSize,
    required this.account,
    required this.showAccountDot,
  });

  final ThreadSummary thread;
  final int index;
  final int groupSize;
  final Account? account;
  final bool showAccountDot;

  @override
  ConsumerState<ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends ConsumerState<ThreadTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final key = keyOf(thread);
    final open = ref.watch(openThreadProvider.select((k) => k == key));
    final selected = ref.watch(selectionProvider.select((s) => s.contains(thread.key)));
    final selectionMode = ref.watch(selectionProvider.select((s) => s.isNotEmpty));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surfaces = PlumeSurfaces.of(context);
    final text = theme.textTheme;
    final unread = thread.isUnread;
    final myEmail = widget.account?.email ?? '';

    final others = thread.participants.where((a) => a.email.toLowerCase() != myEmail.toLowerCase());
    final sender = others.isNotEmpty ? others.last : (thread.participants.isEmpty ? null : thread.participants.last);
    final senderLabel = participantsLabel(thread.participants, myEmail);
    final fg = open ? surfaces.onSelected : scheme.onSurface;
    final muted = open ? surfaces.onSelected.withValues(alpha: 0.78) : scheme.onSurfaceVariant;
    final baseRadius = groupedRadius(widget.index, widget.groupSize);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SpringBuilder(
        value: open || selected ? 1 : 0,
        spring: Spring.spatialFast,
        builder: (context, t, child) {
          final r = unit(t);
          final radius = BorderRadius.lerp(baseRadius, Corners.all(Corners.extraLarge), r)!;
          final color = Color.lerp(
            _hover ? surfaces.itemHover : surfaces.item,
            selected ? scheme.primaryContainer.withValues(alpha: 0.55) : surfaces.selected,
            r,
          )!;
          return Material(
            color: color,
            shape: RoundedRectangleBorder(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: child,
          );
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onSecondaryTapDown: (d) => showThreadMenu(context, ref, [thread], d.globalPosition),
            child: InkWell(
              onTap: () {
                if (selectionMode) {
                  ref.read(selectionProvider.notifier).toggle(thread.key);
                } else {
                  openThread(ref, thread);
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MorphAvatar(
                      name: sender?.displayName ?? '?',
                      colorKey: sender?.email ?? thread.id,
                      image: sender?.email != null ? ref.watch(senderAvatarProvider(sender!.email)).value : null,
                      selected: selected,
                      size: 40,
                      onTap: () => ref.read(selectionProvider.notifier).toggle(thread.key),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 22,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: senderLabel),
                                      if (thread.messageCount > 1)
                                        TextSpan(
                                          text: '  ${thread.messageCount}',
                                          style: text.labelMedium?.copyWith(color: muted),
                                        ),
                                    ]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (unread ? text.titleSmallEmphasized : text.titleSmall!)
                                        .copyWith(color: fg),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _Trailing(
                                  thread: thread,
                                  hover: _hover && !selectionMode,
                                  unread: unread,
                                  color: unread && !open ? scheme.primary : muted,
                                  accountColor: widget.showAccountDot && widget.account != null
                                      ? harmonize(Color(widget.account!.color), scheme)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (thread.draftCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text('Draft', style: text.bodyMediumEmphasized.copyWith(color: scheme.error)),
                                ),
                              Expanded(
                                child: Text(
                                  thread.subject.isEmpty ? '(no subject)' : thread.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (unread ? text.bodyMediumEmphasized : text.bodyMedium!).copyWith(color: fg),
                                ),
                              ),
                              if (thread.isFlagged)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Symbols.star_rounded, fill: 1, size: 18, color: _starColor(scheme)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  thread.snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(color: muted),
                                ),
                              ),
                              if (thread.hasAttachments)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Symbols.attach_file_rounded, size: 18, color: muted),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _starColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.light ? const Color(0xFFE8A200) : const Color(0xFFFFC94A);

/// Date (and unread dot / account dot), swapped for quick actions on hover.
class _Trailing extends ConsumerWidget {
  const _Trailing({
    required this.thread,
    required this.hover,
    required this.unread,
    required this.color,
    this.accountColor,
  });

  final ThreadSummary thread;
  final bool hover;
  final bool unread;
  final Color color;
  final Color? accountColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = keyOf(thread);
    final inTrash = ref.watch(viewProvider.select((v) => v.kind == ViewKind.trash));
    final date = Row(
      key: const ValueKey('date'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accountColor != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: accountColor, shape: BoxShape.circle)),
          ),
        Text(
          listDate(thread.lastDate),
          style: (unread ? theme.textTheme.labelMediumEmphasized : theme.textTheme.labelMedium)?.copyWith(color: color),
        ),
      ],
    );
    final actions = Row(
      key: const ValueKey('actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuickAction(
          icon: inTrash ? Symbols.restore_from_trash_rounded : Symbols.archive_rounded,
          tooltip: inTrash ? 'Restore' : 'Archive (E)',
          onPressed: () => applyThreadAction(ref, inTrash ? MailAction.restore : MailAction.archive, [key]),
        ),
        _QuickAction(
          icon: inTrash ? Symbols.delete_forever_rounded : Symbols.delete_rounded,
          tooltip: inTrash ? 'Delete forever' : 'Delete (#)',
          onPressed: () => applyThreadAction(ref, inTrash ? MailAction.deleteForever : MailAction.trash, [key]),
        ),
        _QuickAction(
          icon: unread ? Symbols.drafts_rounded : Symbols.mark_email_unread_rounded,
          tooltip: unread ? 'Mark as read' : 'Mark as unread',
          onPressed: () => applyThreadAction(ref, unread ? MailAction.markRead : MailAction.markUnread, [key]),
        ),
        _QuickAction(
          icon: Symbols.star_rounded,
          filled: thread.isFlagged,
          tooltip: thread.isFlagged ? 'Unstar' : 'Star (S)',
          onPressed: () => applyThreadAction(ref, thread.isFlagged ? MailAction.unflag : MailAction.flag, [key]),
        ),
      ],
    );
    return AnimatedSwitcher(
      duration: Spring.effectsFast.duration,
      switchInCurve: Spring.standardFast.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
      child: hover ? actions : date,
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.tooltip, required this.onPressed, this.filled = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 30,
      height: 22,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 19,
        visualDensity: VisualDensity.compact,
        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(28, 22))),
        onPressed: onPressed,
        icon: Icon(icon, fill: filled ? 1 : 0, color: filled ? _starColor(scheme) : scheme.onSurfaceVariant),
      ),
    );
  }
}
