import '../models/message.dart';

/// What an account's sync machinery is doing right now.
enum SyncPhase {
  idle,
  syncing,

  /// The last attempt failed for a transient reason; retrying with backoff.
  offline,

  /// Credentials were rejected; nothing runs until the user signs in again.
  needsReauth,
}

/// Observable sync state of one account, for status UI.
final class AccountSyncStatus {
  const AccountSyncStatus({
    required this.accountId,
    this.phase = SyncPhase.idle,
    this.lastSynced,
    this.lastError,
    this.initialSyncDone = false,
    this.pushConnected = false,
  });

  final String accountId;
  final SyncPhase phase;
  final DateTime? lastSynced;
  final String? lastError;

  /// False until the first full sync completed, so the UI can show a
  /// first-run progress state instead of an empty inbox.
  final bool initialSyncDone;

  /// Whether the real-time change stream is currently connected.
  final bool pushConnected;

  AccountSyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSynced,
    String? lastError,
    bool clearError = false,
    bool? initialSyncDone,
    bool? pushConnected,
  }) =>
      AccountSyncStatus(
        accountId: accountId,
        phase: phase ?? this.phase,
        lastSynced: lastSynced ?? this.lastSynced,
        lastError: clearError ? null : (lastError ?? this.lastError),
        initialSyncDone: initialSyncDone ?? this.initialSyncDone,
        pushConnected: pushConnected ?? this.pushConnected,
      );
}

/// New mail that arrived during an incremental sync.
final class NewMailEvent {
  const NewMailEvent(this.accountId, this.messages);

  final String accountId;
  final List<Message> messages;
}

/// A sent message, or a failure to send one.
sealed class OutboxEvent {
  const OutboxEvent(this.outboxId, this.accountId);

  final int outboxId;
  final String accountId;
}

final class OutboxSent extends OutboxEvent {
  const OutboxSent(super.outboxId, super.accountId);
}

final class OutboxFailed extends OutboxEvent {
  const OutboxFailed(super.outboxId, super.accountId, this.error, {required this.willRetry});

  final String error;
  final bool willRetry;
}
