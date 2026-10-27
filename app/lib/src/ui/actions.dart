import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';

import '../state/mail.dart';
import '../state/navigation.dart';
import '../state/services.dart';
import '../state/settings.dart';
import 'toaster.dart';

export 'toaster.dart';

/// Global messenger so snackbars survive pane changes.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showSnack(
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool? showCloseIcon = true,
}) {
  Toaster.instance.show(
    message,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
    showCloseIcon: showCloseIcon,
  );
}

/// Actions that take a conversation out of the current list.
const _removing = {
  MailAction.archive,
  MailAction.trash,
  MailAction.markSpam,
  MailAction.markNotSpam,
  MailAction.restore,
  MailAction.deleteForever,
  MailAction.moveToInbox,
};

String _pastTense(MailAction action, int count) {
  final what = count == 1 ? 'Conversation' : '$count conversations';
  return switch (action) {
    MailAction.archive => '$what archived',
    MailAction.moveToInbox => '$what moved to Inbox',
    MailAction.trash => '$what moved to Trash',
    MailAction.restore => '$what restored',
    MailAction.deleteForever => '$what deleted forever',
    MailAction.markSpam => '$what marked as spam',
    MailAction.markNotSpam => '$what moved out of Spam',
    MailAction.markRead => '$what marked as read',
    MailAction.markUnread => '$what marked as unread',
    MailAction.flag => '$what starred',
    MailAction.unflag => '$what unstarred',
  };
}

/// Applies [action] to whole conversations, with optimistic UI, an undo
/// snackbar and auto-advance in the reading pane.
Future<void> applyThreadAction(WidgetRef ref, MailAction action, List<ThreadKey> threads, {bool announce = true}) async {
  if (threads.isEmpty) return;
  final engine = ref.read(engineProvider);
  final open = ref.read(openThreadProvider);
  if (open != null && threads.contains(open)) {
    if (_removing.contains(action)) {
      _advance(ref, threads.toSet());
    } else if (action == MailAction.markUnread) {
      ref.read(openThreadProvider.notifier).close();
    }
  }
  ref.read(selectionProvider.notifier).clear();

  final undos = <MailOperation>[];
  final byAccount = <String, List<String>>{};
  for (final t in threads) {
    byAccount.putIfAbsent(t.accountId, () => []).add(t.threadId);
  }
  for (final entry in byAccount.entries) {
    final undo = await engine.perform(
        ActionOperation(accountId: entry.key, scope: OperationScope.thread, ids: entry.value, action: action));
    if (undo != null) undos.add(undo);
  }

  final quiet = action == MailAction.markRead || action == MailAction.flag || action == MailAction.unflag;
  if (!announce || quiet) return;
  _snackWithUndo(engine, _pastTense(action, threads.length), undos);
}

void _snackWithUndo(MailEngine engine, String message, List<MailOperation> undos) => showSnack(
      message,
      actionLabel: undos.isEmpty ? null : 'Undo',
      onAction: () {
        for (final op in undos) {
          unawaited(engine.perform(op));
        }
      },
    );

/// Moves conversations to [folder] on folder-based (IMAP) accounts. Their
/// messages leave the folders they are filed in; replies in Sent and
/// unsent drafts stay where they are.
Future<void> moveThreads(WidgetRef ref, List<ThreadSummary> threads, Mailbox folder) async {
  if (threads.isEmpty) return;
  final engine = ref.read(engineProvider);
  final roles = {
    for (final m in ref.read(mailboxesProvider(folder.accountId)).value ?? const <Mailbox>[]) m.id: m.role,
  };
  const staying = {MailboxRole.sent, MailboxRole.drafts};
  final keys = threads.map(keyOf).toSet();
  final open = ref.read(openThreadProvider);
  if (open != null && keys.contains(open)) _advance(ref, keys);
  ref.read(selectionProvider.notifier).clear();

  final undos = <MailOperation>[];
  var moved = 0;
  for (final t in threads) {
    final sources = t.mailboxIds.where((id) => id != folder.id && !staying.contains(roles[id]));
    if (sources.isEmpty) continue;
    moved++;
    // One move per source folder, so that undo can put each message back
    // where it came from.
    for (final source in sources) {
      final undo = await engine.perform(LabelOperation(
          accountId: t.accountId, scope: OperationScope.thread, ids: [t.id], add: {folder.id}, remove: {source}));
      if (undo != null) undos.add(undo);
    }
  }
  if (moved == 0) return;
  _snackWithUndo(engine, '${moved == 1 ? 'Conversation' : '$moved conversations'} moved to ${folder.name}', undos);
}

/// Changes labels on conversations.
Future<void> applyLabels(WidgetRef ref, List<ThreadKey> threads, {Set<String> add = const {}, Set<String> remove = const {}}) async {
  final engine = ref.read(engineProvider);
  final byAccount = <String, List<String>>{};
  for (final t in threads) {
    byAccount.putIfAbsent(t.accountId, () => []).add(t.threadId);
  }
  for (final entry in byAccount.entries) {
    await engine.perform(LabelOperation(
        accountId: entry.key, scope: OperationScope.thread, ids: entry.value, add: add, remove: remove));
  }
}

/// Applies an action to single messages (inside an open conversation).
Future<void> applyMessageAction(WidgetRef ref, MailAction action, String accountId, List<String> messageIds) =>
    ref.read(engineProvider).perform(
        ActionOperation(accountId: accountId, scope: OperationScope.message, ids: messageIds, action: action));

/// Moves the reading pane to the neighbouring conversation, skipping
/// [leaving], as configured in settings.
void _advance(WidgetRef ref, Set<ThreadKey> leaving) {
  final list = ref.read(visibleThreadsProvider).value ?? const <ThreadSummary>[];
  final open = ref.read(openThreadProvider);
  final mode = ref.read(settingsProvider).afterAction;
  final notifier = ref.read(openThreadProvider.notifier);
  final index = list.indexWhere((t) => keyOf(t) == open);
  if (mode == AfterAction.list || index < 0) {
    notifier.close();
    return;
  }
  final step = mode == AfterAction.nextOlder ? 1 : -1;
  for (var i = index + step; i >= 0 && i < list.length; i += step) {
    final key = keyOf(list[i]);
    if (!leaving.contains(key)) {
      notifier.open(key);
      return;
    }
  }
  notifier.close();
}

/// Opens a conversation and marks it read.
void openThread(WidgetRef ref, ThreadSummary thread) {
  final key = keyOf(thread);
  ref.read(openThreadProvider.notifier).open(key);
  if (thread.isUnread) {
    unawaited(applyThreadAction(ref, MailAction.markRead, [key], announce: false));
  }
}

/// Moves the open conversation up or down the list (j/k).
void stepThread(WidgetRef ref, int delta) {
  final list = ref.read(visibleThreadsProvider).value ?? const <ThreadSummary>[];
  if (list.isEmpty) return;
  final open = ref.read(openThreadProvider);
  final index = open == null ? -1 : list.indexWhere((t) => keyOf(t) == open);
  final next = (index + delta).clamp(0, list.length - 1);
  openThread(ref, list[index < 0 ? 0 : next]);
}
