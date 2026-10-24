import 'mailbox.dart';

/// What a message list shows. Filters that omit `accountIds` span every
/// account, which is how the unified views work.
sealed class ThreadFilter {
  const ThreadFilter();

  /// Accounts the filter is limited to, or null for all accounts.
  Set<String>? get accountIds;
}

/// Threads carrying a specific provider mailbox (label/folder), optionally
/// intersected with a second one (Gmail inbox ∩ Promotions).
final class MailboxFilter extends ThreadFilter {
  const MailboxFilter(this.accountId, this.mailboxId, {this.alsoIn});

  final String accountId;
  final String mailboxId;
  final String? alsoIn;

  @override
  Set<String> get accountIds => {accountId};

  @override
  bool operator ==(Object other) =>
      other is MailboxFilter && other.accountId == accountId && other.mailboxId == mailboxId && other.alsoIn == alsoIn;

  @override
  int get hashCode => Object.hash(accountId, mailboxId, alsoIn);
}

/// Threads in the mailbox that has [role] in each account. With a
/// [category], only threads in that category (e.g. the Primary inbox).
final class RoleFilter extends ThreadFilter {
  const RoleFilter(this.role, {this.accountIds, this.category});

  final MailboxRole role;
  final MailCategory? category;

  @override
  final Set<String>? accountIds;

  @override
  bool operator ==(Object other) =>
      other is RoleFilter &&
      other.role == role &&
      other.category == category &&
      _sameSet(other.accountIds, accountIds);

  @override
  int get hashCode => Object.hash(role, category, accountIds?.length);
}

/// Starred / flagged threads.
final class FlaggedFilter extends ThreadFilter {
  const FlaggedFilter({this.accountIds});

  @override
  final Set<String>? accountIds;

  @override
  bool operator ==(Object other) => other is FlaggedFilter && _sameSet(other.accountIds, accountIds);

  @override
  int get hashCode => Object.hash(FlaggedFilter, accountIds?.length);
}

/// Everything except trash and junk.
final class AllMailFilter extends ThreadFilter {
  const AllMailFilter({this.accountIds});

  @override
  final Set<String>? accountIds;

  @override
  bool operator ==(Object other) => other is AllMailFilter && _sameSet(other.accountIds, accountIds);

  @override
  int get hashCode => Object.hash(AllMailFilter, accountIds?.length);
}

/// An explicit result set, used for server-side search results.
final class ThreadSetFilter extends ThreadFilter {
  const ThreadSetFilter(this.threadKeys);

  /// `accountId/threadId` keys, in result order.
  final List<String> threadKeys;

  @override
  Set<String>? get accountIds => threadKeys.map((k) => k.substring(0, k.indexOf('/'))).toSet();

  @override
  bool operator ==(Object other) {
    if (other is! ThreadSetFilter || other.threadKeys.length != threadKeys.length) return false;
    for (var i = 0; i < threadKeys.length; i++) {
      if (other.threadKeys[i] != threadKeys[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(threadKeys);
}

bool _sameSet(Set<String>? a, Set<String>? b) {
  if (a == null || b == null) return a == b;
  return a.length == b.length && a.containsAll(b);
}
