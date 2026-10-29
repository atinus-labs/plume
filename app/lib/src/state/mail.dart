import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';

import 'navigation.dart';
import 'services.dart';
import 'settings.dart';

/// Identifies one message across accounts.
typedef MessageKey = ({String accountId, String messageId});

final accountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(storeProvider).watchAccounts());

/// Accounts by id, empty while loading.
final accountMapProvider = Provider<Map<String, Account>>((ref) {
  final accounts = ref.watch(accountsProvider).value ?? const [];
  return {for (final a in accounts) a.id: a};
});

final syncStatusProvider = StreamProvider<Map<String, AccountSyncStatus>>((ref) async* {
  final engine = ref.watch(engineProvider);
  yield engine.currentStatuses;
  yield* engine.statuses;
});

/// Mailboxes of one account, or of all accounts.
final mailboxesProvider = StreamProvider.family<List<Mailbox>, String?>(
    (ref, accountId) => ref.watch(storeProvider).watchMailboxes(accountId: accountId));

final threadsProvider = StreamProvider.autoDispose.family<List<ThreadSummary>, ThreadFilter>(
    (ref, filter) => ref.watch(storeProvider).watchThreads(filter));

final unreadCountProvider = StreamProvider.autoDispose.family<int, ThreadFilter>(
    (ref, filter) => ref.watch(storeProvider).watchUnreadCount(filter));

final threadDetailProvider = StreamProvider.autoDispose.family<ThreadDetail?, ThreadKey>(
    (ref, key) => ref.watch(storeProvider).watchThread(key.accountId, key.threadId));

/// A message body, downloading it first when it is not cached.
final bodyProvider = FutureProvider.autoDispose.family<MessageBody?, MessageKey>((ref, key) async {
  final store = ref.watch(storeProvider);
  final cached = await store.body(key.accountId, key.messageId);
  if (cached != null) return cached;
  await ref.watch(engineProvider).ensureBodies(key.accountId, [key.messageId]);
  return store.body(key.accountId, key.messageId);
});

/// Local full-text results for a query, scoped like the current view.
final localSearchProvider =
    FutureProvider.autoDispose.family<List<ThreadSummary>, ({String query, String? accountId})>((ref, args) async {
  return ref.watch(storeProvider).searchLocal(
        args.query,
        accountIds: args.accountId == null ? null : {args.accountId!},
      );
});

/// The threads the list pane shows: the current view, or search results.
final visibleThreadsProvider = Provider.autoDispose<AsyncValue<List<ThreadSummary>>>((ref) {
  final search = ref.watch(searchProvider);
  final view = ref.watch(viewProvider);
  if (search.active) {
    final server = search.serverResults;
    if (server != null) {
      return ref.watch(threadsProvider(ThreadSetFilter(server))).whenData((list) {
        final sorted = [...list]..sort((a, b) => b.lastDate.compareTo(a.lastDate));
        return sorted;
      });
    }
    return ref.watch(localSearchProvider((query: search.query.trim(), accountId: view.accountId)));
  }
  return ref.watch(threadsProvider(view.toFilter()));
});

/// Whether [accountId] files mail in folders (a message lives in exactly
/// one) rather than labels. Decides between "Move to" and label menus.
/// Re-evaluated with sync status because a provider may learn its server's
/// capabilities on first connect (Gmail over IMAP has labels).
final usesFoldersProvider = Provider.family<bool, String>((ref, accountId) {
  ref.watch(syncStatusProvider);
  return ref.watch(engineProvider).capabilitiesOf(accountId)?.labels == false;
});

/// Where conversations of [accountId] can be moved: Inbox, Archive and the
/// user's own folders.
final moveTargetsProvider = Provider.family<List<Mailbox>, String>((ref, accountId) {
  final mailboxes = ref.watch(mailboxesProvider(accountId)).value ?? const <Mailbox>[];
  return [
    ...mailboxes.where((m) => m.role == MailboxRole.inbox),
    ...mailboxes.where((m) => m.role == MailboxRole.archive),
    ...mailboxes.where((m) => m.kind == MailboxKind.user && m.role == null && !m.hidden),
  ];
});

/// Whether any connected account sorts mail into categories, to decide
/// whether to show the inbox category tabs.
final hasCategoriesProvider = Provider<bool>((ref) {
  final mailboxes = ref.watch(mailboxesProvider(null)).value ?? const [];
  return mailboxes.any((m) => m.role == MailboxRole.category);
});

/// The inbox tab the navigation opens: Primary while the category tabs
/// show, otherwise the whole inbox.
final inboxCategoryProvider = Provider<MailCategory?>((ref) =>
    ref.watch(hasCategoriesProvider) && ref.watch(settingsProvider).categoryTabs ? MailCategory.primary : null);
