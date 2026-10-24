import 'address.dart';
import 'message.dart';

/// A conversation as shown in message lists. Derived by the store from the
/// thread's messages; never written directly by providers.
final class ThreadSummary {
  const ThreadSummary({
    required this.accountId,
    required this.id,
    required this.subject,
    required this.snippet,
    required this.lastDate,
    required this.messageCount,
    required this.unreadCount,
    required this.isFlagged,
    required this.hasAttachments,
    required this.participants,
    required this.mailboxIds,
    this.draftCount = 0,
  });

  final String accountId;
  final String id;
  final String subject;
  final String snippet;
  final DateTime lastDate;
  final int messageCount;
  final int unreadCount;
  final bool isFlagged;
  final bool hasAttachments;

  /// Senders in conversation order, de-duplicated, at most a handful.
  final List<Address> participants;
  final Set<String> mailboxIds;
  final int draftCount;

  bool get isUnread => unreadCount > 0;

  /// Stable key across accounts.
  String get key => '$accountId/$id';

  @override
  bool operator ==(Object other) =>
      other is ThreadSummary &&
      other.accountId == accountId &&
      other.id == id &&
      other.subject == subject &&
      other.snippet == snippet &&
      other.lastDate == lastDate &&
      other.messageCount == messageCount &&
      other.unreadCount == unreadCount &&
      other.isFlagged == isFlagged &&
      other.hasAttachments == hasAttachments &&
      other.draftCount == draftCount &&
      other.mailboxIds.length == mailboxIds.length &&
      other.mailboxIds.containsAll(mailboxIds);

  @override
  int get hashCode => Object.hash(accountId, id, lastDate, unreadCount, isFlagged, messageCount, snippet);
}

/// A full conversation for the reading pane.
final class ThreadDetail {
  const ThreadDetail({required this.summary, required this.messages});

  final ThreadSummary summary;

  /// Oldest first.
  final List<Message> messages;
}
