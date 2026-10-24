import '../models/mailbox.dart';
import '../models/message.dart';

/// A change to a message's mailbox membership or keywords coming from the
/// server (e.g. a Gmail history record). Null fields are left unchanged.
final class MessageDelta {
  const MessageDelta(
    this.messageId, {
    this.addMailboxes = const {},
    this.removeMailboxes = const {},
    this.isRead,
    this.isFlagged,
  });

  final String messageId;
  final Set<String> addMailboxes;
  final Set<String> removeMailboxes;
  final bool? isRead;
  final bool? isFlagged;
}

/// The write side of the local mail store, as used by providers while
/// syncing. Implementations keep derived thread rows consistent with the
/// messages they are given, and notify readers of changes.
///
/// All methods are scoped to one account so that a misbehaving provider can
/// never touch another account's data.
abstract interface class SyncStore {
  /// Opaque provider sync state (cursors, history ids...).
  Future<String?> readState(String accountId, String key);
  Future<void> writeState(String accountId, String key, String? value);

  /// Replaces the account's mailbox list. Mailboxes not present are removed.
  Future<void> replaceMailboxes(String accountId, List<Mailbox> mailboxes);

  /// Updates the counters of existing mailboxes without touching the rest.
  Future<void> updateMailboxCounts(String accountId, Map<String, ({int unread, int total})> counts);

  /// Inserts or fully replaces message metadata (not bodies). Thread rows for
  /// the affected threads are recomputed.
  Future<void> upsertMessages(String accountId, List<Message> messages);

  /// Applies incremental membership/keyword changes to known messages.
  /// Unknown message ids are ignored.
  Future<void> applyDeltas(String accountId, List<MessageDelta> deltas);

  /// Removes messages (and their bodies). Empty threads disappear.
  Future<void> deleteMessages(String accountId, List<String> messageIds);

  /// Removes every message in the given threads.
  Future<void> deleteThreads(String accountId, List<String> threadIds);

  /// Gives stored messages new ids, keeping their metadata, membership and
  /// cached bodies. Folder-based providers need this because a move gives
  /// a message a new server identity (an IMAP move assigns a new UID), and
  /// re-downloading it would make the message flicker and lose its body.
  ///
  /// Unknown old ids are ignored. When a new id is already stored (a sync
  /// fetched the moved copy first), the old message is removed instead and
  /// its body is kept for the new id if that one has none.
  Future<void> renameMessages(String accountId, Map<String, String> oldToNew);

  /// Of [messageIds], returns the ones already stored.
  Future<Set<String>> knownMessageIds(String accountId, Iterable<String> messageIds);

  /// Messages in [threadIds] currently stored, for providers that need to
  /// diff a server thread against local state.
  Future<List<Message>> messagesInThreads(String accountId, Iterable<String> threadIds);

  /// Stores a decoded body.
  Future<void> saveBody(String accountId, String messageId, MessageBody body);

  /// Of [messageIds], returns those whose body is not cached yet.
  Future<List<String>> messagesWithoutBody(String accountId, Iterable<String> messageIds);

  /// Newest messages in [mailboxId] whose bodies are not cached, for
  /// background prefetching so that opening mail is instant.
  Future<List<String>> recentMessagesWithoutBody(String accountId, String mailboxId, {int limit = 50});

  /// Wipes all mail data for the account (keeps the account itself). Used
  /// before a full resync.
  Future<void> clearMail(String accountId);

  /// Runs [action] atomically. Change notifications are coalesced until the
  /// outermost transaction completes.
  Future<T> transaction<T>(Future<T> Function() action);
}
