import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';

/// Identifies a conversation across accounts.
typedef ThreadKey = ({String accountId, String threadId});

ThreadKey keyOf(ThreadSummary t) => (accountId: t.accountId, threadId: t.id);

/// The kinds of message lists the navigation offers.
enum ViewKind { inbox, starred, sent, drafts, archive, allMail, junk, trash, label }

/// A message list: a kind, optionally scoped to one account.
@immutable
final class MailView {
  const MailView(this.kind, {this.accountId, this.mailboxId, this.category});

  static const unifiedInbox = MailView(ViewKind.inbox);

  final ViewKind kind;

  /// Null for the unified view across accounts.
  final String? accountId;

  /// The label for [ViewKind.label].
  final String? mailboxId;

  /// Inbox category tab; null shows the whole inbox.
  final MailCategory? category;

  MailView withCategory(MailCategory? category) =>
      MailView(kind, accountId: accountId, mailboxId: mailboxId, category: category);

  MailView forAccount(String? accountId) =>
      MailView(kind, accountId: accountId, mailboxId: kind == ViewKind.label ? mailboxId : null, category: category);

  ThreadFilter toFilter() {
    final accounts = accountId == null ? null : {accountId!};
    return switch (kind) {
      ViewKind.inbox => RoleFilter(MailboxRole.inbox, accountIds: accounts, category: category),
      ViewKind.starred => FlaggedFilter(accountIds: accounts),
      ViewKind.sent => RoleFilter(MailboxRole.sent, accountIds: accounts),
      ViewKind.drafts => RoleFilter(MailboxRole.drafts, accountIds: accounts),
      ViewKind.archive => RoleFilter(MailboxRole.archive, accountIds: accounts),
      ViewKind.allMail => AllMailFilter(accountIds: accounts),
      ViewKind.junk => RoleFilter(MailboxRole.junk, accountIds: accounts),
      ViewKind.trash => RoleFilter(MailboxRole.trash, accountIds: accounts),
      ViewKind.label => MailboxFilter(accountId!, mailboxId!),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MailView &&
      other.kind == kind &&
      other.accountId == accountId &&
      other.mailboxId == mailboxId &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, accountId, mailboxId, category);
}

/// The list currently shown.
final viewProvider = NotifierProvider<ViewNotifier, MailView>(ViewNotifier.new);

class ViewNotifier extends Notifier<MailView> {
  @override
  MailView build() => const MailView(ViewKind.inbox, category: MailCategory.primary);

  void show(MailView view) {
    if (view == state) return;
    state = view;
    ref.read(openThreadProvider.notifier).close();
    ref.read(selectionProvider.notifier).clear();
    ref.read(searchProvider.notifier).clear();
  }
}

/// The conversation open in the reading pane.
final openThreadProvider = NotifierProvider<OpenThreadNotifier, ThreadKey?>(OpenThreadNotifier.new);

class OpenThreadNotifier extends Notifier<ThreadKey?> {
  @override
  ThreadKey? build() => null;

  void open(ThreadKey key) => state = key;
  void close() => state = null;
}

/// Threads selected for bulk actions, as `accountId/threadId` keys.
final selectionProvider = NotifierProvider<SelectionNotifier, Set<String>>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) => state = state.contains(key) ? ({...state}..remove(key)) : {...state, key};
  void setAll(Iterable<String> keys) => state = keys.toSet();
  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

/// Active search: the query and, once the server answered, the result set.
@immutable
final class SearchState {
  const SearchState({this.query = '', this.serverResults, this.searchingServer = false});

  final String query;

  /// Thread keys from the server search, or null while only local results
  /// are shown.
  final List<String>? serverResults;
  final bool searchingServer;

  bool get active => query.trim().isNotEmpty;
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

class SearchNotifier extends Notifier<SearchState> {
  int _generation = 0;

  @override
  SearchState build() => const SearchState();

  void setQuery(String query) {
    _generation++;
    state = SearchState(query: query);
  }

  /// Starts a server search; results arrive via [complete].
  int beginServerSearch() {
    state = SearchState(query: state.query, serverResults: state.serverResults, searchingServer: true);
    return ++_generation;
  }

  void complete(int generation, List<String> keys) {
    if (generation != _generation) return;
    state = SearchState(query: state.query, serverResults: keys);
  }

  void clear() {
    _generation++;
    if (state.active || state.serverResults != null) state = const SearchState();
  }
}

/// Whether the compact layout currently shows the reader instead of the
/// list (single-pane windows).
final compactReaderProvider = Provider<bool>((ref) => ref.watch(openThreadProvider) != null);
