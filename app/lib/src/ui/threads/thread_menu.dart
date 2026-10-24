import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../actions.dart';

/// Right-click menu for one or more conversations.
Future<void> showThreadMenu(BuildContext context, WidgetRef ref, List<ThreadSummary> threads, Offset position) async {
  if (threads.isEmpty) return;
  final keys = threads.map(keyOf).toList();
  final view = ref.read(viewProvider);
  final anyUnread = threads.any((t) => t.isUnread);
  final anyFlagged = threads.any((t) => t.isFlagged);
  final sameAccount = threads.every((t) => t.accountId == threads.first.accountId);
  final folders = sameAccount && ref.read(usesFoldersProvider(threads.first.accountId));
  final labels = sameAccount && !folders
      ? (ref.read(mailboxesProvider(threads.first.accountId)).value ?? const <Mailbox>[])
          .where((m) => m.kind == MailboxKind.user && !m.hidden)
          .toList()
      : const <Mailbox>[];
  final moveTargets = folders
      ? ref
          .read(moveTargetsProvider(threads.first.accountId))
          .where((m) => !threads.every((t) => t.mailboxIds.contains(m.id)))
          .toList()
      : const <Mailbox>[];
  final inTrash = view.kind == ViewKind.trash;
  final inSpam = view.kind == ViewKind.junk;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

  PopupMenuItem<VoidCallback> item(IconData icon, String label, VoidCallback action, {String? shortcut}) =>
      PopupMenuItem(
        value: action,
        height: 44,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(label)),
            if (shortcut != null)
              Text(shortcut, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );

  final choice = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (inTrash)
        item(Symbols.restore_from_trash_rounded, 'Restore', () => applyThreadAction(ref, MailAction.restore, keys))
      else if (inSpam)
        item(Symbols.report_off_rounded, 'Not spam', () => applyThreadAction(ref, MailAction.markNotSpam, keys))
      else if (view.kind == ViewKind.inbox)
        item(Symbols.archive_rounded, 'Archive', () => applyThreadAction(ref, MailAction.archive, keys), shortcut: 'E')
      else
        item(Symbols.move_to_inbox_rounded, 'Move to Inbox', () => applyThreadAction(ref, MailAction.moveToInbox, keys)),
      if (inTrash || inSpam)
        item(Symbols.delete_forever_rounded, 'Delete forever', () => applyThreadAction(ref, MailAction.deleteForever, keys))
      else
        item(Symbols.delete_rounded, 'Delete', () => applyThreadAction(ref, MailAction.trash, keys), shortcut: '#'),
      item(anyUnread ? Symbols.drafts_rounded : Symbols.mark_email_unread_rounded, anyUnread ? 'Mark as read' : 'Mark as unread',
          () => applyThreadAction(ref, anyUnread ? MailAction.markRead : MailAction.markUnread, keys),
          shortcut: anyUnread ? 'Shift+I' : 'Shift+U'),
      item(Symbols.star_rounded, anyFlagged ? 'Remove star' : 'Add star',
          () => applyThreadAction(ref, anyFlagged ? MailAction.unflag : MailAction.flag, keys), shortcut: 'S'),
      if (!inSpam && !inTrash)
        item(Symbols.report_rounded, 'Report spam', () => applyThreadAction(ref, MailAction.markSpam, keys), shortcut: '!'),
      if (moveTargets.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final folder in moveTargets.take(12))
          item(
            switch (folder.role) {
              MailboxRole.inbox => Symbols.inbox_rounded,
              MailboxRole.archive => Symbols.archive_rounded,
              _ => Symbols.folder_rounded,
            },
            'Move to ${folder.name}',
            () => moveThreads(ref, threads, folder),
          ),
      ],
      if (labels.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final label in labels.take(12))
          CheckedPopupMenuItem<VoidCallback>(
            value: () {
              final has = threads.every((t) => t.mailboxIds.contains(label.id));
              applyLabels(ref, keys, add: has ? const {} : {label.id}, remove: has ? {label.id} : const {});
            },
            checked: threads.every((t) => t.mailboxIds.contains(label.id)),
            child: Text(label.name),
          ),
      ],
    ],
  );
  choice?.call();
}
