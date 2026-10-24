import 'dart:async';

import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

/// Base time for test messages; message `n` minutes later is `at(n)`.
final base = DateTime.utc(2026, 3, 1, 9);

DateTime at(int minutes) => base.add(Duration(minutes: minutes));

Account account(String id, {int sortOrder = 0}) => Account(
  id: id,
  provider: 'gmail',
  email: '$id@example.com',
  displayName: 'Account $id',
  color: 0xFF336699,
  sortOrder: sortOrder,
);

/// Gmail-like system mailboxes.
List<Mailbox> gmailMailboxes(String accountId) => [
  Mailbox(accountId: accountId, id: 'INBOX', name: 'Inbox', role: MailboxRole.inbox, kind: MailboxKind.system),
  Mailbox(accountId: accountId, id: 'SENT', name: 'Sent', role: MailboxRole.sent, kind: MailboxKind.system),
  Mailbox(accountId: accountId, id: 'DRAFT', name: 'Drafts', role: MailboxRole.drafts, kind: MailboxKind.system),
  Mailbox(accountId: accountId, id: 'TRASH', name: 'Trash', role: MailboxRole.trash, kind: MailboxKind.system),
  Mailbox(accountId: accountId, id: 'SPAM', name: 'Spam', role: MailboxRole.junk, kind: MailboxKind.system),
  Mailbox(
    accountId: accountId,
    id: 'IMPORTANT',
    name: 'Important',
    role: MailboxRole.important,
    kind: MailboxKind.system,
  ),
  for (final (id, cat) in [
    ('CATEGORY_PERSONAL', MailCategory.primary),
    ('CATEGORY_SOCIAL', MailCategory.social),
    ('CATEGORY_PROMOTIONS', MailCategory.promotions),
    ('CATEGORY_UPDATES', MailCategory.updates),
    ('CATEGORY_FORUMS', MailCategory.forums),
  ])
    Mailbox(
      accountId: accountId,
      id: id,
      name: cat.name,
      role: MailboxRole.category,
      category: cat,
      kind: MailboxKind.system,
      hidden: true,
    ),
  Mailbox(accountId: accountId, id: 'Label_work', name: 'Work'),
];

Message msg(
  String id, {
  String account = 'a1',
  String? thread,
  String subject = 'Subject',
  Address? from,
  List<Address> to = const [],
  List<Address> cc = const [],
  DateTime? date,
  int minute = 0,
  String snippet = '',
  bool read = true,
  bool flagged = false,
  bool draft = false,
  Set<String> boxes = const {'INBOX'},
  List<AttachmentInfo> attachments = const [],
}) => Message(
  accountId: account,
  id: id,
  threadId: thread ?? 't-$id',
  subject: subject,
  from: from ?? const Address('ana@example.org', 'Ana Alvarez'),
  to: to,
  cc: cc,
  date: date ?? at(minute),
  snippet: snippet,
  isRead: read,
  isFlagged: flagged,
  isDraft: draft,
  mailboxIds: boxes,
  attachments: attachments,
);

const pdf = AttachmentInfo(partId: '2', filename: 'report.pdf', mimeType: 'application/pdf', size: 1000);
const inlineImage = AttachmentInfo(
  partId: '3',
  filename: 'logo.png',
  mimeType: 'image/png',
  size: 10,
  contentId: 'logo',
  isInline: true,
);

/// A store with accounts a1 (and a2) and Gmail mailboxes.
Future<DriftMailStore> newStore({bool twoAccounts = true}) async {
  final store = DriftMailStore.inMemory();
  await store.saveAccount(account('a1'));
  await store.replaceMailboxes('a1', gmailMailboxes('a1'));
  if (twoAccounts) {
    await store.saveAccount(account('a2', sortOrder: 1));
    await store.replaceMailboxes('a2', gmailMailboxes('a2'));
  }
  return store;
}

Future<List<ThreadSummary>> threads(MailStore store, ThreadFilter filter, {int limit = 300}) =>
    store.watchThreads(filter, limit: limit).first;

Future<List<String>> threadIds(MailStore store, ThreadFilter filter, {int limit = 300}) async => [
  for (final t in await threads(store, filter, limit: limit)) t.id,
];

Future<ThreadSummary?> summary(MailStore store, String account, String thread) async =>
    (await store.watchThread(account, thread).first)?.summary;

/// Records every event of [stream] until cancelled.
final class Recorder<T> {
  Recorder(Stream<T> stream) {
    _sub = stream.listen((e) {
      events.add(e);
      _waiters.removeWhere((w) {
        if (events.length >= w.$1) {
          w.$2.complete();
          return true;
        }
        return false;
      });
    });
  }

  final events = <T>[];
  late final StreamSubscription<T> _sub;
  final _waiters = <(int, Completer<void>)>[];

  T get last => events.last;

  /// Waits until at least [count] events were received.
  Future<void> waitFor(int count) {
    if (events.length >= count) return Future.value();
    final c = Completer<void>();
    _waiters.add((count, c));
    return c.future.timeout(const Duration(seconds: 5));
  }

  /// Lets pending stream queries run.
  static Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  Future<void> cancel() => _sub.cancel();
}
