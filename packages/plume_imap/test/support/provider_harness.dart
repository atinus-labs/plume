import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_store/plume_store.dart' show DriftMailStore;

import 'fake_imap_server.dart';

/// Records what would have been sent over SMTP.
final class FakeSender implements MailSender {
  final sent = <({String from, List<String> recipients, Uint8List data, String username, String password})>[];

  /// Thrown by the next send, if set.
  MailException? failWith;

  @override
  Future<void> send({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
    required String from,
    required List<String> recipients,
    required Uint8List data,
  }) async {
    final f = failWith;
    if (f != null) throw f;
    sent.add((from: from, recipients: recipients, data: data, username: username, password: password));
  }
}

/// Hands out a fixed password.
final class PasswordTokens implements TokenSource {
  PasswordTokens(this.password);

  String password;
  int invalidations = 0;

  @override
  Future<String> accessToken() async => password;

  @override
  void invalidate() => invalidations++;
}

/// A fake server, a real in-memory store and a provider wired together.
final class Harness {
  Harness._(this.server, this.store, this.provider, this.sender, this.account, this.tokens);

  static Future<Harness> start({
    bool gmail = false,
    Set<String>? capabilities,
    ImapSyncConfig config = const ImapSyncConfig(),
    void Function(FakeImapServer server)? seed,
    String email = 'ana@example.org',
  }) async {
    final server = await FakeImapServer.start(gmail: gmail, capabilities: capabilities, username: email);
    seed?.call(server);
    final account = Account(
      id: 'acc',
      provider: 'imap',
      email: email,
      displayName: 'Ana',
      color: 0xFF336699,
      providerConfig: MailServerSettings(
        imap: server.endpoint,
        smtp: const ServerEndpoint(host: '127.0.0.1', port: 2525, security: ConnectionSecurity.none),
        username: email,
        saveSentCopy: true,
      ).toJson(),
    );
    final store = DriftMailStore.inMemory();
    await store.saveAccount(account);
    final sender = FakeSender();
    final tokens = PasswordTokens('secret');
    final provider = ImapProvider(account: account, tokens: tokens, sender: sender, config: config);
    return Harness._(server, store, provider, sender, account, tokens);
  }

  final FakeImapServer server;
  final DriftMailStore store;
  final ImapProvider provider;
  final FakeSender sender;
  final Account account;
  final PasswordTokens tokens;

  String get accountId => account.id;

  Future<SyncResult> sync() => provider.sync(store);

  /// Applies [op] like the engine: local effect first, then the server.
  /// Like `MailEngine.perform`: the optimistic local effect, then the
  /// server round trip.
  Future<void> perform(MailOperation op) async {
    await optimistic(op);
    await provider.execute(store, op);
  }

  /// Just the optimistic local effect, with ids translated as the engine
  /// does.
  Future<void> optimistic(MailOperation op) async {
    final mutation = provider.localEffect(op, await store.mailboxes(accountId));
    final ids = op.scope == OperationScope.message ? provider.currentMessageIds(op.ids) : op.ids;
    if (!mutation.isNoop) await store.applyLocalMutation(accountId, op.scope, ids, mutation);
  }

  ActionOperation action(MailAction action, List<String> ids, {OperationScope scope = OperationScope.thread}) =>
      ActionOperation(accountId: accountId, scope: scope, ids: ids, action: action);

  /// Every stored message, by id.
  Future<Map<String, Message>> messages() async {
    final threads = <String>{};
    for (final filter in [
      AllMailFilter(accountIds: {accountId}),
      RoleFilter(MailboxRole.trash, accountIds: {accountId}),
      RoleFilter(MailboxRole.junk, accountIds: {accountId}),
    ]) {
      threads.addAll((await store.watchThreads(filter, limit: 100000).first).map((t) => t.id));
    }
    return {for (final m in await store.messagesInThreads(accountId, threads)) m.id: m};
  }

  /// The stored message whose subject is [subject].
  Future<Message> bySubject(String subject) async =>
      (await messages()).values.singleWhere((m) => m.subject == subject, orElse: () => throw StateError('No "$subject"'));

  Future<List<Message>> inMailbox(String mailboxId) async =>
      [for (final m in (await messages()).values) if (m.mailboxIds.contains(mailboxId)) m];

  Future<void> dispose() async {
    await provider.dispose();
    await store.close();
    await server.close();
  }
}

/// A plain-text RFC 5322 message.
String rawMessage({
  required String id,
  String from = 'Ben Okafor <ben@example.com>',
  String to = 'Ana <ana@example.org>',
  String? cc,
  String? bcc,
  String subject = 'Hello',
  String body = 'Hi there',
  String? inReplyTo,
  List<String> references = const [],
  String date = 'Mon, 02 Mar 2026 10:00:00 +0000',
  String? listUnsubscribe,
}) {
  final h = StringBuffer()
    ..write('From: $from\r\n')
    ..write('To: $to\r\n');
  if (cc != null) h.write('Cc: $cc\r\n');
  if (bcc != null) h.write('Bcc: $bcc\r\n');
  h
    ..write('Subject: $subject\r\n')
    ..write('Date: $date\r\n')
    ..write('Message-ID: <$id>\r\n');
  if (inReplyTo != null) h.write('In-Reply-To: <$inReplyTo>\r\n');
  if (references.isNotEmpty) h.write('References: ${references.map((r) => '<$r>').join('\r\n ')}\r\n');
  if (listUnsubscribe != null) h.write('List-Unsubscribe: $listUnsubscribe\r\n');
  h
    ..write('MIME-Version: 1.0\r\n')
    ..write('Content-Type: text/plain; charset=utf-8\r\n')
    ..write('\r\n')
    ..write(body);
  return h.toString();
}

/// A message with an HTML body, an inline logo and a PDF attachment
/// (base64), so its BODYSTRUCTURE has several parts.
String richMessage({required String id, String subject = 'Report', int pdfBytes = 3000, String date = 'Tue, 03 Mar 2026 10:00:00 +0000'}) {
  final pdf = List<int>.generate(pdfBytes, (i) => (i * 7) & 0xFF);
  String b64(List<int> bytes) {
    final s = base64.encode(bytes);
    return [for (var i = 0; i < s.length; i += 76) s.substring(i, i + 76 > s.length ? s.length : i + 76)].join('\r\n');
  }

  return 'From: Carla <carla@example.net>\r\n'
      'To: ana@example.org\r\n'
      'Subject: $subject\r\n'
      'Date: $date\r\n'
      'Message-ID: <$id>\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: multipart/mixed; boundary="mix"\r\n'
      '\r\n'
      '--mix\r\n'
      'Content-Type: multipart/related; boundary="rel"\r\n'
      '\r\n'
      '--rel\r\n'
      'Content-Type: text/html; charset=utf-8\r\n'
      'Content-Transfer-Encoding: quoted-printable\r\n'
      '\r\n'
      '<html><head><style>p{color:red}</style></head><body><p>Quarterly numbers =E2=80=94 see attached.</p>'
      '<img src=3D"cid:logo@x"></body></html>\r\n'
      '--rel\r\n'
      'Content-Type: image/png; name="logo.png"\r\n'
      'Content-ID: <logo@x>\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      '${b64([137, 80, 78, 71, 1, 2, 3])}\r\n'
      '--rel--\r\n'
      '--mix\r\n'
      'Content-Type: application/pdf; name="q3.pdf"\r\n'
      'Content-Disposition: attachment; filename="q3.pdf"\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      '${b64(pdf)}\r\n'
      '--mix--\r\n';
}

/// Waits until [condition] holds or [timeout] passes.
Future<void> eventually(FutureOr<bool> Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) throw TimeoutException('Condition not met', timeout);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
