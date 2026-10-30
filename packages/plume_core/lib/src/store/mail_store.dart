import '../models/account.dart';
import '../models/address.dart';
import '../models/filter.dart';
import '../models/mailbox.dart';
import '../models/message.dart';
import '../models/outgoing.dart';
import '../models/thread.dart';
import '../ops/mail_operation.dart';
import 'sync_store.dart';

/// A persisted operation waiting to be replayed against the server.
final class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.operation,
    required this.attempts,
    this.lastError,
    this.notBefore,
  });

  final int id;
  final MailOperation operation;
  final int attempts;
  final String? lastError;
  final DateTime? notBefore;
}

/// Lifecycle of a message in the outbox.
enum OutboxState {
  /// Waiting for the undo window to pass.
  scheduled,
  sending,

  /// Failed transiently; will be retried.
  retrying,

  /// Failed permanently; needs user attention.
  failed,
}

/// A message queued for sending.
final class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.message,
    required this.sendAt,
    required this.state,
    this.attempts = 0,
    this.lastError,
  });

  final int id;
  final OutgoingMessage message;
  final DateTime sendAt;
  final OutboxState state;
  final int attempts;
  final String? lastError;
}

/// A draft kept on this device until the server has it, so that what is
/// written offline is not lost. One that was never uploaded shows in the
/// account's Drafts mailbox as a message of its own (see [messageIdOf]).
final class LocalDraft {
  const LocalDraft({
    required this.id,
    required this.accountId,
    required this.message,
    required this.draftId,
    required this.revision,
    required this.uploadedRevision,
  });

  final int id;
  final String accountId;

  /// The draft as last written, its `draftId` set to [draftId]. Null once
  /// discarded: the row then stays until the server draft is deleted.
  final OutgoingMessage? message;

  /// The server draft holding it, once it has been uploaded.
  final String? draftId;

  /// Bumped by every save.
  final int revision;

  /// The revision the server has; 0 for none.
  final int uploadedRevision;

  bool get isDiscarded => message == null;

  /// Whether the server has it as last written.
  bool get isUploaded => uploadedRevision >= revision;

  static const _prefix = 'local-draft:';

  /// The message (and, for a new message, thread) id standing for draft
  /// [id] in the mail tables while the server does not have it.
  static String messageIdOf(int id) => '$_prefix$id';

  /// The draft a message or thread id stands for, or null when it is a
  /// server id.
  static int? idOf(String messageId) =>
      messageId.startsWith(_prefix) ? int.tryParse(messageId.substring(_prefix.length)) : null;
}

/// The complete local store: provider-facing [SyncStore] plus the reactive
/// read API used by the UI and the queues used by the sync engine.
abstract interface class MailStore implements SyncStore {
  // Accounts ---------------------------------------------------------------

  Stream<List<Account>> watchAccounts();
  Future<List<Account>> accounts();
  Future<void> saveAccount(Account account);

  /// Deletes the account and all of its data.
  Future<void> deleteAccount(String accountId);

  // Mailboxes --------------------------------------------------------------

  /// Mailboxes of one account, or of all accounts when [accountId] is null.
  Stream<List<Mailbox>> watchMailboxes({String? accountId});
  Future<List<Mailbox>> mailboxes(String accountId);

  // Threads ----------------------------------------------------------------

  /// Threads matching [filter], newest first.
  Stream<List<ThreadSummary>> watchThreads(ThreadFilter filter, {int limit = 300});

  /// Number of unread threads matching [filter].
  Stream<int> watchUnreadCount(ThreadFilter filter);

  /// A conversation with its messages, or null once it no longer exists.
  Stream<ThreadDetail?> watchThread(String accountId, String threadId);

  /// Message ids belonging to [threadIds], used to expand thread-scoped
  /// operations for providers that work per message.
  Future<List<String>> messageIdsOfThreads(String accountId, Iterable<String> threadIds);

  Future<MessageBody?> body(String accountId, String messageId);

  /// Full-text search over cached mail. Supports plain words plus `from:`,
  /// `to:`, `subject:`, `has:attachment`, `is:unread`, `is:starred`.
  Future<List<ThreadSummary>> searchLocal(String query, {Set<String>? accountIds, int limit = 100});

  /// Known correspondents matching [prefix], most frequent first, for
  /// recipient autocompletion.
  Future<List<Address>> suggestAddresses(String prefix, {int limit = 8});

  // Optimistic local changes -----------------------------------------------

  /// Applies [mutation] to messages (or to every message of threads, by
  /// [scope]) and recomputes the affected threads.
  Future<void> applyLocalMutation(String accountId, OperationScope scope, List<String> ids, LocalMutation mutation);

  // Operation queue --------------------------------------------------------

  Future<int> enqueueOperation(MailOperation operation);

  /// Pending operations in insertion order.
  Future<List<PendingOperation>> pendingOperations({String? accountId});
  Future<void> completeOperation(int id);
  Future<void> deferOperation(int id, {required String error, required DateTime notBefore});

  // Outbox -----------------------------------------------------------------

  Future<int> enqueueOutgoing(OutgoingMessage message, DateTime sendAt);
  Stream<List<OutboxEntry>> watchOutbox();
  Future<List<OutboxEntry>> outbox();
  /// Updates an entry. Moving to [OutboxState.retrying] or
  /// [OutboxState.failed] increments its attempt counter.
  Future<void> updateOutbox(int id, {required OutboxState state, String? error, DateTime? sendAt});

  /// Removes an entry unconditionally (after it was sent).
  Future<void> deleteOutgoing(int id);

  /// Removes an outbox entry, returning it (for undo-send). Returns null when
  /// it is already being sent.
  Future<OutboxEntry?> takeOutgoing(int id);

  // Drafts kept on this device ---------------------------------------------

  /// Saves [message] as draft [id], or as a new draft when [id] is null or
  /// was sent or discarded. A new draft for a server draft that is kept
  /// already ([OutgoingMessage.draftId]) updates that one instead. Until
  /// the draft is uploaded, it shows in the account's Drafts mailbox.
  Future<LocalDraft> saveLocalDraft(OutgoingMessage message, {int? id});

  Future<LocalDraft?> localDraft(int id);

  /// The draft kept for server draft [draftId], unless discarded.
  Future<LocalDraft?> localDraftFor(String accountId, String draftId);

  /// The account's drafts, oldest first.
  Future<List<LocalDraft>> localDrafts(String accountId);

  /// Records that the server has [revision] of draft [id] as [draftId].
  /// Returns false when the draft was sent meanwhile.
  Future<bool> markLocalDraftUploaded(int id, {required int revision, required String draftId});

  /// Removes draft [id] to send it, returning it. Null when it was
  /// discarded or is gone.
  Future<LocalDraft?> takeLocalDraft(int id);

  /// Discards draft [id] (or the one kept for [draftId]). When a server
  /// draft holds it, the row stays, without its message, until
  /// [deleteLocalDraft] after the server draft is deleted.
  Future<void> discardLocalDraft(String accountId, {int? id, String? draftId});

  Future<void> deleteLocalDraft(int id);

  /// After a sync: takes out of the mail tables the drafts the server had
  /// before [uploadedBefore], as the sync brought in its own copy, and puts
  /// back the ones not uploaded yet that a full resync wiped.
  Future<void> settleLocalDrafts(String accountId, {required DateTime uploadedBefore});

  /// Forgets drafts the server has as last written. Call at start, when no
  /// compose window has them open.
  Future<void> pruneLocalDrafts();

  // Settings ---------------------------------------------------------------

  /// Small app-wide key/value settings.
  Future<String?> readSetting(String key);
  Future<void> writeSetting(String key, String? value);
  Stream<String?> watchSetting(String key);
}
