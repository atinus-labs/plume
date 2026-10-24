@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/imap/imap_client.dart';
import 'package:plume_imap/src/imap/uid_set.dart';
import 'package:plume_imap/src/provider/ids.dart';
import 'package:plume_store/plume_store.dart' show DriftMailStore;
import 'package:test/test.dart';

import '../support/provider_harness.dart';

// Run through tool/integration.sh, which starts Dovecot in a container and
// passes its ports and certificate in these variables.
final _env = Platform.environment;
final int _port = int.parse(_env['PLUME_DOVECOT_PORT'] ?? '0');
final int _tlsPort = int.parse(_env['PLUME_DOVECOT_TLS_PORT'] ?? '0');
final String _ca = _env['PLUME_DOVECOT_CA'] ?? '';
final String _password = _env['PLUME_DOVECOT_PASSWORD'] ?? 'secret';
final String _seedUser = _env['PLUME_DOVECOT_SEED_USER'] ?? 'plume@example.org';

SecurityContext _trust() => SecurityContext(withTrustedRoots: false)..setTrustedCertificates(_ca);

ServerEndpoint get _tls => ServerEndpoint(host: '127.0.0.1', port: _tlsPort, security: ConnectionSecurity.tls);
ServerEndpoint get _startTls => ServerEndpoint(host: '127.0.0.1', port: _port, security: ConnectionSecurity.startTls);

/// A fresh mailbox per test: the static passdb accepts any user name.
String _newUser() => 'u${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}@example.org';

final class _Dovecot {
  _Dovecot._(this.user, this.store, this.provider, this.sender, this.account);

  static Future<_Dovecot> open({String? user, ServerEndpoint? endpoint}) async {
    final name = user ?? _newUser();
    final account = Account(
      id: 'dovecot',
      provider: 'imap',
      email: name,
      displayName: 'Plume',
      color: 0xFF336699,
      providerConfig: MailServerSettings(
        imap: endpoint ?? _startTls,
        smtp: const ServerEndpoint(host: '127.0.0.1', port: 1, security: ConnectionSecurity.none),
        username: name,
      ).toJson(),
    );
    final store = DriftMailStore.inMemory();
    await store.saveAccount(account);
    final sender = FakeSender();
    final provider = ImapProvider(
      account: account,
      tokens: PasswordTokens(_password),
      sender: sender,
      config: ImapSyncConfig(client: ImapClientConfig(securityContext: _trust())),
    );
    return _Dovecot._(name, store, provider, sender, account);
  }

  final String user;
  final DriftMailStore store;
  final ImapProvider provider;
  final FakeSender sender;
  final Account account;

  /// A second client, as another device of the same user would be.
  Future<ImapClient> other() async {
    final c = await ImapClient.connect(_tls, config: ImapClientConfig(securityContext: _trust()));
    await c.login(user, _password);
    return c;
  }

  Future<void> append(String mailbox, String raw, {List<String> flags = const []}) async {
    final c = await other();
    await c.append(mailbox, Uint8List.fromList(utf8.encode(raw)), flags: flags);
    await c.logout();
  }

  Future<Map<String, Message>> messages() async {
    final threads = <String>{};
    for (final filter in [
      AllMailFilter(accountIds: {account.id}),
      RoleFilter(MailboxRole.trash, accountIds: {account.id}),
      RoleFilter(MailboxRole.junk, accountIds: {account.id}),
    ]) {
      threads.addAll((await store.watchThreads(filter, limit: 100000).first).map((t) => t.id));
    }
    return {for (final m in await store.messagesInThreads(account.id, threads)) m.id: m};
  }

  Future<void> perform(MailOperation op) async {
    final mutation = provider.localEffect(op, await store.mailboxes(account.id));
    if (!mutation.isNoop) await store.applyLocalMutation(account.id, op.scope, op.ids, mutation);
    await provider.execute(store, op);
  }

  ActionOperation action(MailAction a, List<String> ids, {OperationScope scope = OperationScope.thread}) =>
      ActionOperation(accountId: account.id, scope: scope, ids: ids, action: a);

  Future<void> close() async {
    await provider.dispose();
    await store.close();
  }
}

void main() {
  setUpAll(() {
    if (_port == 0 || _ca.isEmpty) fail('Run through tool/integration.sh (PLUME_DOVECOT_* not set)');
  });

  group('login check', () {
    test('TLS and STARTTLS with a trusted certificate', () async {
      for (final endpoint in [_tls, _startTls]) {
        final info = await checkImapLogin(endpoint, _newUser(), _password, securityContext: _trust());
        expect(info.isGmail, isFalse);
        expect(info.capabilities, containsAll(['IDLE', 'UIDPLUS', 'MOVE', 'CONDSTORE', 'SPECIAL-USE']));
      }
    });

    test('wrong password, untrusted certificate, TLS on the STARTTLS port, plaintext', () async {
      Future<ConnectionFailure> failure(Future<Object?> f) async {
        final e = await f.then<Object?>((_) => null, onError: (Object e) => e);
        expect(e, isA<ConnectionCheckException>());
        return (e! as ConnectionCheckException).failure;
      }

      expect(await failure(checkImapLogin(_tls, _newUser(), 'wrong', securityContext: _trust())), ConnectionFailure.authFailed);
      expect(await failure(checkImapLogin(_tls, _newUser(), _password)), ConnectionFailure.certificate);
      expect(
        await failure(checkImapLogin(
          ServerEndpoint(host: '127.0.0.1', port: _port, security: ConnectionSecurity.tls),
          _newUser(),
          _password,
          securityContext: _trust(),
          timeout: const Duration(seconds: 3),
        )),
        anyOf(ConnectionFailure.tls, ConnectionFailure.timeout),
      );
      // Plaintext is refused before connecting unless the host is local.
      expect(
        await failure(checkImapLogin(
            ServerEndpoint(host: 'mail.example.com', port: _port, security: ConnectionSecurity.none), _newUser(), _password)),
        ConnectionFailure.tls,
      );
    });
  });

  test('the seeded mailbox syncs completely', () async {
    final d = await _Dovecot.open(user: _seedUser, endpoint: _tls);
    addTearDown(d.close);
    final result = await d.provider.sync(d.store);
    expect(result.fullResync, isTrue);
    final all = await d.messages();
    expect(all.values.where((m) => m.mailboxIds.contains('INBOX')), hasLength(12));
    final reply = all.values.singleWhere((m) => m.subject == 'Re: Seeded message 1');
    final root = all.values.singleWhere((m) => m.subject == 'Seeded message 1');
    expect(reply.threadId, root.threadId);
    expect(root.snippet, 'This is seeded message number 1. Grüße!');
    final roles = {for (final m in await d.store.mailboxes(d.account.id)) m.role};
    expect(roles, containsAll([MailboxRole.inbox, MailboxRole.sent, MailboxRole.drafts, MailboxRole.trash, MailboxRole.junk]));
  });

  test('sync, changes from another client, and operations', () async {
    final d = await _Dovecot.open();
    addTearDown(d.close);
    await d.append('INBOX', rawMessage(id: 'root@x', subject: 'Lunch?', body: 'Friday?'));
    await d.append('Sent', rawMessage(
      id: 'reply@x',
      from: 'Plume <${d.user}>',
      subject: 'Re: Lunch?',
      body: 'Yes',
      inReplyTo: 'root@x',
      references: ['root@x'],
    ), flags: [r'\Seen']);
    await d.append('INBOX', richMessage(id: 'rich@x'));
    await d.provider.sync(d.store);
    var all = await d.messages();
    expect(all, hasLength(3));
    final lunch = all.values.singleWhere((m) => m.subject == 'Lunch?');
    expect(all.values.where((m) => m.threadId == lunch.threadId), hasLength(2));
    final rich = all.values.singleWhere((m) => m.subject == 'Report');
    expect(rich.attachments.map((a) => (a.partId, a.filename, a.isInline)), [('1.2', 'logo.png', true), ('2', 'q3.pdf', false)]);
    expect(rich.snippet, 'Quarterly numbers — see attached.');

    // Bodies and attachments.
    await d.provider.fetchBodies(d.store, [rich.id, lunch.id]);
    expect((await d.store.body(d.account.id, rich.id))!.inlineParts['logo@x'], [137, 80, 78, 71, 1, 2, 3]);
    final pdf = await d.provider.fetchAttachment(rich.id, rich.attachments[1]);
    expect(pdf, List<int>.generate(3000, (i) => (i * 7) & 0xFF));

    // Another device: new mail, a flag change, a deletion.
    final other = await d.other();
    await other.select('INBOX');
    final uid = ImapIds.parse(lunch.id)!.uid;
    await other.store(UidSet.of([uid]), '+FLAGS.SILENT', const [r'\Seen', r'\Flagged']);
    await other.store(UidSet.of([ImapIds.parse(rich.id)!.uid]), '+FLAGS.SILENT', const [r'\Deleted']);
    await other.expunge();
    await other.append('INBOX', Uint8List.fromList(utf8.encode(rawMessage(id: 'new@x', subject: 'Invoice'))));
    await other.logout();
    final result = await d.provider.sync(d.store);
    expect(result.newMessages.map((m) => m.subject), ['Invoice']);
    all = await d.messages();
    expect(all[lunch.id]!.isRead, isTrue);
    expect(all[lunch.id]!.isFlagged, isTrue);
    expect(all[rich.id], isNull);

    // Archive: Dovecot has no Archive folder by default; it is created.
    await d.perform(d.action(MailAction.archive, [lunch.threadId]));
    all = await d.messages();
    final archived = all.values.singleWhere((m) => m.subject == 'Lunch?');
    expect(ImapIds.parse(archived.id)!.path, 'Archive');
    expect(archived.mailboxIds, {'Archive'});
    expect(await d.store.body(d.account.id, archived.id), isNotNull, reason: 're-keyed with COPYUID');
    expect(all.values.singleWhere((m) => m.subject == 'Re: Lunch?').mailboxIds, {'Sent'});
    await d.provider.sync(d.store);
    expect((await d.messages()).keys.toSet(), all.keys.toSet(), reason: 'nothing duplicated or lost');
    expect((await d.store.mailboxes(d.account.id)).singleWhere((m) => m.id == 'Archive').role, MailboxRole.archive);

    // Undo with the original id (message scope).
    await d.perform(MailEngine.inverseOf(d.action(MailAction.archive, [lunch.id], scope: OperationScope.message))!);
    expect((await d.messages()).values.singleWhere((m) => m.subject == 'Lunch?').mailboxIds, {'INBOX'});

    // Trash, restore, delete forever.
    await d.perform(d.action(MailAction.trash, [lunch.threadId]));
    expect((await d.messages()).values.where((m) => m.mailboxIds.contains('Trash')), hasLength(2));
    await d.perform(d.action(MailAction.restore, [lunch.threadId]));
    await d.perform(d.action(MailAction.markUnread, [lunch.threadId]));
    await d.perform(d.action(MailAction.trash, [lunch.threadId]));
    await d.perform(d.action(MailAction.deleteForever, [lunch.threadId]));
    await d.provider.sync(d.store);
    expect((await d.messages()).values.where((m) => m.threadId == lunch.threadId), isEmpty);
    final check = await d.other();
    final trash = await check.select('Trash');
    expect(trash.exists, 0);
    await check.logout();
  });

  test('send files a copy in Sent; drafts; search; IDLE', () async {
    final d = await _Dovecot.open();
    addTearDown(d.close);
    await d.append('INBOX', rawMessage(id: 'hello@x', subject: 'Quarterly invoice', body: 'Please pay the invoice.'));
    await d.provider.sync(d.store);

    final message = OutgoingMessage(
      accountId: d.account.id,
      from: Address(d.user, 'Plume'),
      to: const [Address('ben@example.com')],
      bcc: const [Address('boss@example.com')],
      subject: 'Re: Quarterly invoice',
      textBody: 'Paid.',
      inReplyTo: '<hello@x>',
      references: const ['<hello@x>'],
    );
    final draftId = await d.provider.saveDraft(message);
    expect(ImapIds.parse(draftId)!.path, 'Drafts');
    final draft2 = await d.provider.saveDraft(message.copyWith(draftId: draftId));
    final sentId = await d.provider.send(message.copyWith(draftId: draft2));
    expect(ImapIds.parse(sentId)!.path, 'Sent');
    expect(d.sender.sent.single.recipients, ['ben@example.com', 'boss@example.com']);
    await d.provider.sync(d.store);
    final all = await d.messages();
    expect(all.values.where((m) => m.isDraft), isEmpty, reason: 'the draft was deleted after sending');
    final sent = all[sentId]!;
    expect(sent.isRead, isTrue);
    expect(sent.bcc, [const Address('boss@example.com')]);
    expect(sent.threadId, all.values.singleWhere((m) => m.subject == 'Quarterly invoice').threadId);

    final page = await d.provider.search(d.store, 'invoice');
    expect(page.threadIds, [sent.threadId]);

    final events = StreamController<void>();
    final sub = d.provider.watchChanges().listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await d.append('INBOX', rawMessage(id: 'push@x', subject: 'Pushed'));
    await events.stream.first.timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect((await d.provider.sync(d.store)).newMessages.map((m) => m.subject), ['Pushed']);
  });
}
