/// User intents on threads or messages. These are provider-neutral: each
/// provider decides how an intent maps onto its API (Gmail archives by
/// removing the INBOX label; IMAP moves to an Archive folder).
enum MailAction {
  archive,
  moveToInbox,
  trash,

  /// Take out of the trash back to where it was (Gmail: untrash).
  restore,

  /// Permanently delete. Only offered inside Trash and Junk.
  deleteForever,
  markSpam,
  markNotSpam,
  markRead,
  markUnread,
  flag,
  unflag,
}

/// Which objects an operation targets.
enum OperationScope { thread, message }

/// A queued, persisted change to apply to the server. Operations are applied
/// optimistically to the local store first and then replayed against the
/// provider by the operation queue, surviving restarts and offline periods.
sealed class MailOperation {
  const MailOperation({required this.accountId, required this.scope, required this.ids});

  final String accountId;
  final OperationScope scope;

  /// Thread ids or message ids, depending on [scope].
  final List<String> ids;

  Map<String, Object?> toJson();

  static MailOperation fromJson(Map<String, Object?> json) {
    final accountId = json['account']! as String;
    final scope = OperationScope.values.byName(json['scope']! as String);
    final ids = (json['ids']! as List).cast<String>();
    return switch (json['type']) {
      'action' => ActionOperation(
          accountId: accountId,
          scope: scope,
          ids: ids,
          action: MailAction.values.byName(json['action']! as String),
        ),
      'labels' => LabelOperation(
          accountId: accountId,
          scope: scope,
          ids: ids,
          add: (json['add']! as List).cast<String>().toSet(),
          remove: (json['remove']! as List).cast<String>().toSet(),
        ),
      _ => throw FormatException('Unknown operation ${json['type']}'),
    };
  }
}

/// One of the standard [MailAction]s.
final class ActionOperation extends MailOperation {
  const ActionOperation({
    required super.accountId,
    required super.scope,
    required super.ids,
    required this.action,
  });

  final MailAction action;

  @override
  Map<String, Object?> toJson() => {
        'type': 'action',
        'account': accountId,
        'scope': scope.name,
        'ids': ids,
        'action': action.name,
      };
}

/// Add/remove arbitrary mailboxes (labels, or a folder move expressed as
/// add-one/remove-one).
final class LabelOperation extends MailOperation {
  const LabelOperation({
    required super.accountId,
    required super.scope,
    required super.ids,
    this.add = const {},
    this.remove = const {},
  });

  final Set<String> add;
  final Set<String> remove;

  @override
  Map<String, Object?> toJson() => {
        'type': 'labels',
        'account': accountId,
        'scope': scope.name,
        'ids': ids,
        'add': add.toList(),
        'remove': remove.toList(),
      };
}

/// The local effect of an operation, computed by the provider so that the
/// store can update optimistically without knowing provider semantics.
final class LocalMutation {
  const LocalMutation({
    this.addMailboxes = const {},
    this.removeMailboxes = const {},
    this.setRead,
    this.setFlagged,
    this.delete = false,
    this.onlyIn,
  });

  final Set<String> addMailboxes;
  final Set<String> removeMailboxes;

  /// When set, only messages currently in one of these mailboxes are
  /// changed. Folder-based providers use it to express moves: archiving an
  /// IMAP conversation moves its inbox messages to Archive but leaves the
  /// user's replies in Sent alone.
  final Set<String>? onlyIn;
  final bool? setRead;
  final bool? setFlagged;

  /// Remove the messages from the local store entirely.
  final bool delete;

  bool get isNoop =>
      addMailboxes.isEmpty && removeMailboxes.isEmpty && setRead == null && setFlagged == null && !delete;
}
