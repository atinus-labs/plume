import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../models/account.dart';
import '../models/filter.dart';
import '../models/mailbox.dart';
import '../models/message.dart';
import '../models/outgoing.dart';
import '../ops/mail_operation.dart';
import '../provider/errors.dart';
import '../provider/mail_provider.dart';
import '../store/mail_store.dart';
import 'account_runtime.dart';
import 'account_status.dart';

final _log = Logger('plume.engine');

/// The single entry point the UI uses for anything that talks to servers.
///
/// It owns one [AccountRuntime] per account, applies user operations
/// optimistically, and exposes sync status, new-mail and outbox events.
/// Reads go straight to the [MailStore], which is reactive.
final class MailEngine {
  MailEngine({
    required this.store,
    required List<MailProviderFactory> factories,
    required this.tokenSourceFor,
    this.foregroundInterval = const Duration(minutes: 2),
    this.backgroundInterval = const Duration(minutes: 10),
  }) : _factories = {for (final f in factories) f.kind: f};

  final MailStore store;
  final Map<String, MailProviderFactory> _factories;

  /// Supplies credentials for an account.
  final TokenSource Function(Account account) tokenSourceFor;
  final Duration foregroundInterval;
  final Duration backgroundInterval;

  final _runtimes = <String, AccountRuntime>{};
  final _restarting = <String>{};
  final _statuses = <String, AccountSyncStatus>{};
  final _statusController = StreamController<Map<String, AccountSyncStatus>>.broadcast();
  final _newMail = StreamController<NewMailEvent>.broadcast();
  final _outboxEvents = StreamController<OutboxEvent>.broadcast();
  StreamSubscription<List<Account>>? _accountsSub;
  bool _foreground = true;
  bool _started = false;
  bool _disposed = false;

  /// Sync status per account id. Emits the full map on every change.
  Stream<Map<String, AccountSyncStatus>> get statuses => _statusController.stream;
  Map<String, AccountSyncStatus> get currentStatuses => Map.unmodifiable(_statuses);

  /// Mail that arrived during incremental syncs, for notifications.
  Stream<NewMailEvent> get newMail => _newMail.stream;
  Stream<OutboxEvent> get outboxEvents => _outboxEvents.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _reconcile(await store.accounts());
    _accountsSub = store.watchAccounts().listen(_reconcile);
  }

  void _reconcile(List<Account> accounts) {
    final ids = accounts.map((a) => a.id).toSet();
    for (final id in _runtimes.keys.toList()) {
      if (!ids.contains(id)) {
        unawaited(_runtimes.remove(id)!.dispose());
        _statuses.remove(id);
        _emitStatuses();
      }
    }
    for (final account in accounts) {
      if (_runtimes.containsKey(account.id) || _restarting.contains(account.id)) continue;
      if (account.status == AccountStatus.needsReauth) {
        _statuses[account.id] = AccountSyncStatus(accountId: account.id, phase: SyncPhase.needsReauth);
        _emitStatuses();
        continue;
      }
      _startRuntime(account);
    }
  }

  void _startRuntime(Account account) {
    final factory = _factories[account.provider];
    if (factory == null) {
      _log.severe('No provider registered for "${account.provider}"');
      return;
    }
    final runtime = AccountRuntime(
      account: account,
      provider: factory.create(account, tokenSourceFor(account)),
      store: store,
      syncInterval: _foreground ? foregroundInterval : backgroundInterval,
      onStatus: (s) {
        _statuses[account.id] = s;
        _emitStatuses();
      },
      onNewMail: _newMail.add,
      onOutbox: _outboxEvents.add,
      onNeedsReauth: () => unawaited(_markNeedsReauth(account.id)),
    );
    // Never leave two runtimes (and two sets of server connections) running
    // for one account.
    final previous = _runtimes[account.id];
    if (previous != null) unawaited(previous.dispose());
    _runtimes[account.id] = runtime;
    runtime.start();
  }

  Future<void> _markNeedsReauth(String accountId) async {
    final account = (await store.accounts()).where((a) => a.id == accountId).firstOrNull;
    if (account != null && account.status != AccountStatus.needsReauth) {
      await store.saveAccount(account.copyWith(status: AccountStatus.needsReauth));
    }
  }

  /// Restarts an account after the user signed in again.
  Future<void> restartAccount(String accountId) async {
    // While restarting, account list updates must not start a runtime of
    // their own (saving the account below emits one).
    _restarting.add(accountId);
    try {
      await _runtimes.remove(accountId)?.dispose();
      final account = (await store.accounts()).where((a) => a.id == accountId).firstOrNull;
      if (account == null || _disposed) return;
      final fixed = account.copyWith(status: AccountStatus.ok);
      if (fixed != account) await store.saveAccount(fixed);
      _startRuntime(fixed);
    } finally {
      _restarting.remove(accountId);
    }
  }

  void _emitStatuses() {
    if (!_statusController.isClosed) _statusController.add(Map.unmodifiable(_statuses));
  }

  /// Whether the window is visible. Background mode syncs less often and
  /// relies on push for promptness.
  set foreground(bool value) {
    if (value == _foreground) return;
    _foreground = value;
    for (final r in _runtimes.values) {
      r.syncInterval = value ? foregroundInterval : backgroundInterval;
    }
    if (value) syncAll();
  }

  bool get foreground => _foreground;

  /// Syncs every account now.
  void syncAll() {
    for (final r in _runtimes.values) {
      unawaited(r.requestSync());
    }
  }

  Future<void> syncAccount(String accountId) => _runtimes[accountId]?.requestSync() ?? Future.value();

  /// Call after system resume or when connectivity returns.
  void wake() {
    for (final r in _runtimes.values) {
      r.wake();
    }
  }

  // Operations ---------------------------------------------------------------

  /// Applies [operation] locally right away and queues it for the server.
  ///
  /// Returns the operation that undoes it, or null when it can't be undone.
  /// For folder moves that affect only part of a conversation (an IMAP
  /// archive leaves the replies in Sent alone), the undo names exactly the
  /// messages that moved, so it doesn't pull the rest of the conversation
  /// along.
  Future<MailOperation?> perform(MailOperation operation) async {
    final runtime = _requireRuntime(operation.accountId);
    final mailboxes = await store.mailboxes(operation.accountId);
    final mutation = runtime.provider.localEffect(operation, mailboxes);
    var undo = inverseOf(operation);
    await store.transaction(() async {
      final onlyIn = mutation.onlyIn;
      if (undo != null && onlyIn != null && operation.scope == OperationScope.thread) {
        final moved = [
          for (final m in await store.messagesInThreads(operation.accountId, operation.ids))
            if (m.mailboxIds.any(onlyIn.contains)) m.id,
        ];
        undo = moved.isEmpty ? null : _retarget(undo!, OperationScope.message, moved);
      }
      if (!mutation.isNoop) {
        await store.applyLocalMutation(
            operation.accountId, operation.scope, _localIds(runtime.provider, operation), mutation);
      }
      await store.enqueueOperation(operation);
    });
    runtime.kickOperations();
    return undo;
  }

  /// Message ids as currently stored; an undo may name messages by the ids
  /// they had before a move.
  static List<String> _localIds(MailProvider provider, MailOperation op) =>
      op.scope == OperationScope.message ? provider.currentMessageIds(op.ids) : op.ids;

  static MailOperation _retarget(MailOperation op, OperationScope scope, List<String> ids) => switch (op) {
        ActionOperation(:final action) =>
          ActionOperation(accountId: op.accountId, scope: scope, ids: ids, action: action),
        LabelOperation(:final add, :final remove) =>
          LabelOperation(accountId: op.accountId, scope: scope, ids: ids, add: add, remove: remove),
      };

  /// The operation that reverts an [ActionOperation], for undo snackbars.
  /// Returns null when the action cannot be undone (delete forever).
  static MailOperation? inverseOf(MailOperation operation) {
    switch (operation) {
      case ActionOperation(:final action):
        final inverse = switch (action) {
          MailAction.archive => MailAction.moveToInbox,
          MailAction.moveToInbox => MailAction.archive,
          MailAction.trash => MailAction.restore,
          MailAction.restore => MailAction.trash,
          MailAction.markSpam => MailAction.markNotSpam,
          MailAction.markNotSpam => MailAction.markSpam,
          MailAction.markRead => MailAction.markUnread,
          MailAction.markUnread => MailAction.markRead,
          MailAction.flag => MailAction.unflag,
          MailAction.unflag => MailAction.flag,
          MailAction.deleteForever => null,
        };
        if (inverse == null) return null;
        return ActionOperation(
            accountId: operation.accountId, scope: operation.scope, ids: operation.ids, action: inverse);
      case LabelOperation(:final add, :final remove):
        return LabelOperation(
            accountId: operation.accountId, scope: operation.scope, ids: operation.ids, add: remove, remove: add);
    }
  }

  // Sending ------------------------------------------------------------------

  /// Queues [message] to be sent after [delay] (the undo window). Returns the
  /// outbox id to pass to [cancelSend].
  Future<int> send(OutgoingMessage message, {Duration delay = const Duration(seconds: 5)}) async {
    final runtime = _requireRuntime(message.accountId);
    final id = await store.enqueueOutgoing(message, DateTime.now().add(delay));
    runtime.kickOutbox();
    return id;
  }

  /// Takes a message back out of the outbox. Returns null when it is
  /// already on its way.
  Future<OutgoingMessage?> cancelSend(int outboxId) async => (await store.takeOutgoing(outboxId))?.message;

  /// Retries a failed outbox entry now.
  Future<void> retrySend(int outboxId) async {
    final entry = (await store.outbox()).where((e) => e.id == outboxId).firstOrNull;
    if (entry == null) return;
    await store.updateOutbox(outboxId, state: OutboxState.scheduled, sendAt: DateTime.now());
    _runtimes[entry.message.accountId]?.kickOutbox();
  }

  Future<String> saveDraft(OutgoingMessage message) => _requireRuntime(message.accountId).provider.saveDraft(message);

  Future<void> deleteDraft(String accountId, String draftId) =>
      _requireRuntime(accountId).provider.deleteDraft(draftId);

  // Content ------------------------------------------------------------------

  /// Makes sure message bodies are cached locally, downloading if needed.
  Future<void> ensureBodies(String accountId, List<String> messageIds) =>
      _requireRuntime(accountId).ensureBodies(messageIds);

  Future<Uint8List> attachment(String accountId, String messageId, AttachmentInfo info) =>
      _requireRuntime(accountId).provider.fetchAttachment(messageId, info);

  /// Loads older threads for the list currently shown. Returns whether any
  /// account may have more.
  Future<bool> loadMore(ThreadFilter filter) async {
    final targets = <(AccountRuntime, String?)>[];
    switch (filter) {
      case MailboxFilter(:final accountId, :final mailboxId):
        final r = _runtimes[accountId];
        if (r != null) targets.add((r, mailboxId));
      case RoleFilter(:final role, :final accountIds):
        for (final r in _runtimesFor(accountIds)) {
          final mailbox = (await store.mailboxes(r.id)).where((m) => m.role == role).firstOrNull;
          if (mailbox != null) targets.add((r, mailbox.id));
        }
      case AllMailFilter(:final accountIds):
        for (final r in _runtimesFor(accountIds)) {
          targets.add((r, null));
        }
      case FlaggedFilter() || ThreadSetFilter():
        return false;
    }
    final results = await Future.wait(targets.map((t) async {
      try {
        return (await t.$1.provider.loadMore(store, mailboxId: t.$2)).hasMore;
      } on MailException catch (e) {
        _log.info('Load more failed for ${t.$1.account.email}: $e');
        return false;
      }
    }));
    return results.any((more) => more);
  }

  /// Runs a server-side search in each account. Returns thread keys
  /// (`accountId/threadId`); the threads are in the store when this returns.
  Future<List<String>> searchServer(String query, {Set<String>? accountIds}) async {
    final perAccount = await Future.wait(_runtimesFor(accountIds).map((r) async {
      try {
        final page = await r.provider.search(store, query);
        return [for (final t in page.threadIds) '${r.id}/$t'];
      } on MailException catch (e) {
        _log.info('Search failed for ${r.account.email}: $e');
        return const <String>[];
      }
    }));
    return [for (final list in perAccount) ...list];
  }

  ProviderCapabilities? capabilitiesOf(String accountId) => _runtimes[accountId]?.provider.capabilities;

  Iterable<AccountRuntime> _runtimesFor(Set<String>? accountIds) =>
      accountIds == null ? _runtimes.values : accountIds.map((id) => _runtimes[id]).nonNulls;

  AccountRuntime _requireRuntime(String accountId) {
    final runtime = _runtimes[accountId];
    if (runtime == null) throw const AuthException('Account is not connected');
    return runtime;
  }

  /// The mailbox with [role] in [accountId], if the provider has one.
  Future<Mailbox?> mailboxWithRole(String accountId, MailboxRole role) async =>
      (await store.mailboxes(accountId)).where((m) => m.role == role).firstOrNull;

  Future<void> dispose() async {
    _disposed = true;
    await _accountsSub?.cancel();
    await Future.wait(_runtimes.values.map((r) => r.dispose()));
    _runtimes.clear();
    // Not awaited: a broadcast controller's close completes only after every
    // listener saw `done`, which can stall shutdown on a listener's zone.
    unawaited(_statusController.close());
    unawaited(_newMail.close());
    unawaited(_outboxEvents.close());
  }
}
