import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:plume_core/plume_core.dart';

import 'codecs.dart';

/// The accounts, in display order, and their mailboxes that carry a role or
/// a category: everything needed to resolve role-based filters.
final class MailboxDirectory {
  const MailboxDirectory(this.accountIds, this.special);

  /// SQL producing the rows [MailboxDirectory.fromRows] expects.
  static const sql = '''
SELECT a.id AS account_id, b.id AS mailbox_id, b.role, b.category
FROM accounts a
LEFT JOIN mailboxes b ON b.account_id = a.id AND (b.role IS NOT NULL OR b.category IS NOT NULL)
ORDER BY a.sort_order, a.id, b.sort_order, b.id''';

  factory MailboxDirectory.fromRows(
    Iterable<({String accountId, String? mailboxId, String? role, String? category})> rows,
  ) {
    final accounts = <String>[];
    final special = <String, List<SpecialMailbox>>{};
    for (final r in rows) {
      if (accounts.isEmpty || accounts.last != r.accountId) accounts.add(r.accountId);
      final id = r.mailboxId;
      if (id != null) {
        (special[r.accountId] ??= []).add(SpecialMailbox(id, r.role, r.category));
      }
    }
    return MailboxDirectory(accounts, special);
  }

  final List<String> accountIds;
  final Map<String, List<SpecialMailbox>> special;

  Iterable<String> accountsIn(Set<String>? only) => only == null ? accountIds : accountIds.where(only.contains);

  List<SpecialMailbox> of(String accountId) => special[accountId] ?? const [];
}

final class SpecialMailbox {
  const SpecialMailbox(this.id, this.role, this.category);

  final String id;
  final String? role;
  final String? category;
}

/// One account's contribution to a thread list. Each branch is evaluated
/// separately in index order with its own LIMIT, then the branches are
/// merged, so unified views stay index-only however large each account is.
sealed class Branch {
  const Branch(this.accountId);

  final String accountId;
}

/// Threads in [mailboxId], optionally also in [alsoIn] and in none of
/// [exclude].
final class MailboxBranch extends Branch {
  const MailboxBranch(super.accountId, this.mailboxId, {this.alsoIn, this.exclude = const []});

  final String mailboxId;
  final String? alsoIn;
  final List<String> exclude;

  @override
  bool operator ==(Object other) =>
      other is MailboxBranch &&
      other.accountId == accountId &&
      other.mailboxId == mailboxId &&
      other.alsoIn == alsoIn &&
      const ListEquality<String>().equals(other.exclude, exclude);

  @override
  int get hashCode => Object.hash(accountId, mailboxId, alsoIn, Object.hashAll(exclude));
}

/// Threads with a message outside trash and junk, optionally only flagged
/// ones.
final class ActiveBranch extends Branch {
  const ActiveBranch(super.accountId, {required this.flaggedOnly});

  final bool flaggedOnly;

  @override
  bool operator ==(Object other) =>
      other is ActiveBranch && other.accountId == accountId && other.flaggedOnly == flaggedOnly;

  @override
  int get hashCode => Object.hash(accountId, flaggedOnly);
}

/// A SQL statement with its arguments.
final class SqlQuery {
  const SqlQuery(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}

/// A resolved [ThreadFilter]: either per-account [branches] or an explicit
/// list of thread [keys].
final class ThreadPlan {
  const ThreadPlan.branches(this.branches) : keys = null;
  const ThreadPlan.keys(List<(String, String)> this.keys) : branches = const [];

  final List<Branch> branches;
  final List<(String, String)>? keys;

  bool get isEmpty => keys == null ? branches.isEmpty : keys!.isEmpty;

  /// Resolves [filter]. [directory] is required for role, flagged and all-mail
  /// filters (see [needsDirectory]).
  static ThreadPlan resolve(ThreadFilter filter, MailboxDirectory? directory) {
    switch (filter) {
      case MailboxFilter(:final accountId, :final mailboxId, :final alsoIn):
        return ThreadPlan.branches([MailboxBranch(accountId, mailboxId, alsoIn: alsoIn)]);
      case ThreadSetFilter(:final threadKeys):
        final seen = <String>{};
        final keys = <(String, String)>[];
        for (final key in threadKeys) {
          final slash = key.indexOf('/');
          if (slash <= 0 || !seen.add(key)) continue;
          keys.add((key.substring(0, slash), key.substring(slash + 1)));
        }
        return ThreadPlan.keys(keys);
      case FlaggedFilter(:final accountIds):
        return ThreadPlan.branches([
          for (final a in directory!.accountsIn(accountIds)) ActiveBranch(a, flaggedOnly: true),
        ]);
      case AllMailFilter(:final accountIds):
        return ThreadPlan.branches([
          for (final a in directory!.accountsIn(accountIds)) ActiveBranch(a, flaggedOnly: false),
        ]);
      case RoleFilter(:final role, :final category, :final accountIds):
        final branches = <Branch>[];
        for (final account in directory!.accountsIn(accountIds)) {
          final branch = _roleBranch(account, directory.of(account), role, category);
          if (branch != null) branches.add(branch);
        }
        return ThreadPlan.branches(branches);
    }
  }

  static bool needsDirectory(ThreadFilter filter) => filter is! MailboxFilter && filter is! ThreadSetFilter;

  static Branch? _roleBranch(String account, List<SpecialMailbox> boxes, MailboxRole role, MailCategory? category) {
    if (role == MailboxRole.category) {
      // The category mailbox itself (e.g. Promotions, including archived).
      final box = boxes.firstWhereOrNull(
        (b) => b.role == MailboxRole.category.name && (category == null || b.category == category.name),
      );
      return box == null ? null : MailboxBranch(account, box.id);
    }
    final base = boxes.firstWhereOrNull((b) => b.role == role.name);
    if (base == null) return null;
    if (category == null) return MailboxBranch(account, base.id);
    if (category == MailCategory.primary) {
      // Gmail does not reliably label primary mail, so Primary is "in none of
      // the other categories".
      final others = [
        for (final b in boxes)
          if (b.category != null && b.category != MailCategory.primary.name && b.id != base.id) b.id,
      ];
      return MailboxBranch(account, base.id, exclude: others);
    }
    final box = boxes.firstWhereOrNull((b) => b.category == category.name);
    if (box == null) return null;
    return box.id == base.id ? MailboxBranch(account, base.id) : MailboxBranch(account, base.id, alsoIn: box.id);
  }

  /// Thread rows (see [threadColumns]) newest first, at most [limit].
  SqlQuery listQuery(int limit) {
    if (keys case final keys?) {
      return SqlQuery(
        'SELECT $threadColumns FROM json_each(?1) k '
        'JOIN threads t ON t.account_id = k.value ->> 0 AND t.id = k.value ->> 1 '
        'ORDER BY k.key LIMIT ?2',
        [
          jsonEncode([
            for (final (a, t) in keys) [a, t],
          ]),
          limit,
        ],
      );
    }
    final args = <Object?>[];
    final parts = [for (final b in branches) _branchList(b, args, limit)];
    final source = parts.length == 1 ? parts.single : parts.map((p) => 'SELECT * FROM ($p)').join(' UNION ALL ');
    args.add(limit);
    return SqlQuery(
      'SELECT $threadColumns FROM ($source) k '
      'JOIN threads t ON t.account_id = k.account_id AND t.id = k.thread_id '
      'ORDER BY k.last_date DESC, k.thread_id, k.account_id LIMIT ?',
      args,
    );
  }

  /// A single row with column `c`: the number of unread threads.
  SqlQuery countQuery() {
    if (keys case final keys?) {
      return SqlQuery(
        'SELECT COUNT(*) AS c FROM json_each(?1) k '
        'JOIN threads t ON t.account_id = k.value ->> 0 AND t.id = k.value ->> 1 '
        'WHERE t.unread_count > 0',
        [
          jsonEncode([
            for (final (a, t) in keys) [a, t],
          ]),
        ],
      );
    }
    final args = <Object?>[];
    final parts = [for (final b in branches) '(${_branchCount(b, args)})'];
    return SqlQuery('SELECT ${parts.join(' + ')} AS c', args);
  }

  static String _branchList(Branch b, List<Object?> args, int limit) {
    switch (b) {
      case MailboxBranch():
        final where = _mailboxWhere(b, args);
        args.add(limit);
        return 'SELECT tm.account_id, tm.thread_id, tm.last_date FROM thread_mailboxes tm '
            'WHERE $where ORDER BY tm.last_date DESC, tm.thread_id LIMIT ?';
      case ActiveBranch():
        args
          ..add(b.accountId)
          ..add(limit);
        return 'SELECT t.account_id, t.id AS thread_id, t.last_date FROM threads t '
            'WHERE t.account_id = ? AND ${b.flaggedOnly ? 't.flagged = 1 AND ' : ''}t.active_count > 0 '
            'ORDER BY t.last_date DESC, t.id LIMIT ?';
    }
  }

  static String _branchCount(Branch b, List<Object?> args) {
    switch (b) {
      case MailboxBranch():
        final where = _mailboxWhere(b, args);
        return 'SELECT COUNT(*) FROM thread_mailboxes tm WHERE $where AND tm.unread = 1';
      case ActiveBranch():
        args.add(b.accountId);
        return 'SELECT COUNT(*) FROM threads t '
            'WHERE t.account_id = ? AND ${b.flaggedOnly ? 't.flagged = 1 AND ' : ''}t.active_count > 0 '
            'AND t.unread_count > 0';
    }
  }

  static String _mailboxWhere(MailboxBranch b, List<Object?> args) {
    final where = StringBuffer('tm.account_id = ? AND tm.mailbox_id = ?');
    args
      ..add(b.accountId)
      ..add(b.mailboxId);
    if (b.alsoIn case final also?) {
      where.write(
        ' AND EXISTS (SELECT 1 FROM thread_mailboxes x WHERE x.account_id = tm.account_id '
        'AND x.thread_id = tm.thread_id AND x.mailbox_id = ?)',
      );
      args.add(also);
    }
    if (b.exclude.isNotEmpty) {
      where.write(
        ' AND NOT EXISTS (SELECT 1 FROM thread_mailboxes x WHERE x.account_id = tm.account_id '
        'AND x.thread_id = tm.thread_id AND x.mailbox_id IN (${List.filled(b.exclude.length, '?').join(', ')}))',
      );
      args.addAll(b.exclude);
    }
    return where.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ThreadPlan &&
      const ListEquality<Branch>().equals(other.branches, branches) &&
      const ListEquality<(String, String)>().equals(other.keys, keys);

  @override
  int get hashCode => Object.hash(Object.hashAll(branches), keys == null ? null : Object.hashAll(keys!));
}
