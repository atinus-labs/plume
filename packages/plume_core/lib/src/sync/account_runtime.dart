import 'dart:async';

import 'package:logging/logging.dart';

import '../models/account.dart';
import '../models/mailbox.dart';
import '../ops/mail_operation.dart';
import '../provider/errors.dart';
import '../provider/mail_provider.dart';
import '../store/mail_store.dart';
import 'account_status.dart';
import 'backoff.dart';

final _log = Logger('plume.engine');

/// Drives one account: sync passes, the real-time change stream, the
/// operation queue and the outbox. Created and owned by `MailEngine`.
final class AccountRuntime {
  AccountRuntime({
    required this.account,
    required this.provider,
    required this.store,
    required this.onStatus,
    required this.onNewMail,
    required this.onOutbox,
    required this.onNeedsReauth,
    required this._syncInterval,
  });

  final Account account;
  final MailProvider provider;
  final MailStore store;
  final void Function(AccountSyncStatus) onStatus;
  final void Function(NewMailEvent) onNewMail;
  final void Function(OutboxEvent) onOutbox;
  final void Function() onNeedsReauth;

  String get id => account.id;

  late AccountSyncStatus _status = AccountSyncStatus(accountId: account.id);
  AccountSyncStatus get status => _status;

  Duration _syncInterval;
  Timer? _periodic;
  Timer? _retryTimer;
  Timer? _opsTimer;
  Timer? _outboxTimer;
  StreamSubscription<void>? _push;
  Timer? _pushRetry;
  final _syncBackoff = Backoff();
  final _pushBackoff = Backoff(initial: const Duration(seconds: 5), max: const Duration(minutes: 10));

  Future<void>? _currentSync;
  bool _syncAgain = false;
  bool _opsRunning = false;
  bool _opsAgain = false;
  bool _outboxRunning = false;
  bool _outboxAgain = false;
  bool _disposed = false;
  bool _paused = false;

  final _bodyFetches = <String, Future<void>>{};

  void start() {
    _setStatus(_status.copyWith(initialSyncDone: false));
    unawaited(_markInitialState());
    unawaited(requestSync());
    _connectPush();
    _schedulePeriodic();
    kickOperations();
    kickOutbox();
  }

  Future<void> _markInitialState() async {
    // Accounts that synced before start with their data already in place.
    final done = await store.readState(id, _initialDoneKey) == '1';
    if (done && !_disposed) _setStatus(_status.copyWith(initialSyncDone: true));
  }

  set syncInterval(Duration value) {
    if (value == _syncInterval) return;
    _syncInterval = value;
    _schedulePeriodic();
  }

  void _schedulePeriodic() {
    _periodic?.cancel();
    if (_disposed || _paused) return;
    _periodic = Timer.periodic(_syncInterval, (_) => unawaited(requestSync()));
  }

  // Sync ---------------------------------------------------------------------

  /// Requests a sync pass. Concurrent requests coalesce: if a pass is
  /// running, exactly one more pass follows it.
  Future<void> requestSync() {
    if (_disposed || _paused) return Future.value();
    if (_currentSync != null) {
      _syncAgain = true;
      return _currentSync!;
    }
    final future = _runSyncLoop().whenComplete(() => _currentSync = null);
    _currentSync = future;
    return future;
  }

  Future<void> _runSyncLoop() async {
    do {
      _syncAgain = false;
      await _syncOnce();
    } while (_syncAgain && !_disposed && !_paused);
  }

  Future<void> _syncOnce() async {
    _retryTimer?.cancel();
    _setStatus(_status.copyWith(phase: SyncPhase.syncing));
    try {
      final result = await provider.sync(store);
      if (_disposed) return;
      await _reapplyPending();
      _syncBackoff.reset();
      if (!_status.initialSyncDone) await store.writeState(id, _initialDoneKey, '1');
      _setStatus(_status.copyWith(
        phase: SyncPhase.idle,
        lastSynced: DateTime.now(),
        clearError: true,
        initialSyncDone: true,
      ));
      if (result.newMessages.isNotEmpty) onNewMail(NewMailEvent(id, result.newMessages));
      unawaited(_prefetchBodies());
      // Server state may have changed under queued operations; let them run.
      kickOperations();
    } on AuthException catch (e) {
      _enterNeedsReauth(e);
    } on MailException catch (e) {
      _log.warning('Sync failed for ${account.email}: $e');
      _setStatus(_status.copyWith(phase: SyncPhase.offline, lastError: e.message));
      _scheduleSyncRetry(e is TransientException ? e.retryAfter : null);
    } catch (e, st) {
      _log.severe('Unexpected sync error for ${account.email}', e, st);
      _setStatus(_status.copyWith(phase: SyncPhase.offline, lastError: '$e'));
      _scheduleSyncRetry(null);
    }
  }

  void _scheduleSyncRetry(Duration? hint) {
    if (_disposed || _paused) return;
    final delay = hint ?? _syncBackoff.next();
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(requestSync()));
  }

  /// Providers write server state, which does not yet include queued
  /// operations. Re-applying their local effect keeps the user's actions
  /// (an archive that is still in flight) from flickering back.
  Future<void> _reapplyPending() async {
    final pending = await store.pendingOperations(accountId: id);
    if (pending.isEmpty) return;
    final mailboxes = await store.mailboxes(id);
    await store.transaction(() async {
      for (final op in pending) {
        final mutation = provider.localEffect(op.operation, mailboxes);
        if (!mutation.isNoop) {
          final ids = op.operation.scope == OperationScope.message
              ? provider.currentMessageIds(op.operation.ids)
              : op.operation.ids;
          await store.applyLocalMutation(id, op.operation.scope, ids, mutation);
        }
      }
    });
  }

  /// Downloads bodies of the newest inbox messages so that opening them is
  /// instant. Best effort; failures are ignored.
  Future<void> _prefetchBodies() async {
    try {
      final mailboxes = await store.mailboxes(id);
      final inbox = mailboxes.where((m) => m.role == MailboxRole.inbox).firstOrNull;
      if (inbox == null) return;
      final missing = await store.recentMessagesWithoutBody(id, inbox.id, limit: 40);
      for (var i = 0; i < missing.length && !_disposed; i += 20) {
        final end = i + 20 > missing.length ? missing.length : i + 20;
        await provider.fetchBodies(store, missing.sublist(i, end));
      }
      await _reapplyPending();
    } on MailException catch (e) {
      _log.fine('Body prefetch skipped: $e');
    }
  }

  /// Ensures the bodies of [messageIds] are cached. Concurrent calls for the
  /// same message share one request.
  Future<void> ensureBodies(List<String> messageIds) async {
    final missing = await store.messagesWithoutBody(id, messageIds);
    if (missing.isEmpty) return;
    final waits = <Future<void>>[];
    final toFetch = <String>[];
    for (final m in missing) {
      final pending = _bodyFetches[m];
      if (pending != null) {
        waits.add(pending);
      } else {
        toFetch.add(m);
      }
    }
    if (toFetch.isNotEmpty) {
      final fetch = provider.fetchBodies(store, toFetch);
      for (final m in toFetch) {
        _bodyFetches[m] = fetch;
      }
      waits.add(fetch.whenComplete(() {
        for (final m in toFetch) {
          _bodyFetches.remove(m);
        }
      }));
    }
    try {
      await Future.wait(waits);
      if (toFetch.isNotEmpty) await _reapplyPending();
    } on AuthException catch (e) {
      _enterNeedsReauth(e);
      rethrow;
    }
  }

  // Push ---------------------------------------------------------------------

  void _connectPush() {
    if (_disposed || _paused || !provider.capabilities.push) return;
    _push?.cancel();
    _push = provider.watchChanges().listen(
      (_) {
        _pushBackoff.reset();
        if (!_status.pushConnected) _setStatus(_status.copyWith(pushConnected: true));
        unawaited(requestSync());
      },
      onError: (Object e) {
        _setStatus(_status.copyWith(pushConnected: false));
        if (e is AuthException) {
          _enterNeedsReauth(e);
          return;
        }
        _log.fine('Push stream error for ${account.email}: $e');
        _schedulePushReconnect();
      },
      onDone: () {
        _setStatus(_status.copyWith(pushConnected: false));
        _schedulePushReconnect();
      },
      cancelOnError: true,
    );
    _setStatus(_status.copyWith(pushConnected: true));
  }

  void _schedulePushReconnect() {
    if (_disposed || _paused) return;
    _pushRetry?.cancel();
    _pushRetry = Timer(_pushBackoff.next(), _connectPush);
  }

  /// Called after the system resumes or the network returns: reconnect push
  /// right away and sync.
  void wake() {
    if (_disposed || _paused) return;
    _pushBackoff.reset();
    _syncBackoff.reset();
    _pushRetry?.cancel();
    _connectPush();
    unawaited(requestSync());
    kickOperations();
    kickOutbox();
  }

  // Operations ---------------------------------------------------------------

  /// Replays queued operations against the server, in order.
  void kickOperations() {
    if (_disposed || _paused) return;
    if (_opsRunning) {
      _opsAgain = true;
      return;
    }
    unawaited(_drainOperations());
  }

  Future<void> _drainOperations() async {
    _opsRunning = true;
    _opsTimer?.cancel();
    var repairNeeded = false;
    try {
      do {
        _opsAgain = false;
        final pending = await store.pendingOperations(accountId: id);
        for (final op in pending) {
          if (_disposed || _paused) return;
          final notBefore = op.notBefore;
          if (notBefore != null && notBefore.isAfter(DateTime.now())) {
            _opsTimer = Timer(notBefore.difference(DateTime.now()), kickOperations);
            break;
          }
          try {
            await provider.execute(store, op.operation);
            await store.completeOperation(op.id);
          } on AuthException catch (e) {
            _enterNeedsReauth(e);
            return;
          } on TransientException catch (e) {
            final delay = e.retryAfter ?? Backoff.forAttempt(op.attempts);
            await store.deferOperation(op.id, error: e.message, notBefore: DateTime.now().add(delay));
            _opsTimer = Timer(delay, kickOperations);
            break;
          } on MailException catch (e) {
            // The server refused the change for good (or the target is
            // gone). Drop it and let a sync restore the true state.
            _log.warning('Dropping operation ${op.operation.toJson()}: $e');
            await store.completeOperation(op.id);
            repairNeeded = true;
          }
        }
      } while (_opsAgain && !_disposed && !_paused);
    } finally {
      _opsRunning = false;
    }
    if (repairNeeded) unawaited(requestSync());
  }

  // Outbox -------------------------------------------------------------------

  void kickOutbox() {
    if (_disposed || _paused) return;
    if (_outboxRunning) {
      _outboxAgain = true;
      return;
    }
    unawaited(_drainOutbox());
  }

  Future<void> _drainOutbox() async {
    _outboxRunning = true;
    _outboxTimer?.cancel();
    try {
      do {
        _outboxAgain = false;
        final entries = (await store.outbox()).where((e) => e.message.accountId == id).toList()
          ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
        DateTime? nextWake;
        for (final entry in entries) {
          if (_disposed || _paused) return;
          if (entry.state == OutboxState.failed) continue;
          if (entry.sendAt.isAfter(DateTime.now())) {
            nextWake = nextWake == null || entry.sendAt.isBefore(nextWake) ? entry.sendAt : nextWake;
            continue;
          }
          await _sendEntry(entry);
        }
        if (nextWake != null) {
          _outboxTimer = Timer(nextWake.difference(DateTime.now()), kickOutbox);
        }
      } while (_outboxAgain && !_disposed && !_paused);
    } finally {
      _outboxRunning = false;
    }
  }

  Future<void> _sendEntry(OutboxEntry entry) async {
    await store.updateOutbox(entry.id, state: OutboxState.sending);
    // Undo may have removed it between listing and marking.
    final still = (await store.outbox()).where((e) => e.id == entry.id).firstOrNull;
    if (still == null) return;
    try {
      await provider.send(entry.message);
      await store.deleteOutgoing(entry.id);
      onOutbox(OutboxSent(entry.id, id));
      unawaited(requestSync());
    } on AuthException catch (e) {
      await store.updateOutbox(entry.id, state: OutboxState.retrying, error: e.message);
      _enterNeedsReauth(e);
    } on TransientException catch (e) {
      final delay = e.retryAfter ?? Backoff.forAttempt(entry.attempts, initial: const Duration(seconds: 10));
      await store.updateOutbox(entry.id,
          state: OutboxState.retrying, error: e.message, sendAt: DateTime.now().add(delay));
      onOutbox(OutboxFailed(entry.id, id, e.message, willRetry: true));
    } on MailException catch (e) {
      await store.updateOutbox(entry.id, state: OutboxState.failed, error: e.message);
      onOutbox(OutboxFailed(entry.id, id, e.message, willRetry: false));
    }
  }

  // Lifecycle ----------------------------------------------------------------

  void _enterNeedsReauth(AuthException e) {
    if (_paused) return;
    _log.warning('Account ${account.email} needs to sign in again: ${e.message}');
    _paused = true;
    _cancelTimers();
    _push?.cancel();
    _push = null;
    _setStatus(_status.copyWith(phase: SyncPhase.needsReauth, lastError: e.message, pushConnected: false));
    onNeedsReauth();
  }

  void _setStatus(AccountSyncStatus status) {
    _status = status;
    if (!_disposed) onStatus(status);
  }

  void _cancelTimers() {
    _periodic?.cancel();
    _retryTimer?.cancel();
    _opsTimer?.cancel();
    _outboxTimer?.cancel();
    _pushRetry?.cancel();
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelTimers();
    await _push?.cancel();
    await provider.dispose();
  }

  static const _initialDoneKey = 'engine.initialSyncDone';
}
