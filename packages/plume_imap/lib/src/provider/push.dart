import 'dart:async';

import 'package:plume_core/plume_core.dart';

import '../imap/imap_client.dart';
import 'context.dart';
import 'errors.dart';

/// Real-time change signals from a dedicated connection: IDLE on INBOX
/// (re-issued every [ImapClientConfig.idleRestart]), or NOOP polling every
/// [ImapSyncConfig.pollInterval] when the server lacks IDLE. Emits
/// (debounced) when the server reports new, expunged or changed messages.
///
/// The stream ends with a [MailException] when the connection fails; the
/// engine then subscribes again with backoff. Cancelling logs out.
final class ImapPush {
  ImapPush(this.ctx);

  final ImapContext ctx;
  int _subscriptions = 0;
  final _active = <_Watcher>{};

  Stream<void> watch() {
    late final StreamController<void> controller;
    _Watcher? watcher;
    controller = StreamController<void>(
      onListen: () {
        final reconnect = _subscriptions++ > 0;
        final w = watcher = _Watcher(ctx, controller, ringOnConnect: reconnect);
        _active.add(w);
        unawaited(w.run().whenComplete(() => _active.remove(w)));
      },
      onCancel: () => watcher?.stop(),
    );
    return controller.stream;
  }

  /// Stops every watcher (their connections log out).
  void close() {
    for (final w in [..._active]) {
      w.stop();
    }
  }
}

final class _Watcher {
  _Watcher(this.ctx, this.controller, {required this.ringOnConnect});

  final ImapContext ctx;
  final StreamController<void> controller;

  /// After a reconnect, changes may have been missed while disconnected.
  final bool ringOnConnect;
  final _stop = Completer<void>();
  ImapClient? _client;
  Timer? _debounce;
  bool get _stopped => _stop.isCompleted;

  /// Ends IDLE (DONE) and lets [run] log out; does not wait for it.
  void stop() {
    if (!_stop.isCompleted) _stop.complete();
    _debounce?.cancel();
  }

  void _ring() {
    if (_stopped || controller.isClosed) return;
    _debounce ??= Timer(ctx.config.pushDebounce, () {
      _debounce = null;
      if (!_stopped && !controller.isClosed) controller.add(null);
    });
  }

  Future<void> run() async {
    StreamSubscription<ImapEvent>? events;
    try {
      final client = _client = await ctx.pool.openAuthenticated();
      if (_stopped) return;
      // EXAMINE: watching never changes the mailbox.
      await client.select('INBOX', readOnly: true);
      events = client.events.listen((e) {
        if (e is ImapExistsEvent || e is ImapExpungeEvent || e is ImapVanishedEvent || e is ImapFlagsEvent) _ring();
      });
      if (ringOnConnect) _ring();
      while (!_stopped && !client.isClosed) {
        if (client.supports('IDLE')) {
          await client.idle(stop: _stop.future);
        } else {
          final tick = Completer<void>();
          final timer = Timer(ctx.config.pollInterval, tick.complete);
          await Future.any([_stop.future, tick.future]);
          timer.cancel();
          if (!_stopped) await client.noop();
        }
      }
    } on Object catch (e) {
      if (!_stopped && !controller.isClosed) controller.addError(toMailException(e));
    } finally {
      await events?.cancel();
      _debounce?.cancel();
      final c = _client;
      _client = null;
      if (c != null) await c.logout();
      if (!controller.isClosed) unawaited(controller.close());
    }
  }
}
