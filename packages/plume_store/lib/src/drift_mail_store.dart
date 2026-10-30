import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';

import 'codecs.dart';
import 'database.dart';
import 'search_query.dart';
import 'stream_util.dart';
import 'thread_query.dart';

final _log = Logger('plume_store.DriftMailStore');

/// [MailStore] backed by SQLite through drift.
///
/// Reads used by the UI are reactive drift queries; derived thread rows are
/// recomputed set-based in the same transaction as every message write.
final class DriftMailStore implements MailStore {
  DriftMailStore(this.db);

  /// Opens (creating if needed) the store at [path]. See [PlumeDatabase.open].
  factory DriftMailStore.open(String path, {int readPool = 2, bool logStatements = false}) =>
      DriftMailStore(PlumeDatabase.open(File(path), readPool: readPool, logStatements: logStatements));

  /// A private in-memory store, for tests.
  factory DriftMailStore.inMemory({bool logStatements = false}) =>
      DriftMailStore(PlumeDatabase.memory(logStatements: logStatements));

  final PlumeDatabase db;

  Future<void> close() => db.close();

  // Helpers ------------------------------------------------------------------

  static List<Variable<Object>> _vars(List<Object?> args) => [for (final a in args) Variable<Object>(a)];

  Future<List<QueryRow>> _select(String sql, [List<Object?> args = const []]) =>
      db.customSelect(sql, variables: _vars(args)).get();

  Selectable<QueryRow> _query(String sql, List<Object?> args, Set<ResultSetImplementation<dynamic, dynamic>> tables) =>
      db.customSelect(sql, variables: _vars(args), readsFrom: tables);

  Future<void> _exec(String sql, [List<Object?> args = const []]) => db.customStatement(sql, args);

  void _notify(Iterable<TableInfo<Table, dynamic>> tables) =>
      db.notifyUpdates({for (final t in tables) TableUpdate.onTable(t)});

  late final _mailTables = <TableInfo<Table, dynamic>>{
    db.messages,
    db.messageMailboxes,
    db.threads,
    db.threadMailboxes,
  };

  static String _json(Iterable<Object?> values) => jsonEncode(values is List ? values : values.toList());

  @override
  Future<T> transaction<T>(Future<T> Function() action) => db.transaction(action);

  // Sync state ---------------------------------------------------------------

  @override
  Future<String?> readState(String accountId, String key) async {
    final rows = await _select('SELECT value FROM sync_state WHERE account_id = ?1 AND "key" = ?2', [accountId, key]);
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  @override
  Future<void> writeState(String accountId, String key, String? value) async {
    if (value == null) {
      await _exec('DELETE FROM sync_state WHERE account_id = ?1 AND "key" = ?2', [accountId, key]);
    } else {
      await _exec(
        'INSERT INTO sync_state (account_id, "key", value) VALUES (?1, ?2, ?3) '
        'ON CONFLICT (account_id, "key") DO UPDATE SET value = excluded.value',
        [accountId, key, value],
      );
    }
    _notify([db.syncState]);
  }

  // Accounts -----------------------------------------------------------------

  static const _accountsSql = 'SELECT * FROM accounts ORDER BY sort_order, email, id';

  @override
  Stream<List<Account>> watchAccounts() => _query(_accountsSql, const [], {
    db.accounts,
  }).watch().map((rows) => rows.map(accountFromRow).toList()).distinct(const ListEquality<Account>().equals);

  @override
  Future<List<Account>> accounts() async => (await _select(_accountsSql)).map(accountFromRow).toList();

  @override
  Future<void> saveAccount(Account a) async {
    // A true upsert: INSERT OR REPLACE would delete the row and cascade.
    await _exec(
      'INSERT INTO accounts (id, provider, email, display_name, avatar_url, color, sort_order, status, signature, '
      'provider_config) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) '
      'ON CONFLICT (id) DO UPDATE SET provider = excluded.provider, email = excluded.email, '
      'display_name = excluded.display_name, avatar_url = excluded.avatar_url, color = excluded.color, '
      'sort_order = excluded.sort_order, status = excluded.status, signature = excluded.signature, '
      'provider_config = excluded.provider_config',
      [
        a.id,
        a.provider,
        a.email,
        a.displayName,
        a.avatarUrl,
        a.color,
        a.sortOrder,
        a.status.name,
        a.signature,
        a.providerConfig.isEmpty ? null : jsonEncode(a.providerConfig),
      ],
    );
    _notify([db.accounts]);
  }

  @override
  Future<void> deleteAccount(String accountId) => db.transaction(() async {
    await _exec('DELETE FROM message_fts WHERE rowid IN (SELECT row_id FROM messages WHERE account_id = ?1)', [
      accountId,
    ]);
    // Everything else cascades from the account row.
    await _exec('DELETE FROM accounts WHERE id = ?1', [accountId]);
    _notify(db.allTables);
  });

  // Mailboxes ----------------------------------------------------------------

  static const _mailboxOrder = 'ORDER BY a.sort_order, a.id, b.sort_order, b.name COLLATE NOCASE, b.id';

  @override
  Stream<List<Mailbox>> watchMailboxes({String? accountId}) => _query(
    'SELECT b.* FROM mailboxes b JOIN accounts a ON a.id = b.account_id '
    '${accountId == null ? '' : 'WHERE b.account_id = ?1 '}$_mailboxOrder',
    [?accountId],
    {db.mailboxes, db.accounts},
  ).watch().map((rows) => rows.map(mailboxFromRow).toList()).distinct(const ListEquality<Mailbox>().equals);

  @override
  Future<List<Mailbox>> mailboxes(String accountId) async => (await _select(
    'SELECT b.* FROM mailboxes b JOIN accounts a ON a.id = b.account_id WHERE b.account_id = ?1 $_mailboxOrder',
    [accountId],
  )).map(mailboxFromRow).toList();

  Future<Set<String>> _trashOrJunkIds(String accountId) async => {
    for (final r in await _select("SELECT id FROM mailboxes WHERE account_id = ?1 AND role IN ('trash', 'junk')", [
      accountId,
    ]))
      r.read<String>('id'),
  };

  @override
  Future<void> replaceMailboxes(String accountId, List<Mailbox> mailboxes) => db.transaction(() async {
    final before = await _trashOrJunkIds(accountId);
    await db.batch((b) {
      b.customStatement('DELETE FROM mailboxes WHERE account_id = ?1 AND id NOT IN (SELECT value FROM json_each(?2))', [
        accountId,
        _json(mailboxes.map((m) => m.id)),
      ]);
      for (final m in mailboxes) {
        b.customStatement(
          'INSERT INTO mailboxes (account_id, id, name, role, category, kind, parent_id, color, '
          'unread_threads, total_threads, sort_order, hidden) '
          'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) '
          'ON CONFLICT (account_id, id) DO UPDATE SET name = excluded.name, role = excluded.role, '
          'category = excluded.category, kind = excluded.kind, parent_id = excluded.parent_id, '
          'color = excluded.color, unread_threads = excluded.unread_threads, '
          'total_threads = excluded.total_threads, sort_order = excluded.sort_order, hidden = excluded.hidden',
          [
            accountId, m.id, m.name, m.role?.name, m.category?.name, m.kind.name, m.parentId, m.color, //
            m.unreadThreads, m.totalThreads, m.sortOrder, m.hidden ? 1 : 0,
          ],
        );
      }
    });
    _notify([db.mailboxes]);
    // Which messages count as trash/junk changed: every thread's
    // active_count may be stale.
    final after = await _trashOrJunkIds(accountId);
    if (!const SetEquality<String>().equals(before, after)) await _recomputeAllThreads(accountId);
  });

  @override
  Future<void> updateMailboxCounts(String accountId, Map<String, ({int unread, int total})> counts) async {
    if (counts.isEmpty) return;
    await db.batch((b) {
      for (final MapEntry(key: id, value: c) in counts.entries) {
        b.customStatement(
          'UPDATE mailboxes SET unread_threads = ?3, total_threads = ?4 WHERE account_id = ?1 AND id = ?2',
          [accountId, id, c.unread, c.total],
        );
      }
    });
    _notify([db.mailboxes]);
  }

  // Messages -----------------------------------------------------------------

  static const _insertMembershipSql =
      'INSERT INTO message_mailboxes (account_id, message_id, mailbox_id) '
      'SELECT ?1, j.value ->> 0, j.value ->> 1 FROM json_each(?2) j WHERE true ON CONFLICT DO NOTHING';

  static const _deleteFtsSql =
      'DELETE FROM message_fts WHERE rowid IN '
      '(SELECT row_id FROM messages WHERE account_id = ?1 AND id IN (SELECT value FROM json_each(?2)))';

  static const _insertFtsSql = '''
INSERT INTO message_fts (rowid, subject, sender, recipients, snippet, body)
SELECT m.row_id, m.subject, plume_addr_text(m.from_addr), plume_addr_text(m.to_addrs, m.cc_addrs, m.bcc_addrs),
  m.snippet, CASE WHEN b.message_id IS NULL THEN '' ELSE plume_body_text(b.html, b.plain) END
FROM messages m LEFT JOIN bodies b ON b.account_id = m.account_id AND b.message_id = m.id
WHERE m.account_id = ?1 AND m.id IN (SELECT value FROM json_each(?2))''';

  static const _upsertContactsSql = '''
INSERT INTO contacts (email, name, use_count, last_used)
SELECT j.value ->> 0, j.value ->> 1, j.value ->> 2, j.value ->> 3 FROM json_each(?1) j WHERE true
ON CONFLICT (email) DO UPDATE SET
  use_count = use_count + excluded.use_count,
  name = CASE WHEN excluded.name IS NOT NULL AND (name IS NULL OR excluded.last_used >= last_used)
    THEN excluded.name ELSE name END,
  last_used = max(last_used, excluded.last_used)''';

  @override
  Future<void> upsertMessages(String accountId, List<Message> messages) async {
    if (messages.isEmpty) return;
    final byId = <String, EncodedMessage>{for (final m in messages) m.id: EncodedMessage(m)};
    final idsJson = _json(byId.keys);
    await db.transaction(() async {
      final existing = {
        for (final r in await _select(
          'SELECT id, thread_id, subject, snippet, from_addr, to_addrs, cc_addrs, bcc_addrs FROM messages '
          'WHERE account_id = ?1 AND id IN (SELECT value FROM json_each(?2))',
          [accountId, idsJson],
        ))
          r.read<String>('id'): r,
      };
      final threadIds = <String>{};
      final ftsIds = <String>[];
      final reindexIds = <String>[];
      final added = <Message>[];
      for (final e in byId.values) {
        final m = e.message;
        threadIds.add(m.threadId);
        final old = existing[m.id];
        if (old == null) {
          ftsIds.add(m.id);
          added.add(m);
        } else {
          threadIds.add(old.read<String>('thread_id'));
          if (e.indexedTextDiffers(old)) reindexIds.add(m.id);
        }
      }
      final contacts = _contactsOf(added);
      await db.batch((b) {
        for (final e in byId.values) {
          b.customStatement(upsertMessageSql, e.args(accountId));
        }
        b.customStatement(
          'DELETE FROM message_mailboxes WHERE account_id = ?1 AND message_id IN (SELECT value FROM json_each(?2))',
          [accountId, idsJson],
        );
        b.customStatement(_insertMembershipSql, [
          accountId,
          _json([
            for (final e in byId.values)
              for (final mb in e.message.mailboxIds) [e.message.id, mb],
          ]),
        ]);
        if (reindexIds.isNotEmpty) b.customStatement(_deleteFtsSql, [accountId, _json(reindexIds)]);
        if (ftsIds.isNotEmpty || reindexIds.isNotEmpty) {
          b.customStatement(_insertFtsSql, [
            accountId,
            _json([...ftsIds, ...reindexIds]),
          ]);
        }
        if (contacts != null) b.customStatement(_upsertContactsSql, [contacts]);
        _addRecompute(b, accountId, threadIds);
      });
      _notify([..._mailTables, if (contacts != null) db.contacts]);
    });
  }

  /// JSON rows for [_upsertContactsSql] from newly stored messages (drafts
  /// excluded), or null when there are none.
  static String? _contactsOf(List<Message> added) {
    final agg = <String, (String?, int, int)>{};
    for (final m in added) {
      if (m.isDraft) continue;
      final date = m.date.millisecondsSinceEpoch;
      for (final a in [?m.from, ...m.to, ...m.cc]) {
        final email = a.email.trim().toLowerCase();
        if (!email.contains('@')) continue;
        final name = a.name?.trim();
        final named = name == null || name.isEmpty || name.toLowerCase() == email ? null : name;
        final (prevName, count, last) = agg[email] ?? (null, 0, 0);
        final useNew = named != null && (prevName == null || date >= last);
        agg[email] = (useNew ? named : prevName, count + 1, date > last ? date : last);
      }
    }
    if (agg.isEmpty) return null;
    return _json([
      for (final MapEntry(key: email, value: (name, count, last)) in agg.entries) [email, name, count, last],
    ]);
  }

  @override
  Future<void> applyDeltas(String accountId, List<MessageDelta> deltas) async {
    if (deltas.isEmpty) return;
    // Fold deltas per message, in order, so that a later record wins.
    final folded = <String, ({Set<String> add, Set<String> remove, bool? read, bool? flagged})>{};
    for (final d in deltas) {
      final f = folded[d.messageId] ?? (add: <String>{}, remove: <String>{}, read: null, flagged: null);
      for (final m in d.addMailboxes) {
        f.add.add(m);
        f.remove.remove(m);
      }
      for (final m in d.removeMailboxes) {
        f.remove.add(m);
        f.add.remove(m);
      }
      folded[d.messageId] = (add: f.add, remove: f.remove, read: d.isRead ?? f.read, flagged: d.isFlagged ?? f.flagged);
    }
    // Set-based statements driven by the (small) id lists, so that every
    // access to messages and memberships is a primary-key lookup.
    final ids = <String>[];
    final read = <bool, List<String>>{true: [], false: []};
    final flagged = <bool, List<String>>{true: [], false: []};
    final add = <List<String>>[];
    final remove = <List<String>>[];
    for (final MapEntry(key: id, value: f) in folded.entries) {
      ids.add(id);
      if (f.read case final r?) read[r]!.add(id);
      if (f.flagged case final v?) flagged[v]!.add(id);
      for (final m in f.add) {
        add.add([id, m]);
      }
      for (final m in f.remove) {
        remove.add([id, m]);
      }
    }
    await db.transaction(() async {
      final threadIds = await _threadsOf(accountId, 'id IN (SELECT value FROM json_each(?2))', _json(ids));
      if (threadIds.isEmpty) return;
      await db.batch((b) {
        for (final (column, values) in [('is_read', read), ('is_flagged', flagged)]) {
          for (final MapEntry(key: value, value: list) in values.entries) {
            if (list.isEmpty) continue;
            b.customStatement(
              'UPDATE messages SET $column = ?3 WHERE account_id = ?1 AND id IN (SELECT value FROM json_each(?2))',
              [accountId, _json(list), value ? 1 : 0],
            );
          }
        }
        if (add.isNotEmpty) {
          b.customStatement(
            'INSERT INTO message_mailboxes (account_id, message_id, mailbox_id) '
            'SELECT ?1, j.value ->> 0, j.value ->> 1 FROM json_each(?2) j '
            'WHERE EXISTS (SELECT 1 FROM messages m WHERE m.account_id = ?1 AND m.id = j.value ->> 0) '
            'ON CONFLICT DO NOTHING',
            [accountId, _json(add)],
          );
        }
        if (remove.isNotEmpty) {
          b.customStatement(
            'DELETE FROM message_mailboxes WHERE account_id = ?1 AND (message_id, mailbox_id) IN '
            '(SELECT j.value ->> 0, j.value ->> 1 FROM json_each(?2) j)',
            [accountId, _json(remove)],
          );
        }
        _addRecompute(b, accountId, threadIds);
      });
      _notify(_mailTables);
    });
  }

  @override
  Future<void> deleteMessages(String accountId, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _deleteWhere(accountId, 'id IN (SELECT value FROM json_each(?2))', _json(messageIds));
  }

  @override
  Future<void> deleteThreads(String accountId, List<String> threadIds) async {
    if (threadIds.isEmpty) return;
    await _deleteWhere(
      accountId,
      'thread_id IN (SELECT value FROM json_each(?2))',
      _json(threadIds),
      alsoRecompute: threadIds,
    );
  }

  @override
  Future<void> renameMessages(String accountId, Map<String, String> oldToNew) async {
    final pairs = [
      for (final MapEntry(key: from, value: to) in oldToNew.entries)
        if (from != to) [from, to],
    ];
    if (pairs.isEmpty) return;
    final pairsJson = _json(pairs);
    await db.transaction(() async {
      // Children reference (account_id, id) without ON UPDATE CASCADE; the
      // ids are swapped in parent and children within this transaction, so
      // the foreign key check is deferred to its end.
      await _exec('PRAGMA defer_foreign_keys = ON');
      final rows = await _select(
        'SELECT j.value ->> 0 AS old_id, j.value ->> 1 AS new_id, '
        'EXISTS (SELECT 1 FROM messages n WHERE n.account_id = ?1 AND n.id = j.value ->> 1) AS taken, '
        'EXISTS (SELECT 1 FROM bodies b WHERE b.account_id = ?1 AND b.message_id = j.value ->> 0) AS old_body, '
        'EXISTS (SELECT 1 FROM bodies b WHERE b.account_id = ?1 AND b.message_id = j.value ->> 1) AS new_body '
        'FROM json_each(?2) j WHERE EXISTS (SELECT 1 FROM messages m WHERE m.account_id = ?1 AND m.id = j.value ->> 0)',
        [accountId, pairsJson],
      );
      if (rows.isEmpty) return;
      final move = <List<String>>[];
      final duplicates = <String>[];
      final bodyTransfers = <List<String>>[];
      for (final r in rows) {
        final from = r.read<String>('old_id');
        final to = r.read<String>('new_id');
        if (r.read<bool>('taken')) {
          duplicates.add(from);
          if (r.read<bool>('old_body') && !r.read<bool>('new_body')) bodyTransfers.add([from, to]);
        } else {
          move.add([from, to]);
        }
      }
      if (move.isNotEmpty) {
        final moveJson = _json(move);
        await db.batch((b) {
          for (final table in ['body_parts', 'bodies', 'message_mailboxes']) {
            b.customStatement(
              'UPDATE $table SET message_id = '
              '(SELECT j.value ->> 1 FROM json_each(?2) j WHERE j.value ->> 0 = $table.message_id) '
              'WHERE account_id = ?1 AND message_id IN (SELECT j.value ->> 0 FROM json_each(?2) j)',
              [accountId, moveJson],
            );
          }
          // row_id (the full-text rowid) is unchanged, so the index stays valid.
          // json_each has an `id` column of its own, hence messages.id.
          b.customStatement(
            'UPDATE messages SET id = (SELECT j.value ->> 1 FROM json_each(?2) j WHERE j.value ->> 0 = messages.id) '
            'WHERE account_id = ?1 AND id IN (SELECT j.value ->> 0 FROM json_each(?2) j)',
            [accountId, moveJson],
          );
        });
      }
      if (bodyTransfers.isNotEmpty) {
        final transferJson = _json(bodyTransfers);
        await db.batch((b) {
          // Bodies first, then their inline parts (which reference bodies).
          for (final table in ['bodies', 'body_parts']) {
            b.customStatement(
              'UPDATE $table SET message_id = '
              '(SELECT j.value ->> 1 FROM json_each(?2) j WHERE j.value ->> 0 = $table.message_id) '
              'WHERE account_id = ?1 AND message_id IN (SELECT j.value ->> 0 FROM json_each(?2) j)',
              [accountId, transferJson],
            );
          }
          b.customStatement(_deleteFtsSql, [accountId, _json([for (final t in bodyTransfers) t[1]])]);
          b.customStatement(_insertFtsSql, [accountId, _json([for (final t in bodyTransfers) t[1]])]);
        });
      }
      _notify([..._mailTables, db.bodies, db.bodyParts]);
      if (duplicates.isNotEmpty) await deleteMessages(accountId, duplicates);
    });
  }

  /// Thread ids of the messages of [accountId] matching [where] (which may
  /// use `?2` bound to [arg]). Deduplicated here rather than with DISTINCT,
  /// which would make SQLite prefer scanning the whole thread index.
  Future<Set<String>> _threadsOf(String accountId, String where, String arg) async => {
    for (final r in await _select('SELECT thread_id FROM messages WHERE account_id = ?1 AND $where', [accountId, arg]))
      r.read<String>('thread_id'),
  };

  /// Deletes the messages of [accountId] matching [where] (which may use `?2`
  /// bound to [arg]) with their bodies and index entries, then recomputes
  /// their threads.
  Future<void> _deleteWhere(String accountId, String where, String arg, {Iterable<String> alsoRecompute = const []}) =>
      db.transaction(() async {
        final threadIds = {...alsoRecompute, ...await _threadsOf(accountId, where, arg)};
        if (threadIds.isEmpty) return;
        await db.batch((b) {
          b.customStatement(
            'DELETE FROM message_fts WHERE rowid IN (SELECT row_id FROM messages WHERE account_id = ?1 AND $where)',
            [accountId, arg],
          );
          // Bodies, inline parts and memberships cascade.
          b.customStatement('DELETE FROM messages WHERE account_id = ?1 AND $where', [accountId, arg]);
          _addRecompute(b, accountId, threadIds);
        });
        _notify([..._mailTables, db.bodies, db.bodyParts]);
      });

  @override
  Future<Set<String>> knownMessageIds(String accountId, Iterable<String> messageIds) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) return {};
    final rows = await _select(
      'SELECT id FROM messages WHERE account_id = ?1 AND id IN (SELECT value FROM json_each(?2))',
      [accountId, _json(ids)],
    );
    return {for (final r in rows) r.read<String>('id')};
  }

  @override
  Future<List<Message>> messagesInThreads(String accountId, Iterable<String> threadIds) async {
    final ids = threadIds.toList();
    if (ids.isEmpty) return [];
    final rows = await _select(
      'SELECT $messageColumns FROM messages m '
      'WHERE m.account_id = ?1 AND m.thread_id IN (SELECT value FROM json_each(?2)) '
      'ORDER BY m.thread_id, m.date, m.id',
      [accountId, _json(ids)],
    );
    return rows.map(messageFromRow).toList();
  }

  @override
  Future<List<String>> messageIdsOfThreads(String accountId, Iterable<String> threadIds) async {
    final ids = threadIds.toList();
    if (ids.isEmpty) return [];
    final rows = await _select(
      'SELECT id FROM messages WHERE account_id = ?1 AND thread_id IN (SELECT value FROM json_each(?2)) '
      'ORDER BY thread_id, date, id',
      [accountId, _json(ids)],
    );
    return [for (final r in rows) r.read<String>('id')];
  }

  // Bodies -------------------------------------------------------------------

  @override
  Future<void> saveBody(String accountId, String messageId, MessageBody body) => db.transaction(() async {
    final known = await _select('SELECT 1 FROM messages WHERE account_id = ?1 AND id = ?2', [accountId, messageId]);
    if (known.isEmpty) {
      _log.fine('Ignoring body of unknown message $accountId/$messageId');
      return;
    }
    final ids = _json([messageId]);
    await db.batch((b) {
      b.customStatement(
        'INSERT INTO bodies (account_id, message_id, html, plain) VALUES (?1, ?2, ?3, ?4) '
        'ON CONFLICT (account_id, message_id) DO UPDATE SET html = excluded.html, plain = excluded.plain',
        [accountId, messageId, body.html, body.text],
      );
      b.customStatement('DELETE FROM body_parts WHERE account_id = ?1 AND message_id = ?2', [accountId, messageId]);
      for (final MapEntry(key: cid, value: bytes) in body.inlineParts.entries) {
        b.customStatement(
          'INSERT INTO body_parts (account_id, message_id, content_id, data) VALUES (?1, ?2, ?3, ?4) '
          'ON CONFLICT DO UPDATE SET data = excluded.data',
          [accountId, messageId, cid, bytes],
        );
      }
      b.customStatement(_deleteFtsSql, [accountId, ids]);
      b.customStatement(_insertFtsSql, [accountId, ids]);
    });
    _notify([db.bodies, db.bodyParts]);
  });

  @override
  Future<MessageBody?> body(String accountId, String messageId) async {
    final rows = await _select('SELECT html, plain FROM bodies WHERE account_id = ?1 AND message_id = ?2', [
      accountId,
      messageId,
    ]);
    if (rows.isEmpty) return null;
    final parts = await _select('SELECT content_id, data FROM body_parts WHERE account_id = ?1 AND message_id = ?2', [
      accountId,
      messageId,
    ]);
    return MessageBody(
      html: rows.first.readNullable<String>('html'),
      text: rows.first.readNullable<String>('plain'),
      inlineParts: {for (final p in parts) p.read<String>('content_id'): p.read<Uint8List>('data')},
    );
  }

  @override
  Future<List<String>> messagesWithoutBody(String accountId, Iterable<String> messageIds) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) return [];
    final rows = await _select(
      'SELECT j.value AS id FROM json_each(?2) j WHERE NOT EXISTS '
      '(SELECT 1 FROM bodies b WHERE b.account_id = ?1 AND b.message_id = j.value) ORDER BY j.key',
      [accountId, _json(ids)],
    );
    return [for (final r in rows) r.read<String>('id')];
  }

  @override
  Future<List<String>> recentMessagesWithoutBody(String accountId, String mailboxId, {int limit = 50}) async {
    // Walks the mailbox's threads newest first (index order) and stops after
    // [limit] hits, so the cost does not grow with the mailbox size.
    final rows = await _select(
      'SELECT m.id FROM thread_mailboxes tm '
      'CROSS JOIN messages m ON m.account_id = tm.account_id AND m.thread_id = tm.thread_id '
      'WHERE tm.account_id = ?1 AND tm.mailbox_id = ?2 '
      'AND EXISTS (SELECT 1 FROM message_mailboxes mm WHERE mm.account_id = m.account_id '
      'AND mm.message_id = m.id AND mm.mailbox_id = ?2) '
      'AND NOT EXISTS (SELECT 1 FROM bodies b WHERE b.account_id = m.account_id AND b.message_id = m.id) '
      'ORDER BY tm.last_date DESC, tm.thread_id, m.date DESC LIMIT ?3',
      [accountId, mailboxId, limit],
    );
    return [for (final r in rows) r.read<String>('id')];
  }

  @override
  Future<void> clearMail(String accountId) => db.transaction(() async {
    await db.batch((b) {
      b.customStatement('DELETE FROM message_fts WHERE rowid IN (SELECT row_id FROM messages WHERE account_id = ?1)', [
        accountId,
      ]);
      b.customStatement('DELETE FROM threads WHERE account_id = ?1', [accountId]);
      b.customStatement('DELETE FROM messages WHERE account_id = ?1', [accountId]);
      // Cursors describe the wiped data; a full resync must start over.
      b.customStatement('DELETE FROM sync_state WHERE account_id = ?1', [accountId]);
    });
    _notify([..._mailTables, db.bodies, db.bodyParts, db.syncState]);
  });

  /// Rebuilds the full-text index from `messages` and `bodies`. Use after a
  /// tokenizer change or to repair the index.
  Future<void> rebuildSearchIndex() => db.transaction(() async {
    await _exec('DELETE FROM message_fts');
    await _exec('''
INSERT INTO message_fts (rowid, subject, sender, recipients, snippet, body)
SELECT m.row_id, m.subject, plume_addr_text(m.from_addr), plume_addr_text(m.to_addrs, m.cc_addrs, m.bcc_addrs),
  m.snippet, CASE WHEN b.message_id IS NULL THEN '' ELSE plume_body_text(b.html, b.plain) END
FROM messages m LEFT JOIN bodies b ON b.account_id = m.account_id AND b.message_id = m.id''');
    await _exec("INSERT INTO message_fts (message_fts) VALUES ('optimize')");
  });

  // Derived threads ------------------------------------------------------------

  static const _deleteEmptyThreadsSql = '''
DELETE FROM threads WHERE account_id = ?1 AND id IN (SELECT value FROM json_each(?2))
  AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.account_id = ?1 AND m.thread_id = threads.id)''';

  static const _upsertThreadsSql = '''
INSERT INTO threads (account_id, id, subject, snippet, last_date, message_count, unread_count, flagged,
  has_attachments, draft_count, active_count, participants, mailbox_ids)
SELECT ?1, g.thread_id,
  coalesce((SELECT x.subject FROM messages x WHERE x.account_id = ?1 AND x.thread_id = g.thread_id
    AND x.subject <> '' ORDER BY x.date, x.id LIMIT 1), ''),
  coalesce((SELECT x.snippet FROM messages x WHERE x.account_id = ?1 AND x.thread_id = g.thread_id
    ORDER BY x.is_draft, x.date DESC, x.id DESC LIMIT 1), ''),
  g.last_date, g.message_count, g.unread_count, g.flagged, g.has_attachments, g.draft_count, g.active_count,
  plume_participants(g.senders),
  coalesce((SELECT json_group_array(DISTINCT mm.mailbox_id) FROM messages x
    CROSS JOIN message_mailboxes mm ON mm.account_id = x.account_id AND mm.message_id = x.id
    WHERE x.account_id = ?1 AND x.thread_id = g.thread_id), '[]')
FROM (
  SELECT m.thread_id,
    max(m.date) AS last_date,
    count(*) AS message_count,
    sum(m.is_read = 0 AND m.is_draft = 0) AS unread_count,
    max(m.is_flagged) AS flagged,
    max(m.has_attachments) AS has_attachments,
    sum(m.is_draft) AS draft_count,
    sum(NOT EXISTS (SELECT 1 FROM message_mailboxes mm
      JOIN mailboxes b ON b.account_id = mm.account_id AND b.id = mm.mailbox_id
      WHERE mm.account_id = m.account_id AND mm.message_id = m.id AND b.role IN ('trash', 'junk'))) AS active_count,
    json_group_array(json(m.from_addr) ORDER BY m.date, m.id) AS senders
  FROM messages m
  WHERE m.account_id = ?1 AND m.thread_id IN (SELECT value FROM json_each(?2))
  GROUP BY m.thread_id
) g
WHERE true
ON CONFLICT (account_id, id) DO UPDATE SET
  subject = excluded.subject, snippet = excluded.snippet, last_date = excluded.last_date,
  message_count = excluded.message_count, unread_count = excluded.unread_count, flagged = excluded.flagged,
  has_attachments = excluded.has_attachments, draft_count = excluded.draft_count,
  active_count = excluded.active_count, participants = excluded.participants, mailbox_ids = excluded.mailbox_ids''';

  static const _clearThreadMailboxesSql =
      'DELETE FROM thread_mailboxes WHERE account_id = ?1 AND thread_id IN (SELECT value FROM json_each(?2))';

  static const _fillThreadMailboxesSql = '''
INSERT INTO thread_mailboxes (account_id, thread_id, mailbox_id, last_date, unread)
SELECT t.account_id, t.id, j.value, t.last_date, t.unread_count > 0
FROM threads t, json_each(t.mailbox_ids) j
WHERE t.account_id = ?1 AND t.id IN (SELECT value FROM json_each(?2))''';

  /// Appends the statements that recompute [threadIds] from their messages:
  /// summaries, mailbox membership, and removal of threads left empty.
  static void _addRecompute(Batch b, String accountId, Iterable<String> threadIds) {
    final ids = _json(threadIds);
    final args = [accountId, ids];
    b
      ..customStatement(_deleteEmptyThreadsSql, args)
      ..customStatement(_upsertThreadsSql, args)
      ..customStatement(_clearThreadMailboxesSql, args)
      ..customStatement(_fillThreadMailboxesSql, args);
  }

  Future<void> _recomputeAllThreads(String accountId) async {
    final ids = [
      for (final r in await _select(
        'SELECT id FROM threads WHERE account_id = ?1 UNION SELECT thread_id FROM messages WHERE account_id = ?1',
        [accountId],
      ))
        r.read<String>('id'),
    ];
    if (ids.isEmpty) return;
    await db.batch((b) => _addRecompute(b, accountId, ids));
    _notify(_mailTables);
  }

  // Thread lists -----------------------------------------------------------------

  Stream<MailboxDirectory> get _directory =>
      _query(MailboxDirectory.sql, const [], {db.accounts, db.mailboxes}).watch().map(
        (rows) => MailboxDirectory.fromRows(
          rows.map(
            (r) => (
              accountId: r.read<String>('account_id'),
              mailboxId: r.readNullable<String>('mailbox_id'),
              role: r.readNullable<String>('role'),
              category: r.readNullable<String>('category'),
            ),
          ),
        ),
      );

  Stream<ThreadPlan> _plans(ThreadFilter filter) {
    if (!ThreadPlan.needsDirectory(filter)) return Stream.value(ThreadPlan.resolve(filter, null));
    return _directory.map((d) => ThreadPlan.resolve(filter, d)).distinct();
  }

  /// The SQL and arguments [watchThreads] runs for [filter] once resolved,
  /// for diagnostics (EXPLAIN QUERY PLAN) and benchmarks.
  Future<({String sql, List<Object?> args})> debugThreadQuery(
    ThreadFilter filter, {
    int limit = 300,
    bool count = false,
  }) async {
    final plan = await _plans(filter).first;
    final q = count ? plan.countQuery() : plan.listQuery(limit);
    return (sql: q.sql, args: q.args);
  }

  @override
  Stream<List<ThreadSummary>> watchThreads(ThreadFilter filter, {int limit = 300}) => _plans(filter)
      .switchMap((plan) {
        if (plan.isEmpty || limit <= 0) return Stream.value(const <ThreadSummary>[]);
        final q = plan.listQuery(limit);
        return _query(q.sql, q.args, {
          db.threads,
          db.threadMailboxes,
        }).watch().map((rows) => rows.map(threadFromRow).toList(growable: false));
      })
      .distinct(const ListEquality<ThreadSummary>().equals);

  @override
  Stream<int> watchUnreadCount(ThreadFilter filter) => _plans(filter).switchMap((plan) {
    if (plan.isEmpty) return Stream.value(0);
    final q = plan.countQuery();
    return _query(q.sql, q.args, {db.threads, db.threadMailboxes}).watch().map((rows) => rows.first.read<int>('c'));
  }).distinct();

  @override
  Stream<ThreadDetail?> watchThread(String accountId, String threadId) =>
      _query(
            'SELECT t.subject AS t_subject, t.snippet AS t_snippet, t.last_date AS t_last_date, '
            't.message_count AS t_message_count, t.unread_count AS t_unread_count, t.flagged AS t_flagged, '
            't.has_attachments AS t_has_attachments, t.draft_count AS t_draft_count, '
            't.participants AS t_participants, t.mailbox_ids AS t_mailbox_ids, t.account_id AS t_account_id, '
            't.id AS t_id, $messageColumns '
            'FROM threads t JOIN messages m ON m.account_id = t.account_id AND m.thread_id = t.id '
            'WHERE t.account_id = ?1 AND t.id = ?2 ORDER BY m.date, m.id',
            [accountId, threadId],
            {db.threads, db.messages, db.messageMailboxes},
          )
          .watch()
          .map((rows) {
            if (rows.isEmpty) return null;
            return ThreadDetail(
              summary: threadFromRow(rows.first, prefix: 't_'),
              messages: rows.map(messageFromRow).toList(growable: false),
            );
          })
          .distinct(_sameDetail);

  static bool _sameDetail(ThreadDetail? a, ThreadDetail? b) {
    if (a == null || b == null) return a == b;
    return a.summary == b.summary && const ListEquality<Message>().equals(a.messages, b.messages);
  }

  // Search -------------------------------------------------------------------

  @override
  Future<List<ThreadSummary>> searchLocal(String query, {Set<String>? accountIds, int limit = 100}) async {
    final q = SearchQuery.parse(query);
    if (q.isEmpty || limit <= 0) return [];
    final args = <Object?>[];
    final where = <String>[];
    if (q.match != null) args.add(q.match);
    if (accountIds != null) {
      if (accountIds.isEmpty) return [];
      where.add('m.account_id IN (SELECT value FROM json_each(?))');
      args.add(_json(accountIds));
    }
    if (q.isRead case final read?) where.add('m.is_read = ${read ? 1 : 0}');
    if (q.flagged) where.add('m.is_flagged = 1');
    if (q.hasAttachment) where.add('m.has_attachments = 1');
    if (q.draft) where.add('m.is_draft = 1');
    const inMailbox =
        'EXISTS (SELECT 1 FROM message_mailboxes mm JOIN mailboxes b '
        'ON b.account_id = mm.account_id AND b.id = mm.mailbox_id '
        'WHERE mm.account_id = m.account_id AND mm.message_id = m.id AND ';
    for (final mailbox in q.mailboxes) {
      where.add('$inMailbox(b.role = ? OR lower(b.name) = ? OR lower(b.id) = ?))');
      args.addAll([mailbox, mailbox, mailbox]);
    }
    for (final category in q.categories) {
      where.add('$inMailbox(b.category = ? OR lower(b.name) = ?))');
      args.addAll([category, category]);
    }
    if (!q.includesTrashOrJunk) where.add("NOT $inMailbox b.role IN ('trash', 'junk'))");
    if (q.exclude != null) {
      where.add('m.row_id NOT IN (SELECT rowid FROM message_fts WHERE message_fts MATCH ?)');
      args.add(q.exclude);
    }
    args.add(limit);
    final String sql;
    if (q.match != null) {
      // bm25 cannot be used in an aggregate, so messages are scored first.
      // Weights: subject, sender, recipients, snippet, body.
      sql =
          'WITH scored AS MATERIALIZED (SELECT rowid AS rid, bm25(message_fts, 4.0, 3.0, 1.5, 1.0, 1.0) AS score '
          'FROM message_fts WHERE message_fts MATCH ?), '
          'hits AS (SELECT m.account_id, m.thread_id, min(s.score) AS score '
          'FROM scored s JOIN messages m ON m.row_id = s.rid '
          '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}GROUP BY m.account_id, m.thread_id) '
          'SELECT $threadColumns FROM hits h JOIN threads t ON t.account_id = h.account_id AND t.id = h.thread_id '
          'ORDER BY h.score, t.last_date DESC, t.id LIMIT ?';
    } else {
      sql =
          'WITH hits AS (SELECT DISTINCT m.account_id, m.thread_id FROM messages m WHERE ${where.join(' AND ')}) '
          'SELECT $threadColumns FROM hits h JOIN threads t ON t.account_id = h.account_id AND t.id = h.thread_id '
          'ORDER BY t.last_date DESC, t.id LIMIT ?';
    }
    try {
      return (await _select(sql, args)).map(threadFromRow).toList();
    } on Exception catch (e) {
      // A query FTS5 cannot parse (should not happen: terms are quoted).
      _log.warning('Local search failed for "$query": $e');
      return [];
    }
  }

  @override
  Future<List<Address>> suggestAddresses(String prefix, {int limit = 8}) async {
    final p = prefix.trim().toLowerCase().replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    final rows = await _select(
      r"SELECT email, name FROM contacts WHERE email LIKE ?1 ESCAPE '\' "
      r"OR (' ' || lower(name)) LIKE ?2 ESCAPE '\' "
      'ORDER BY use_count DESC, last_used DESC LIMIT ?3',
      ['$p%', '% $p%', limit],
    );
    return [for (final r in rows) Address(r.read<String>('email'), r.readNullable<String>('name'))];
  }

  // Optimistic local changes ---------------------------------------------------

  @override
  Future<void> applyLocalMutation(
    String accountId,
    OperationScope scope,
    List<String> ids,
    LocalMutation mutation,
  ) async {
    if (ids.isEmpty || mutation.isNoop) return;
    var target = scope == OperationScope.thread
        ? 'thread_id IN (SELECT value FROM json_each(?2))'
        : 'id IN (SELECT value FROM json_each(?2))';
    var idsJson = _json(ids);
    final onlyIn = mutation.onlyIn;
    if (onlyIn != null) {
      // Resolve the matching messages up front: removing memberships below
      // would otherwise change which messages the filter selects.
      final rows = await _select(
        'SELECT m.id FROM messages m WHERE m.account_id = ?1 AND m.$target AND EXISTS ('
        'SELECT 1 FROM message_mailboxes x WHERE x.account_id = ?1 AND x.message_id = m.id '
        'AND x.mailbox_id IN (SELECT value FROM json_each(?3)))',
        [accountId, idsJson, _json(onlyIn)],
      );
      if (rows.isEmpty) return;
      target = 'id IN (SELECT value FROM json_each(?2))';
      idsJson = _json([for (final r in rows) r.read<String>('id')]);
    }
    if (mutation.delete) {
      await _deleteWhere(
        accountId,
        target,
        idsJson,
        alsoRecompute: scope == OperationScope.thread && onlyIn == null ? ids : const [],
      );
      return;
    }
    await db.transaction(() async {
      final threadIds = await _threadsOf(accountId, target, idsJson);
      if (threadIds.isEmpty) return;
      await db.batch((b) {
        if (mutation.setRead != null || mutation.setFlagged != null) {
          b.customStatement(
            'UPDATE messages SET is_read = coalesce(?3, is_read), is_flagged = coalesce(?4, is_flagged) '
            'WHERE account_id = ?1 AND $target',
            [
              accountId,
              idsJson,
              mutation.setRead == null ? null : (mutation.setRead! ? 1 : 0),
              mutation.setFlagged == null ? null : (mutation.setFlagged! ? 1 : 0),
            ],
          );
        }
        if (mutation.addMailboxes.isNotEmpty) {
          b.customStatement(
            'INSERT INTO message_mailboxes (account_id, message_id, mailbox_id) '
            'SELECT ?1, m.id, a.value FROM messages m, json_each(?3) a '
            'WHERE m.account_id = ?1 AND m.$target ON CONFLICT DO NOTHING',
            [accountId, idsJson, _json(mutation.addMailboxes)],
          );
        }
        if (mutation.removeMailboxes.isNotEmpty) {
          b.customStatement(
            'DELETE FROM message_mailboxes WHERE account_id = ?1 '
            'AND mailbox_id IN (SELECT value FROM json_each(?3)) '
            'AND message_id IN (SELECT id FROM messages WHERE account_id = ?1 AND $target)',
            [accountId, idsJson, _json(mutation.removeMailboxes)],
          );
        }
        _addRecompute(b, accountId, threadIds);
      });
      _notify(_mailTables);
    });
  }

  // Operation queue ------------------------------------------------------------

  @override
  Future<int> enqueueOperation(MailOperation operation) => db.customInsert(
    'INSERT INTO pending_ops (account_id, payload) VALUES (?, ?)',
    variables: _vars([operation.accountId, jsonEncode(operation.toJson())]),
    updates: {db.pendingOps},
  );

  @override
  Future<List<PendingOperation>> pendingOperations({String? accountId}) async {
    final rows = await _select(
      'SELECT * FROM pending_ops ${accountId == null ? '' : 'WHERE account_id = ?1 '}ORDER BY id',
      [?accountId],
    );
    final result = <PendingOperation>[];
    for (final r in rows) {
      final id = r.read<int>('id');
      try {
        final notBefore = r.readNullable<int>('not_before');
        result.add(
          PendingOperation(
            id: id,
            operation: MailOperation.fromJson((jsonDecode(r.read<String>('payload')) as Map).cast<String, Object?>()),
            attempts: r.read<int>('attempts'),
            lastError: r.readNullable<String>('last_error'),
            notBefore: notBefore == null ? null : fromEpochMs(notBefore),
          ),
        );
      } on Object catch (e) {
        // Written by a newer version, or corrupt: skip rather than block the
        // whole queue.
        _log.warning('Skipping unreadable pending operation $id: $e');
      }
    }
    return result;
  }

  @override
  Future<void> completeOperation(int id) =>
      db.customUpdate('DELETE FROM pending_ops WHERE id = ?', variables: _vars([id]), updates: {db.pendingOps});

  @override
  Future<void> deferOperation(int id, {required String error, required DateTime notBefore}) => db.customUpdate(
    'UPDATE pending_ops SET attempts = attempts + 1, last_error = ?2, not_before = ?3 WHERE id = ?1',
    variables: _vars([id, error, notBefore.millisecondsSinceEpoch]),
    updates: {db.pendingOps},
  );

  // Outbox -------------------------------------------------------------------

  @override
  Future<int> enqueueOutgoing(OutgoingMessage message, DateTime sendAt) => db.customInsert(
    'INSERT INTO outbox (account_id, payload, send_at, state) VALUES (?, ?, ?, ?)',
    variables: _vars([
      message.accountId,
      OutgoingMessageCodec.encode(message),
      sendAt.millisecondsSinceEpoch,
      OutboxState.scheduled.name,
    ]),
    updates: {db.outbox},
  );

  static const _outboxSql = 'SELECT * FROM outbox ORDER BY send_at, id';

  static OutboxEntry? _outboxFromRow(QueryRow r) {
    final id = r.read<int>('id');
    try {
      return OutboxEntry(
        id: id,
        message: OutgoingMessageCodec.decode(r.read<String>('payload')),
        sendAt: fromEpochMs(r.read<int>('send_at')),
        state: enumByName(OutboxState.values, r.read<String>('state')) ?? OutboxState.failed,
        attempts: r.read<int>('attempts'),
        lastError: r.readNullable<String>('last_error'),
      );
    } on Object catch (e) {
      _log.warning('Skipping unreadable outbox entry $id: $e');
      return null;
    }
  }

  @override
  Stream<List<OutboxEntry>> watchOutbox() =>
      _query(_outboxSql, const [], {db.outbox}).watch().map((rows) => rows.map(_outboxFromRow).nonNulls.toList());

  @override
  Future<List<OutboxEntry>> outbox() async => (await _select(_outboxSql)).map(_outboxFromRow).nonNulls.toList();

  @override
  Future<void> updateOutbox(int id, {required OutboxState state, String? error, DateTime? sendAt}) => db.customUpdate(
    'UPDATE outbox SET state = ?2, '
    "attempts = attempts + (CASE WHEN ?2 IN ('retrying', 'failed') THEN 1 ELSE 0 END), "
    'last_error = coalesce(?3, last_error), send_at = coalesce(?4, send_at) WHERE id = ?1',
    variables: _vars([id, state.name, error, sendAt?.millisecondsSinceEpoch]),
    updates: {db.outbox},
  );

  @override
  Future<void> deleteOutgoing(int id) =>
      db.customUpdate('DELETE FROM outbox WHERE id = ?', variables: _vars([id]), updates: {db.outbox});

  @override
  Future<OutboxEntry?> takeOutgoing(int id) async {
    // One statement, so it cannot interleave with the sender claiming the
    // entry (which moves it out of `scheduled` first).
    final rows = await db.customWriteReturning(
      'DELETE FROM outbox WHERE id = ?1 AND state = ?2 RETURNING *',
      variables: _vars([id, OutboxState.scheduled.name]),
      updates: {db.outbox},
      updateKind: UpdateKind.delete,
    );
    return rows.isEmpty ? null : _outboxFromRow(rows.first);
  }

  // Drafts kept on this device -------------------------------------------------

  static LocalDraft? _localDraftFromRow(QueryRow r) {
    final id = r.read<int>('id');
    final draftId = r.readNullable<String>('draft_id');
    final payload = r.readNullable<String>('payload');
    try {
      return LocalDraft(
        id: id,
        accountId: r.read<String>('account_id'),
        message: payload == null ? null : OutgoingMessageCodec.decode(payload).copyWith(draftId: draftId),
        draftId: draftId,
        revision: r.read<int>('revision'),
        uploadedRevision: r.read<int>('uploaded_revision'),
      );
    } on Object catch (e) {
      _log.warning('Skipping unreadable draft $id: $e');
      return null;
    }
  }

  Future<LocalDraft?> _localDraftWhere(String where, List<Object?> args) async {
    final rows = await _select('SELECT * FROM local_drafts WHERE $where LIMIT 1', args);
    return rows.isEmpty ? null : _localDraftFromRow(rows.first);
  }

  @override
  Future<LocalDraft> saveLocalDraft(OutgoingMessage message, {int? id}) => db.transaction(() async {
    // The server draft is the row's to know; the message may not have
    // caught up with an upload yet.
    final payload = jsonEncode(OutgoingMessageCodec.toJson(message)..remove('draft'));
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _select(
      'SELECT id FROM local_drafts WHERE account_id = ?1 AND payload IS NOT NULL AND (id = ?2 OR draft_id = ?3) '
      'ORDER BY id = ?2 DESC LIMIT 1',
      [message.accountId, id, message.draftId],
    );
    final int key;
    if (existing.isEmpty) {
      key = await db.customInsert(
        'INSERT INTO local_drafts (account_id, payload, draft_id, saved_at) VALUES (?, ?, ?, ?)',
        variables: _vars([message.accountId, payload, message.draftId, now]),
        updates: {db.localDrafts},
      );
    } else {
      key = existing.first.read<int>('id');
      await db.customUpdate(
        'UPDATE local_drafts SET payload = ?2, revision = revision + 1, saved_at = ?3, '
        'draft_id = coalesce(draft_id, ?4) WHERE id = ?1',
        variables: _vars([key, payload, now, message.draftId]),
        updates: {db.localDrafts},
      );
    }
    final draft = (await _localDraftWhere('id = ?1', [key]))!;
    if (draft.draftId == null) await _showLocalDraft(draft, fromEpochMs(now));
    return draft;
  });

  /// Puts [draft], which the server does not have yet, in the account's
  /// Drafts as a message of its own, with [date].
  Future<void> _showLocalDraft(LocalDraft draft, DateTime date) async {
    final m = draft.message!;
    final mailbox = await _select("SELECT id FROM mailboxes WHERE account_id = ?1 AND role = 'drafts' LIMIT 1", [
      draft.accountId,
    ]);
    if (mailbox.isEmpty) return;
    final id = LocalDraft.messageIdOf(draft.id);
    final snippet = m.textBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    await upsertMessages(draft.accountId, [
      Message(
        accountId: draft.accountId,
        id: id,
        threadId: m.threadId ?? id,
        subject: m.subject,
        from: m.from,
        to: m.to,
        cc: m.cc,
        bcc: m.bcc,
        date: date,
        snippet: snippet.length > 200 ? snippet.substring(0, 200) : snippet,
        isDraft: true,
        mailboxIds: {mailbox.first.read<String>('id')},
        attachments: [
          for (final (i, a) in m.attachments.indexed)
            AttachmentInfo(
              partId: '${i + 1}',
              filename: a.filename,
              mimeType: a.mimeType,
              size: a.bytes.length,
              contentId: a.contentId,
              isInline: a.contentId != null,
            ),
        ],
        inReplyTo: m.inReplyTo,
        references: m.references,
      ),
    ]);
    await saveBody(draft.accountId, id, MessageBody(text: m.textBody, html: m.htmlBody));
  }

  @override
  Future<LocalDraft?> localDraft(int id) => _localDraftWhere('id = ?1', [id]);

  @override
  Future<LocalDraft?> localDraftFor(String accountId, String draftId) =>
      _localDraftWhere('account_id = ?1 AND draft_id = ?2 AND payload IS NOT NULL', [accountId, draftId]);

  @override
  Future<List<LocalDraft>> localDrafts(String accountId) async => (await _select(
    'SELECT * FROM local_drafts WHERE account_id = ?1 ORDER BY id',
    [accountId],
  )).map(_localDraftFromRow).nonNulls.toList();

  @override
  Future<bool> markLocalDraftUploaded(int id, {required int revision, required String draftId}) async =>
      await db.customUpdate(
        'UPDATE local_drafts SET draft_id = ?2, uploaded_revision = max(uploaded_revision, ?3), uploaded_at = ?4 '
        'WHERE id = ?1',
        variables: _vars([id, draftId, revision, DateTime.now().millisecondsSinceEpoch]),
        updates: {db.localDrafts},
      ) >
      0;

  @override
  Future<LocalDraft?> takeLocalDraft(int id) => db.transaction(() async {
    final rows = await db.customWriteReturning(
      'DELETE FROM local_drafts WHERE id = ?1 AND payload IS NOT NULL RETURNING *',
      variables: _vars([id]),
      updates: {db.localDrafts},
      updateKind: UpdateKind.delete,
    );
    if (rows.isEmpty) return null;
    final draft = _localDraftFromRow(rows.first);
    await deleteMessages(rows.first.read<String>('account_id'), [LocalDraft.messageIdOf(id)]);
    return draft;
  });

  @override
  Future<void> discardLocalDraft(String accountId, {int? id, String? draftId}) => db.transaction(() async {
    final draft =
        (id == null ? null : await _localDraftWhere('id = ?1 AND payload IS NOT NULL', [id])) ??
        (draftId == null ? null : await localDraftFor(accountId, draftId));
    final serverId = draft?.draftId ?? draftId;
    if (draft != null) {
      await deleteMessages(draft.accountId, [LocalDraft.messageIdOf(draft.id)]);
      if (serverId == null) return deleteLocalDraft(draft.id);
      await db.customUpdate(
        'UPDATE local_drafts SET payload = NULL, draft_id = ?2 WHERE id = ?1',
        variables: _vars([draft.id, serverId]),
        updates: {db.localDrafts},
      );
    } else if (serverId != null) {
      await db.customInsert(
        'INSERT INTO local_drafts (account_id, draft_id, saved_at) VALUES (?, ?, ?)',
        variables: _vars([accountId, serverId, DateTime.now().millisecondsSinceEpoch]),
        updates: {db.localDrafts},
      );
    }
  });

  @override
  Future<void> deleteLocalDraft(int id) =>
      db.customUpdate('DELETE FROM local_drafts WHERE id = ?', variables: _vars([id]), updates: {db.localDrafts});

  @override
  Future<void> settleLocalDrafts(String accountId, {required DateTime uploadedBefore}) => db.transaction(() async {
    final shown = {
      for (final r in await _select(
        // The prefix as a range, so that the (account_id, id) index finds it.
        "SELECT id FROM messages WHERE account_id = ?1 AND id >= 'local-draft:' AND id < 'local-draft;'",
        [accountId],
      ))
        r.read<String>('id'),
    };
    final waiting = await _select(
      'SELECT * FROM local_drafts WHERE account_id = ?1 AND payload IS NOT NULL '
      'AND (draft_id IS NULL OR uploaded_at >= ?2)',
      [accountId, uploadedBefore.millisecondsSinceEpoch],
    );
    final keep = <String>{};
    for (final r in waiting) {
      final draft = _localDraftFromRow(r);
      if (draft == null) continue;
      final id = LocalDraft.messageIdOf(draft.id);
      if (shown.contains(id)) {
        keep.add(id);
      } else if (draft.draftId == null) {
        await _showLocalDraft(draft, fromEpochMs(r.read<int>('saved_at')));
      }
    }
    await deleteMessages(accountId, shown.difference(keep).toList());
  });

  @override
  Future<void> pruneLocalDrafts() => db.customUpdate(
    'DELETE FROM local_drafts WHERE payload IS NOT NULL AND uploaded_revision >= revision '
    // Shown until a sync brings the server's copy, and opened from there.
    'AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.account_id = local_drafts.account_id '
    "AND m.id = 'local-draft:' || local_drafts.id)",
    updates: {db.localDrafts},
  );

  // Settings -------------------------------------------------------------------

  @override
  Future<String?> readSetting(String key) async {
    final rows = await _select('SELECT value FROM settings WHERE "key" = ?1', [key]);
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      await db.customUpdate('DELETE FROM settings WHERE "key" = ?', variables: _vars([key]), updates: {db.settings});
    } else {
      await db.customUpdate(
        'INSERT INTO settings ("key", value) VALUES (?1, ?2) ON CONFLICT ("key") DO UPDATE SET value = excluded.value',
        variables: _vars([key, value]),
        updates: {db.settings},
      );
    }
  }

  @override
  Stream<String?> watchSetting(String key) => _query(
    'SELECT value FROM settings WHERE "key" = ?1',
    [key],
    {db.settings},
  ).watch().map((rows) => rows.isEmpty ? null : rows.first.read<String>('value')).distinct();
}
