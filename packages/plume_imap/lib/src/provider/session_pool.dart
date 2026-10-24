import 'dart:async';

import 'package:logging/logging.dart';

import '../imap/imap_client.dart';
import '../imap/imap_exception.dart';
import '../settings.dart';
import 'errors.dart';

final Logger _log = Logger('plume.imap');

/// Which pooled connection to use. Sync and operations share one so that
/// folder state stays consistent; message bodies and attachments use
/// another, so opening a message never waits behind a long sync. Push
/// (IDLE) opens a third, dedicated connection.
enum ImapSlot { primary, fetch }

/// What the server told us at login.
final class ServerProfile {
  const ServerProfile({required this.capabilities, required this.isGmail, this.namespacePrefix = '', this.delimiter});

  final Set<String> capabilities;
  final bool isGmail;

  /// Personal namespace prefix (`INBOX.` on Courier-style servers).
  final String namespacePrefix;
  final String? delimiter;

  bool supports(String capability) => capabilities.contains(capability.toUpperCase());
}

/// Opens a connected, authenticated client. Injectable for tests.
typedef ImapOpener = Future<ImapClient> Function(ServerEndpoint endpoint, ImapClientConfig config);

final class _Slot {
  final lock = Mutex();
  ImapClient? client;
  DateTime lastUsed = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? idleTimer;
}

/// Up to two pooled connections per account (see [ImapSlot]), each used by
/// one caller at a time. Connections are opened on demand, verified with
/// NOOP after sitting idle, reopened after failures and closed after
/// [idleTimeout] without use.
final class ImapSessionPool {
  ImapSessionPool({
    required this.endpoint,
    required this.username,
    required this.password,
    this.config = const ImapClientConfig(),
    this.idleTimeout = const Duration(minutes: 5),
    ImapOpener? opener,
  }) : _opener = opener ?? ((e, c) => ImapClient.connect(e, config: c));

  final ServerEndpoint endpoint;
  final String username;

  /// Supplies the password (the account's TokenSource).
  final Future<String> Function() password;
  final ImapClientConfig config;
  final Duration idleTimeout;
  final ImapOpener _opener;
  final _slots = {for (final s in ImapSlot.values) s: _Slot()};
  bool _closed = false;
  ServerProfile? _profile;

  /// Known after the first successful login.
  ServerProfile? get profile => _profile;

  /// Runs [action] with the slot's client, connecting and logging in first
  /// if needed. Calls on the same slot are serialized. A client whose
  /// connection broke is discarded so the next call reconnects. Errors are
  /// passed through unchanged.
  Future<T> run<T>(ImapSlot slot, Future<T> Function(ImapClient client) action) {
    final s = _slots[slot]!;
    return s.lock.run(() async {
      if (_closed) throw const ImapConnectionException('The account is being closed');
      s.idleTimer?.cancel();
      final client = await _ensure(s, slot);
      try {
        return await action(client);
      } finally {
        if (client.isClosed && identical(s.client, client)) s.client = null;
        s.lastUsed = DateTime.now();
        _scheduleIdleClose(s);
      }
    });
  }

  Future<ImapClient> _ensure(_Slot s, ImapSlot slot) async {
    final existing = s.client;
    if (existing != null && !existing.isClosed) {
      // A connection that sat idle may have been dropped by the server or
      // a NAT box without us noticing; a NOOP finds out cheaply.
      if (DateTime.now().difference(s.lastUsed) < const Duration(seconds: 45)) return existing;
      try {
        await existing.noop();
        return existing;
      } on ImapException catch (e) {
        _log.fine('Pooled ${slot.name} connection is stale ($e); reconnecting');
        existing.destroy();
      }
    }
    s.client = null;
    final client = await openAuthenticated();
    s.client = client;
    return client;
  }

  /// A new connected and logged-in client with the extensions Plume uses
  /// enabled. The caller owns it (used for IDLE).
  Future<ImapClient> openAuthenticated() async {
    final secret = await password();
    final client = await _opener(endpoint, config);
    try {
      await client.login(username, secret);
      await client.enable([if (client.supports('QRESYNC')) 'QRESYNC' else 'CONDSTORE', 'UTF8=ACCEPT']);
      if (_profile == null) {
        final ns = await client.personalNamespace();
        _profile = ServerProfile(
          capabilities: client.capabilities,
          isGmail: client.isGmail,
          namespacePrefix: ns?.prefix ?? '',
          delimiter: ns?.delimiter,
        );
      }
      return client;
    } catch (_) {
      client.destroy();
      rethrow;
    }
  }

  void _scheduleIdleClose(_Slot s) {
    s.idleTimer?.cancel();
    if (_closed) return;
    s.idleTimer = Timer(idleTimeout, () {
      final client = s.client;
      if (client == null) return;
      // Through the lock, so a call that just started is not cut off.
      unawaited(s.lock.run(() async {
        if (!identical(s.client, client) || DateTime.now().difference(s.lastUsed) < idleTimeout) return;
        s.client = null;
        await client.logout();
      }));
    });
  }

  /// Logs out and closes every pooled connection.
  Future<void> close() async {
    _closed = true;
    await Future.wait([
      for (final s in _slots.values)
        () async {
          s.idleTimer?.cancel();
          final client = s.client;
          s.client = null;
          if (client != null) await client.logout();
        }(),
    ]);
  }
}
