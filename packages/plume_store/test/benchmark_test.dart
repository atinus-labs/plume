// Benchmark-style test: ~20k messages in ~8k threads across two accounts,
// stored in a file database on a background isolate (the production setup).
// Prints timings and query plans; the assertions use generous bounds so that
// the test is not flaky on slow machines. Exclude with `dart test -x benchmark`.
@Tags(['benchmark'])
library;

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:test/test.dart';

import 'support.dart';

const _accounts = ['work', 'home'];
const _threadsPerAccount = 4000;
const _messagesPerAccount = 10000;

final _words = [
  'meeting', 'budget', 'invoice', 'project', 'review', 'schedule', 'update', 'report', 'launch', 'design', //
  'quarterly', 'contract', 'travel', 'flight', 'hotel', 'dinner', 'birthday', 'party', 'newsletter', 'offer',
  'discount', 'order', 'shipped', 'delivery', 'receipt', 'payment', 'account', 'security', 'password', 'login',
  'team', 'offsite', 'roadmap', 'planning', 'hiring', 'interview', 'candidate', 'feedback', 'draft', 'proposal',
  for (var i = 0; i < 3000; i++) 'w${i.toRadixString(36)}x',
];

final _first = ['Ana', 'Ben', 'Chloé', 'Dmitri', 'Eva', 'Farid', 'Grace', 'Hiro', 'Ines', 'José', 'Kai', 'Lena'];
final _last = ['Alvarez', 'Brown', 'Chen', 'Dubois', 'Evans', 'Fischer', 'García', 'Huang', 'Ivanova', 'Jones'];

final class _Dataset {
  _Dataset(this.messages, this.mailboxes);

  final Map<String, List<Message>> messages;
  final Map<String, List<Mailbox>> mailboxes;
}

_Dataset _generate(Random rnd) {
  final contacts = [
    for (var i = 0; i < 2000; i++)
      Address(
        '${_first[i % _first.length].toLowerCase()}.$i@${['acme.com', 'mail.org', 'corp.io', 'shop.biz'][i % 4]}',
        '${_first[i % _first.length]} ${_last[(i ~/ 12) % _last.length]}',
      ),
  ];
  String sentence(int n) => [for (var i = 0; i < n; i++) _words[rnd.nextInt(_words.length)]].join(' ');
  final now = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
  const twoYears = 2 * 365 * 24 * 3600 * 1000;

  final messages = <String, List<Message>>{};
  final mailboxes = <String, List<Mailbox>>{};
  for (final account in _accounts) {
    final me = Address('me@$account.example', 'Me');
    mailboxes[account] = [
      ...gmailMailboxes(account),
      for (final l in ['Family', 'Receipts', 'Travel', 'Projects'])
        Mailbox(accountId: account, id: 'Label_$l', name: l),
    ];
    // Thread sizes: mostly singletons, a long tail of conversations.
    final sizes = <int>[];
    var total = 0;
    while (sizes.length < _threadsPerAccount) {
      final r = rnd.nextDouble();
      final size = r < 0.6
          ? 1
          : r < 0.8
          ? 2 + rnd.nextInt(2)
          : r < 0.95
          ? 4 + rnd.nextInt(3)
          : 7 + rnd.nextInt(9);
      sizes.add(size);
      total += size;
    }
    // Scale to the target message count.
    var i = 0;
    while (total > _messagesPerAccount) {
      if (sizes[i % sizes.length] > 1) {
        sizes[i % sizes.length]--;
        total--;
      }
      i++;
    }
    while (total < _messagesPerAccount) {
      sizes[rnd.nextInt(sizes.length)]++;
      total++;
    }

    final list = <Message>[];
    for (var t = 0; t < sizes.length; t++) {
      final threadId = '${account[0]}t${t.toRadixString(16).padLeft(6, '0')}';
      final start = now - (rnd.nextDouble() * twoYears).round();
      final age = (now - start) / twoYears;
      final r = rnd.nextDouble();
      final location = r < 0.03
          ? 'TRASH'
          : r < 0.05
          ? 'SPAM'
          : (r < 0.40 ? 'INBOX' : null);
      final c = rnd.nextDouble();
      final category = c < 0.25
          ? 'CATEGORY_PERSONAL'
          : c < 0.45
          ? null
          : c < 0.60
          ? 'CATEGORY_SOCIAL'
          : c < 0.85
          ? 'CATEGORY_PROMOTIONS'
          : c < 0.97
          ? 'CATEGORY_UPDATES'
          : 'CATEGORY_FORUMS';
      final label = rnd.nextDouble() < 0.12 ? mailboxes[account]![12 + rnd.nextInt(4)].id : null;
      final important = rnd.nextDouble() < 0.2;
      final subject = sentence(3 + rnd.nextInt(5));
      final people = [for (var k = 0; k < 1 + rnd.nextInt(3); k++) contacts[rnd.nextInt(contacts.length)]];
      for (var m = 0; m < sizes[t]; m++) {
        final mine = m > 0 && rnd.nextDouble() < 0.3;
        final boxes = <String>{
          if (mine) 'SENT' else ...[?location, ?category],
          ?label,
          if (important) 'IMPORTANT',
        };
        list.add(
          Message(
            accountId: account,
            id: '$threadId-$m',
            threadId: threadId,
            subject: m == 0 ? subject : 'Re: $subject',
            from: mine ? me : people[m % people.length],
            to: mine ? people : [me],
            cc: rnd.nextDouble() < 0.2 ? [contacts[rnd.nextInt(contacts.length)]] : const [],
            date: DateTime.fromMillisecondsSinceEpoch(start + m * (rnd.nextDouble() * 3 * 24 * 3600 * 1000).round()),
            snippet: sentence(12 + rnd.nextInt(10)),
            // Recent inbox mail is more often unread.
            isRead: !(location == 'INBOX' && !mine && rnd.nextDouble() < (age < 0.05 ? 0.6 : 0.08)),
            isFlagged: rnd.nextDouble() < 0.03,
            mailboxIds: boxes,
            attachments: rnd.nextDouble() < 0.1 ? const [pdf] : const [],
            messageIdHeader: '<$threadId-$m@$account.example>',
            size: 2000 + rnd.nextInt(50000),
          ),
        );
      }
    }
    messages[account] = list;
  }
  return _Dataset(messages, mailboxes);
}

double _ms(Duration d) => d.inMicroseconds / 1000;

Future<Duration> _time(Future<void> Function() action) async {
  final sw = Stopwatch()..start();
  await action();
  return sw.elapsed;
}

/// Median and best of [runs] timings of [action].
Future<(double, double)> _measure(int runs, Future<void> Function(int run) action) async {
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    times.add(_ms(await _time(() => action(i))));
    // Let drift drop cached stream results so each run hits SQLite.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  times.sort();
  return (times[times.length ~/ 2], times.first);
}

void main() {
  late Directory dir;
  late DriftMailStore store;
  late _Dataset data;
  final results = <String, String>{};

  void report(String name, (double, double) t, {double? target}) {
    final line =
        'median ${t.$1.toStringAsFixed(2)} ms, best ${t.$2.toStringAsFixed(2)} ms'
        '${target == null ? '' : ' (target < $target ms)'}';
    results[name] = line;
    print('$name: $line');
  }

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('plume_bench');
    store = DriftMailStore.open('${dir.path}/mail.sqlite');
    data = _generate(Random(42));
    for (final a in _accounts) {
      await store.saveAccount(account(a, sortOrder: _accounts.indexOf(a)));
      await store.replaceMailboxes(a, data.mailboxes[a]!);
    }
    final load = Stopwatch()..start();
    var count = 0;
    for (final a in _accounts) {
      final list = data.messages[a]!;
      // The last 500 of each account are kept for the insert benchmark.
      for (var i = 0; i < list.length - 500; i += 500) {
        final batch = list.sublist(i, min(i + 500, list.length - 500));
        await store.upsertMessages(a, batch);
        count += batch.length;
      }
    }
    final stats = await store.db
        .customSelect(
          'SELECT (SELECT count(*) FROM messages) AS m, (SELECT count(*) FROM threads) AS t, '
          '(SELECT count(*) FROM thread_mailboxes) AS tm',
        )
        .getSingle();
    print(
      'Initial load of $count messages: ${load.elapsedMilliseconds} ms '
      '(${(load.elapsedMicroseconds / count).toStringAsFixed(1)} µs/message); '
      'rows: ${stats.data}',
    );
  });

  tearDownAll(() async {
    await store.close();
    final size = File('${dir.path}/mail.sqlite').lengthSync();
    print('Database file: ${(size / 1024 / 1024).toStringAsFixed(1)} MB (before WAL checkpoint)');
    await dir.delete(recursive: true);
    print('\nSummary');
    results.forEach((k, v) => print('  $k: $v'));
  });

  test('upsertMessages of 500', () async {
    final fresh = data.messages['work']!.sublist(_messagesPerAccount - 500);
    final insert = _ms(await _time(() => store.upsertMessages('work', fresh)));
    results['upsert 500 new'] = '${insert.toStringAsFixed(1)} ms (target < 300 ms)';
    print('upsert 500 new messages: ${insert.toStringAsFixed(1)} ms');

    final existing = data.messages['home']!.sublist(1000, 1500);
    final changed = [for (final m in existing) m.copyWith(isRead: !m.isRead)];
    final update = _ms(await _time(() => store.upsertMessages('home', changed)));
    results['upsert 500 existing'] = '${update.toStringAsFixed(1)} ms';
    print('upsert 500 existing messages (resync): ${update.toStringAsFixed(1)} ms');
    expect(insert, lessThan(1500));
    expect(update, lessThan(1500));
  });

  test('list queries', () async {
    const inbox = RoleFilter(MailboxRole.inbox, accountIds: {'work'});
    const unified = RoleFilter(MailboxRole.inbox);
    const primary = RoleFilter(MailboxRole.inbox, category: MailCategory.primary);
    const label = MailboxFilter('work', 'Label_Projects');
    const flagged = FlaggedFilter();
    const all = AllMailFilter();

    final firstInbox = await threads(store, inbox);
    expect(firstInbox, hasLength(300));
    final unifiedList = await threads(store, unified);
    expect(unifiedList.map((t) => t.accountId).toSet(), {'work', 'home'});

    for (final (name, filter, target) in [
      ('watchThreads(RoleFilter(inbox)) first emission', inbox as ThreadFilter, 15.0),
      ('unified inbox first emission', unified, 15.0),
      ('unified primary inbox first emission', primary, 15.0),
      ('label first emission', label, null),
      ('flagged (all accounts) first emission', flagged, null),
      ('all mail (all accounts) first emission', all, null),
    ]) {
      final t = await _measure(9, (_) => store.watchThreads(filter).first);
      report(name, t, target: target);
      expect(t.$1, lessThan(150));
    }

    for (final (name, filter) in [
      ('unread count unified inbox', unified as ThreadFilter),
      ('unread count unified primary', primary),
    ]) {
      report(name, await _measure(9, (_) => store.watchUnreadCount(filter).first));
    }

    // Raw SQL time on the database isolate, without stream plumbing.
    for (final (name, filter) in [('inbox SQL', inbox as ThreadFilter), ('unified inbox SQL', unified)]) {
      final q = await store.debugThreadQuery(filter);
      report(
        name,
        await _measure(9, (_) => store.db.customSelect(q.sql, variables: [for (final a in q.args) Variable(a)]).get()),
      );
    }
  });

  test('list and count queries are index-driven', () async {
    for (final filter in [
      const RoleFilter(MailboxRole.inbox, accountIds: {'work'}),
      const RoleFilter(MailboxRole.inbox),
      const RoleFilter(MailboxRole.inbox, category: MailCategory.primary),
      const RoleFilter(MailboxRole.inbox, category: MailCategory.social),
      const FlaggedFilter(),
      const AllMailFilter(),
    ]) {
      for (final count in [false, true]) {
        final q = await store.debugThreadQuery(filter, count: count);
        final plan =
            (await store.db
                    .customSelect('EXPLAIN QUERY PLAN ${q.sql}', variables: [for (final a in q.args) Variable(a)])
                    .get())
                .map((r) => r.read<String>('detail'))
                .toList();
        print(
          '${count ? 'count' : 'list'} ${filter.runtimeType}${filter is RoleFilter ? '(${filter.category?.name ?? ''})' : ''}:\n'
          '  ${plan.join('\n  ')}',
        );
        // No full scans: every access to the big tables goes through an index.
        for (final line in plan) {
          expect(line, isNot(matches(RegExp(r'^SCAN (tm|t|x|threads|thread_mailboxes)$'))), reason: plan.join('\n'));
          if (line.startsWith('SCAN tm') || line.startsWith('SCAN t ')) {
            expect(line, contains('INDEX'), reason: plan.join('\n'));
          }
        }
        if (!count) {
          // Each branch reads its rows in index order (only the merge sorts).
          final sorts = plan.where((l) => l.contains('TEMP B-TREE')).length;
          expect(sorts, lessThanOrEqualTo(1), reason: plan.join('\n'));
        }
      }
    }
  });

  test('searchLocal', () async {
    for (final (name, query) in [
      ('search common word', 'meeting'),
      ('search two words', 'budget review'),
      ('search prefix (typing)', 'quarter'),
      ('search vocabulary word', 'w2bx'),
      ('search from: + is:unread', 'from:ana is:unread'),
      ('search operators only', 'is:unread has:attachment'),
    ]) {
      final results = await store.searchLocal(query);
      final t = await _measure(7, (_) => store.searchLocal(query));
      report('$name "$query" (${results.length} threads)', t);
      expect(t.$1, lessThan(500));
    }
    expect(await store.searchLocal('meeting'), isNotEmpty);
  });

  test('applyLocalMutation on 50 threads', () async {
    final list = await threads(store, const RoleFilter(MailboxRole.inbox, accountIds: {'work'}));
    final ids = [for (final t in list.take(50)) t.id];
    final rec = Recorder(store.watchThreads(const RoleFilter(MailboxRole.inbox, accountIds: {'work'})));
    await rec.waitFor(1);

    final read = _ms(
      await _time(
        () => store.applyLocalMutation('work', OperationScope.thread, ids, const LocalMutation(setRead: true)),
      ),
    );
    final sw = Stopwatch()..start();
    await rec.waitFor(2);
    final visible = _ms(sw.elapsed);
    expect(rec.last.take(50).every((t) => t.unreadCount == 0), isTrue);

    final archive = _ms(
      await _time(
        () => store.applyLocalMutation(
          'work',
          OperationScope.thread,
          ids,
          const LocalMutation(removeMailboxes: {'INBOX'}),
        ),
      ),
    );
    await rec.waitFor(3);
    expect(rec.last.map((t) => t.id).toSet().intersection(ids.toSet()), isEmpty);
    await rec.cancel();

    results['applyLocalMutation mark read 50 threads'] =
        '${read.toStringAsFixed(1)} ms (+${visible.toStringAsFixed(1)} ms until the list re-emits)';
    results['applyLocalMutation archive 50 threads'] = '${archive.toStringAsFixed(1)} ms';
    print('mark read 50 threads: ${read.toStringAsFixed(1)} ms, list updated ${visible.toStringAsFixed(1)} ms later');
    print('archive 50 threads: ${archive.toStringAsFixed(1)} ms');
    expect(read, lessThan(500));
    expect(archive, lessThan(500));
  });

  test('body save and prefetch queries', () async {
    final ids = await store.recentMessagesWithoutBody('work', 'INBOX');
    expect(ids, hasLength(50));
    final html =
        '<html><body>${'<p>Hello <b>world</b> &amp; friends, see the quarterly numbers.</p>' * 400}</body></html>';
    final save = await _measure(5, (i) => store.saveBody('work', ids[i], MessageBody(html: html, text: 'x')));
    report('saveBody (~${(html.length / 1024).round()} KB html, indexed)', save);
    report(
      'recentMessagesWithoutBody(INBOX, 50)',
      await _measure(7, (_) => store.recentMessagesWithoutBody('work', 'INBOX')),
    );
    report('suggestAddresses("ana")', await _measure(7, (_) => store.suggestAddresses('ana')));
  });
}
