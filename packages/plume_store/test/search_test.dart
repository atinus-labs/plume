import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';
import 'package:plume_store/src/search_query.dart';
import 'package:test/test.dart';

import 'support.dart';

const ana = Address('ana@example.org', 'Ana Álvarez');
const ben = Address('ben@corp.io', 'Ben Brown');
const me = Address('a1@example.com', 'Me');

void main() {
  group('htmlToText', () {
    test('drops tags, scripts, styles and comments', () {
      expect(
        htmlToText(
          '<html><head><title>T</title><style>p{color:red}</style></head>'
          '<body><p>Hello <b>wor</b>ld</p><!-- hidden --><script>var x = "<p>";</script><div>Bye</div></body></html>',
        ),
        'Hello world\nBye',
      );
    });

    test('decodes entities', () {
      expect(
        htmlToText('Fish &amp; Chips &lt;3 &quot;q&quot; &#39;s&#x27; caf&eacute; &euro;5&nbsp;now &hellip;'),
        'Fish & Chips <3 "q" \'s\' café €5 now …',
      );
      expect(htmlToText('AT&T &unknown; &#8217; &#150;'), 'AT&T &unknown; ’ –');
      expect(decodeHtmlEntities('a&amp;b &copy'), 'a&b ©');
    });

    test('block tags separate words, inline tags do not', () {
      expect(htmlToText('one<br>two<td>three</td><span>fo</span>ur'), 'one\ntwo\nthree\nfour');
    });

    test('collapses whitespace and drops zero-width padding', () {
      expect(htmlToText('  a \n\t b &zwnj;&nbsp;&zwnj;&nbsp; c​­x  '), 'a b cx');
    });

    test('quoted > inside attributes and stray <', () {
      expect(htmlToText('<a title="a > b" href=\'x>y\'>link</a> 1 < 2'), 'link 1 < 2');
    });

    test('caps the output', () {
      expect(htmlToText('<p>${'word ' * 1000}</p>', maxLength: 50).length, lessThanOrEqualTo(55));
    });
  });

  group('SearchQuery.parse', () {
    test('plain words, last one prefix matched', () {
      expect(SearchQuery.parse('budget meet').match, '"budget" "meet"*');
      expect(SearchQuery.parse('budget meet ').match, '"budget" "meet"');
      expect(SearchQuery.parse('a').match, '"a"');
    });

    test('phrases and operators', () {
      final q = SearchQuery.parse(
        '"weekly report" from:ana to:"Ben Brown" subject:plan has:attachment is:unread '
        'is:starred in:spam label:Work category:promotions',
      );
      expect(q.match, '"weekly report" {sender} : "ana" {recipients} : "Ben Brown" {subject} : "plan"');
      expect(q.hasAttachment, isTrue);
      expect(q.isRead, isFalse);
      expect(q.flagged, isTrue);
      expect(q.mailboxes, ['junk', 'work']);
      expect(q.categories, ['promotions']);
      expect(q.includesTrashOrJunk, isTrue);
    });

    test('negation, unknown operators, unclosed quotes and junk', () {
      final q = SearchQuery.parse('-spam -from:bob foo:bar "unclosed phr');
      expect(q.match, '"foo:bar" "unclosed phr"*');
      expect(q.exclude, '"spam" OR {sender} : "bob"');
      expect(SearchQuery.parse('" * ( ) :').isEmpty, isTrue);
      expect(SearchQuery.parse('say "hi""there"').match, '"say" "hi" "there"');
      expect(SearchQuery.parse('o"neil').match, '"o""neil"*');
    });
  });

  group('searchLocal', () {
    late DriftMailStore store;

    setUp(() async {
      store = await newStore();
      await store.upsertMessages('a1', [
        msg(
          'm1',
          thread: 't1',
          subject: 'Quarterly budget review',
          from: ana,
          to: const [me],
          minute: 1,
          snippet: 'Numbers attached for the meeting',
          attachments: [pdf],
          read: false,
        ),
        msg(
          'm2',
          thread: 't1',
          subject: 'Re: Quarterly budget review',
          from: me,
          to: const [ana],
          minute: 2,
          snippet: 'Thanks, looks good',
          boxes: {'SENT'},
        ),
        msg(
          'm3',
          thread: 't2',
          subject: 'Lunch?',
          from: ben,
          to: const [me],
          minute: 3,
          snippet: 'Café on Friday',
          flagged: true,
        ),
        msg(
          'm4',
          thread: 't3',
          subject: 'Budget spam',
          from: const Address('spammer@bad.biz'),
          minute: 4,
          snippet: 'cheap budget',
          boxes: {'SPAM'},
        ),
        msg(
          'm5',
          thread: 't4',
          subject: 'Notes',
          from: ben,
          cc: const [ana],
          minute: 5,
          snippet: 'see body',
          boxes: {'Label_work'},
        ),
      ]);
      await store.upsertMessages('a2', [
        msg('n1', account: 'a2', thread: 'u1', subject: 'Budget for a2', from: ben, minute: 6, snippet: 'other'),
      ]);
      await store.saveBody('a1', 'm5', const MessageBody(html: '<p>The <b>xylophone</b> concert&nbsp;tickets</p>'));
    });
    tearDown(() => store.close());

    Future<List<String>> search(String q, {Set<String>? accounts}) async => [
      for (final t in await store.searchLocal(q, accountIds: accounts)) t.key,
    ];

    test('words match subject, snippet, names and emails', () async {
      expect(await search('quarterly'), ['a1/t1']);
      expect(await search('numbers meeting'), ['a1/t1']);
      expect(await search('alvarez'), unorderedEquals(['a1/t1', 'a1/t4']));
      expect(await search('corp.io'), unorderedEquals(['a1/t2', 'a1/t4', 'a2/u1']));
      expect(await search('nothinglikethis'), isEmpty);
    });

    test('ranking: bm25 then recency; one result per thread', () async {
      final results = await search('budget');
      // Subject hits rank above recency; spam is excluded by default.
      expect(results.toSet(), {'a1/t1', 'a2/u1'});
      expect(results, hasLength(2));
    });

    test('prefix matching of the last word and diacritics folding', () async {
      expect(await search('quart'), ['a1/t1']);
      expect(await search('quart '), isEmpty);
      expect(await search('cafe'), ['a1/t2']);
      expect(await search('CAFÉ'), ['a1/t2']);
    });

    test('body text is indexed when saved, html stripped', () async {
      expect(await search('xylophone'), ['a1/t4']);
      expect(await search('concert tickets'), ['a1/t4']);
      expect(await search('"xylophone concert"'), ['a1/t4']);
      expect(await search('nbsp'), isEmpty);
      await store.saveBody('a1', 'm5', const MessageBody(text: 'marimba only'));
      expect(await search('xylophone'), isEmpty);
      expect(await search('marimba'), ['a1/t4']);
    });

    test('operators', () async {
      expect(await search('from:ana'), ['a1/t1']);
      expect(await search('from:ben@corp.io'), unorderedEquals(['a1/t2', 'a1/t4', 'a2/u1']));
      expect(await search('to:ana'), unorderedEquals(['a1/t1', 'a1/t4']));
      expect(await search('subject:lunch'), ['a1/t2']);
      expect(await search('subject:"budget review"'), ['a1/t1']);
      expect(await search('subject:numbers'), isEmpty);
      expect(await search('has:attachment'), ['a1/t1']);
      expect(await search('is:unread'), ['a1/t1']);
      expect(await search('is:starred'), ['a1/t2']);
      expect(await search('is:flagged lunch'), ['a1/t2']);
      expect(await search('is:unread lunch'), isEmpty);
      expect(await search('in:sent'), ['a1/t1']);
      expect(await search('in:inbox from:ben'), unorderedEquals(['a1/t2', 'a2/u1']));
      expect(await search('label:work'), ['a1/t4']);
      expect(await search('in:spam'), ['a1/t3']);
      expect(await search('in:anywhere budget'), hasLength(3));
      expect(await search('budget -review'), ['a2/u1']);
      expect(await search('from:ben -from:ben'), isEmpty);
      expect(await search('-lunch is:starred'), isEmpty);
    });

    test('account restriction', () async {
      expect(await search('budget', accounts: {'a2'}), ['a2/u1']);
      expect(await search('budget', accounts: {}), isEmpty);
    });

    test('index follows updates and deletes', () async {
      await store.upsertMessages('a1', [
        msg('m3', thread: 't2', subject: 'Dinner?', from: ben, to: const [me], minute: 3, snippet: 'Bistro'),
      ]);
      expect(await search('lunch'), isEmpty);
      expect(await search('dinner bistro'), ['a1/t2']);
      // A metadata-only change keeps the body indexed.
      await store.upsertMessages('a1', [
        msg(
          'm5',
          thread: 't4',
          subject: 'Notes v2',
          from: ben,
          cc: const [ana],
          minute: 5,
          snippet: 'see body',
          boxes: {'Label_work'},
        ),
      ]);
      expect(await search('xylophone v2'), ['a1/t4']);
      await store.deleteThreads('a1', ['t4']);
      expect(await search('xylophone'), isEmpty);
      await store.rebuildSearchIndex();
      expect(await search('dinner'), ['a1/t2']);
      expect(await search('xylophone'), isEmpty);
    });

    test('empty and degenerate queries', () async {
      expect(await search(''), isEmpty);
      expect(await search('   '), isEmpty);
      expect(await search('"'), isEmpty);
      expect(await search('AND OR NOT'), isEmpty);
      expect(await search('*'), isEmpty);
      expect(await search('in:anywhere'), isEmpty);
    });
  });
}
