import 'package:plume_core/plume_core.dart';

/// In-memory [SyncStore] that also records how it was used.
class FakeSyncStore implements SyncStore {
  final state = <String, String>{};
  final mailboxes = <String, Map<String, Mailbox>>{};
  final messages = <String, Map<String, Message>>{};
  final bodies = <String, Map<String, MessageBody>>{};

  /// Names of write calls, in order.
  final writes = <String>[];

  /// Write calls made while no transaction was open.
  final writesOutsideTransaction = <String>[];
  int transactions = 0;
  int clearMailCalls = 0;
  int _open = 0;

  Map<String, Message> msgs(String accountId) => messages.putIfAbsent(accountId, () => {});

  Message? message(String accountId, String id) => messages[accountId]?[id];

  void _write(String name) {
    writes.add(name);
    if (_open == 0) writesOutsideTransaction.add(name);
  }

  @override
  Future<String?> readState(String accountId, String key) async => state['$accountId|$key'];

  @override
  Future<void> writeState(String accountId, String key, String? value) async {
    _write('writeState:$key');
    if (value == null) {
      state.remove('$accountId|$key');
    } else {
      state['$accountId|$key'] = value;
    }
  }

  @override
  Future<void> replaceMailboxes(String accountId, List<Mailbox> list) async {
    _write('replaceMailboxes');
    mailboxes[accountId] = {for (final m in list) m.id: m};
  }

  @override
  Future<void> updateMailboxCounts(String accountId, Map<String, ({int unread, int total})> counts) async {
    _write('updateMailboxCounts');
    final map = mailboxes[accountId] ?? {};
    for (final e in counts.entries) {
      final m = map[e.key];
      if (m != null) map[e.key] = m.copyWith(unreadThreads: e.value.unread, totalThreads: e.value.total);
    }
  }

  @override
  Future<void> upsertMessages(String accountId, List<Message> list) async {
    _write('upsertMessages');
    for (final m in list) {
      msgs(accountId)[m.id] = m;
    }
  }

  @override
  Future<void> applyDeltas(String accountId, List<MessageDelta> deltas) async {
    _write('applyDeltas');
    for (final d in deltas) {
      final m = msgs(accountId)[d.messageId];
      if (m == null) continue;
      msgs(accountId)[d.messageId] = m.copyWith(
        mailboxIds: {...m.mailboxIds, ...d.addMailboxes}.difference(d.removeMailboxes),
        isRead: d.isRead,
        isFlagged: d.isFlagged,
      );
    }
  }

  @override
  Future<void> deleteMessages(String accountId, List<String> ids) async {
    _write('deleteMessages');
    for (final id in ids) {
      msgs(accountId).remove(id);
      bodies[accountId]?.remove(id);
    }
  }

  @override
  Future<void> deleteThreads(String accountId, List<String> threadIds) async {
    _write('deleteThreads');
    final set = threadIds.toSet();
    msgs(accountId).removeWhere((_, m) => set.contains(m.threadId));
  }

  @override
  Future<void> renameMessages(String accountId, Map<String, String> oldToNew) async {
    _write('renameMessages');
    final all = msgs(accountId);
    final accountBodies = bodies.putIfAbsent(accountId, () => {});
    for (final MapEntry(key: from, value: to) in oldToNew.entries) {
      final m = all.remove(from);
      if (m == null || from == to) continue;
      final body = accountBodies.remove(from);
      if (!all.containsKey(to)) {
        all[to] = Message(
          accountId: m.accountId,
          id: to,
          threadId: m.threadId,
          subject: m.subject,
          from: m.from,
          to: m.to,
          cc: m.cc,
          bcc: m.bcc,
          replyTo: m.replyTo,
          date: m.date,
          snippet: m.snippet,
          isRead: m.isRead,
          isFlagged: m.isFlagged,
          isDraft: m.isDraft,
          mailboxIds: m.mailboxIds,
          attachments: m.attachments,
          messageIdHeader: m.messageIdHeader,
          inReplyTo: m.inReplyTo,
          references: m.references,
          listUnsubscribe: m.listUnsubscribe,
          size: m.size,
        );
      }
      if (body != null) accountBodies.putIfAbsent(to, () => body);
    }
  }

  @override
  Future<Set<String>> knownMessageIds(String accountId, Iterable<String> ids) async =>
      {for (final id in ids) if (msgs(accountId).containsKey(id)) id};

  @override
  Future<List<Message>> messagesInThreads(String accountId, Iterable<String> threadIds) async {
    final set = threadIds.toSet();
    return [for (final m in msgs(accountId).values) if (set.contains(m.threadId)) m];
  }

  @override
  Future<void> saveBody(String accountId, String messageId, MessageBody body) async {
    _write('saveBody');
    bodies.putIfAbsent(accountId, () => {})[messageId] = body;
  }

  @override
  Future<List<String>> messagesWithoutBody(String accountId, Iterable<String> ids) async =>
      [for (final id in ids) if (!(bodies[accountId]?.containsKey(id) ?? false)) id];

  @override
  Future<List<String>> recentMessagesWithoutBody(String accountId, String mailboxId, {int limit = 50}) async {
    final list = msgs(accountId).values
        .where((m) => m.mailboxIds.contains(mailboxId) && !(bodies[accountId]?.containsKey(m.id) ?? false))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.take(limit).map((m) => m.id).toList();
  }

  @override
  Future<void> clearMail(String accountId) async {
    _write('clearMail');
    clearMailCalls++;
    messages.remove(accountId);
    bodies.remove(accountId);
    mailboxes.remove(accountId);
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    _open++;
    try {
      return await action();
    } finally {
      _open--;
      transactions++;
    }
  }
}
