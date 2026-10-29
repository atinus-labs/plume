import 'dart:io'; // TEMP-VERIFY
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:plume_core/plume_core.dart';

import '../services/accounts.dart';

/// A provider that generates believable mail locally. Used with
/// `--dart-define=PLUME_DEMO=true` to develop and demo the UI without a real
/// account. It follows Gmail's label semantics.
final class DemoConnector implements AccountConnector {
  @override
  String get kind => 'demo';
  @override
  String get label => 'Demo account';
  @override
  bool get isConfigured => true;
  @override
  MailProviderFactory get factory => _DemoFactory();

  @override
  Future<({String email, String name, String? avatarUrl})> signIn(String accountId, {String? loginHint, Future<void>? cancel}) async =>
      (email: 'alex.rivera@example.com', name: 'Alex Rivera', avatarUrl: null);

  @override
  TokenSource tokenSource(Account account) => _NoTokens();

  @override
  Future<void> moveCredentials(String fromAccountId, String toAccountId) async {}

  @override
  Future<void> signOut(Account account) async {}
}

final class _NoTokens implements TokenSource {
  @override
  Future<String> accessToken() async => 'demo';
  @override
  void invalidate() {}
}

final class _DemoFactory implements MailProviderFactory {
  @override
  String get kind => 'demo';
  @override
  MailProvider create(Account account, TokenSource tokens) => DemoProvider(account);
}

final class DemoProvider implements MailProvider {
  DemoProvider(this.account);

  @override
  final Account account;
  final _random = Random(7);
  final _bodies = <String, MessageBody>{};
  final _messages = <String, Message>{};
  int _seq = 0;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
      labels: true, categories: true, serverSearch: true, serverDrafts: false, push: true);

  String get _id => account.id;

  List<Mailbox> get _mailboxes => [
        Mailbox(accountId: _id, id: 'INBOX', name: 'Inbox', role: MailboxRole.inbox, kind: MailboxKind.system, sortOrder: 0),
        Mailbox(accountId: _id, id: 'SENT', name: 'Sent', role: MailboxRole.sent, kind: MailboxKind.system, sortOrder: 2),
        Mailbox(accountId: _id, id: 'DRAFT', name: 'Drafts', role: MailboxRole.drafts, kind: MailboxKind.system, sortOrder: 3),
        Mailbox(accountId: _id, id: 'SPAM', name: 'Spam', role: MailboxRole.junk, kind: MailboxKind.system, sortOrder: 5),
        Mailbox(accountId: _id, id: 'TRASH', name: 'Trash', role: MailboxRole.trash, kind: MailboxKind.system, sortOrder: 6),
        Mailbox(accountId: _id, id: 'IMPORTANT', name: 'Important', role: MailboxRole.important, kind: MailboxKind.system, hidden: true),
        for (final (id, name, cat) in [
          ('CATEGORY_PERSONAL', 'Primary', MailCategory.primary),
          ('CATEGORY_SOCIAL', 'Social', MailCategory.social),
          ('CATEGORY_PROMOTIONS', 'Promotions', MailCategory.promotions),
          ('CATEGORY_UPDATES', 'Updates', MailCategory.updates),
          ('CATEGORY_FORUMS', 'Forums', MailCategory.forums),
        ])
          Mailbox(accountId: _id, id: id, name: name, role: MailboxRole.category, category: cat, kind: MailboxKind.system, hidden: true),
        Mailbox(accountId: _id, id: 'Label_work', name: 'Work', color: 0xFF4986E7, sortOrder: 10),
        Mailbox(accountId: _id, id: 'Label_travel', name: 'Travel', color: 0xFF16A765, sortOrder: 11),
        Mailbox(accountId: _id, id: 'Label_receipts', name: 'Receipts', color: 0xFFFFAD47, sortOrder: 12),
        Mailbox(accountId: _id, id: 'Label_family', name: 'Family', color: 0xFFF691B2, sortOrder: 13),
      ];

  @override
  Future<SyncResult> sync(SyncStore store) async {
    final seeded = await store.readState(_id, 'demo.seeded');
    if (seeded == null) {
      await store.transaction(() async {
        await store.replaceMailboxes(_id, _mailboxes);
        await store.upsertMessages(_id, _generate());
        await store.writeState(_id, 'demo.seeded', '1');
      });
      return const SyncResult(fullResync: true);
    }
    if (_pendingArrival) {
      _pendingArrival = false;
      final m = _arrival();
      await store.upsertMessages(_id, [m]);
      return SyncResult(newMessages: [m]);
    }
    return const SyncResult();
  }

  bool _pendingArrival = false;

  @override
  Stream<void> watchChanges() {
    // A new message every few minutes, to exercise notifications.
    return Stream.periodic(const Duration(minutes: 3), (_) => _pendingArrival = true);
  }

  @override
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, int pageSize = 50}) async =>
      const LoadMoreResult(loaded: 0, hasMore: false);

  @override
  Future<void> fetchBodies(SyncStore store, List<String> messageIds) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    for (final id in messageIds) {
      await store.saveBody(_id, id, _bodies[id] ?? _bodyFor(id, _messages[id]));
    }
  }

  @override
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment) async =>
      Uint8List.fromList(List.generate(attachment.size.clamp(0, 4096), (i) => i % 256));

  @override
  LocalMutation localEffect(MailOperation operation, List<Mailbox> mailboxes) => switch (operation) {
        LabelOperation(:final add, :final remove) => LocalMutation(addMailboxes: add, removeMailboxes: remove),
        ActionOperation(:final action) => switch (action) {
            MailAction.archive => const LocalMutation(removeMailboxes: {'INBOX'}),
            MailAction.moveToInbox => const LocalMutation(addMailboxes: {'INBOX'}, removeMailboxes: {'TRASH', 'SPAM'}),
            MailAction.trash => const LocalMutation(addMailboxes: {'TRASH'}, removeMailboxes: {'INBOX'}),
            MailAction.restore => const LocalMutation(addMailboxes: {'INBOX'}, removeMailboxes: {'TRASH'}),
            MailAction.deleteForever => const LocalMutation(delete: true),
            MailAction.markSpam => const LocalMutation(addMailboxes: {'SPAM'}, removeMailboxes: {'INBOX'}),
            MailAction.markNotSpam => const LocalMutation(addMailboxes: {'INBOX'}, removeMailboxes: {'SPAM'}),
            MailAction.markRead => const LocalMutation(setRead: true),
            MailAction.markUnread => const LocalMutation(setRead: false),
            MailAction.flag => const LocalMutation(setFlagged: true),
            MailAction.unflag => const LocalMutation(setFlagged: false),
          },
      };

  @override
  List<String> currentMessageIds(List<String> messageIds) => messageIds;

  @override
  Future<void> execute(SyncStore store, MailOperation operation) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  @override
  Future<String> send(OutgoingMessage message) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return 'sent-${_seq++}';
  }

  @override
  Future<String> saveDraft(OutgoingMessage message) async => message.draftId ?? 'draft-${_seq++}';

  @override
  Future<void> deleteDraft(String draftId) async {}

  @override
  Future<SearchPage> search(SyncStore store, String query, {String? pageToken}) async {
    final q = query.toLowerCase();
    final ids = <String>{
      for (final m in _messages.values)
        if (m.subject.toLowerCase().contains(q) ||
            m.snippet.toLowerCase().contains(q) ||
            (m.from?.displayName.toLowerCase().contains(q) ?? false))
          m.threadId,
    };
    return SearchPage(threadIds: ids.toList());
  }

  @override
  Future<void> dispose() async {}

  // Content ------------------------------------------------------------------

  static const _me = Address('alex.rivera@example.com', 'Alex Rivera');

  static const _people = [
    Address('maya.chen@lumen.design', 'Maya Chen'),
    Address('arjun@northwind.dev', 'Arjun Mehta'),
    Address('sofia.alvarez@gmail.com', 'Sofía Álvarez'),
    Address('jonas@kettle.studio', 'Jonas Becker'),
    Address('priya.nair@acme.co', 'Priya Nair'),
    Address('mom@family.example', 'Mom'),
    Address('liam.oconnor@outlook.com', "Liam O'Connor"),
    Address('hana.sato@rakuten.example', 'Hana Sato'),
  ];

  static const _threads = <(int, String, List<String>, String, Set<String>)>[
    (0, 'Design review: inbox redesign v3', [
      "Hey Alex — I've pushed the latest iteration of the inbox redesign. The grouped list feels a lot calmer now, and the selection morph on avatars tested really well. Can you take a look before Thursday?",
      'Looks great! One note: the unread weight might be a touch too heavy on dark mode. Otherwise ship it.',
      'Good catch. Dialled it back from 700 to 650. Updated file is in the same folder.',
    ], 'CATEGORY_PERSONAL', {'Label_work', 'IMPORTANT'}),
    (1, 'Re: Q4 infrastructure budget', [
      "Following up on yesterday's call — attached is the revised budget with the reserved instances broken out. Net saving is about 18% versus on-demand.",
      'Thanks Arjun. Can we also model the scenario where we move the batch jobs to spot?',
    ], 'CATEGORY_PERSONAL', {'Label_work'}),
    (2, 'Lisbon in March? 🌊', [
      'Okay, hear me out: Lisbon, second week of March. Flights are cheap right now and the weather should be perfect. I found a lovely flat in Alfama with a terrace.',
    ], 'CATEGORY_PERSONAL', {'Label_travel'}),
    (5, 'Sunday lunch', [
      'Your father is making his famous lasagna on Sunday. Come around 1? Bring that nice bread from the bakery near you if you can. Love you!',
    ], 'CATEGORY_PERSONAL', {'Label_family'}),
    (3, 'Prototype feedback + next steps', [
      'Played with the prototype over the weekend. The spring animations are delightful — especially the compose transition. A few small things I noticed are in the doc.',
    ], 'CATEGORY_PERSONAL', {'Label_work'}),
    (4, 'Contract renewal — please sign by Friday', [
      'Hi Alex, please find the renewal contract attached. Everything is unchanged except for the updated payment terms (net 30). Let me know if you have any questions.',
    ], 'CATEGORY_PERSONAL', {'Label_work', 'IMPORTANT'}),
    (6, 'Photos from the hike', [
      'Finally got around to editing the photos from the ridge trail. A couple of them came out really well — the one at the summit is my new wallpaper.',
    ], 'CATEGORY_PERSONAL', {}),
    (7, 'Tokyo meetup — venue confirmed', [
      "We've locked in the venue for the November meetup in Shibuya. 120 RSVPs so far! Would you be up for a 10-minute lightning talk?",
    ], 'CATEGORY_PERSONAL', {'Label_travel'}),
  ];

  static const _bulk = <(String, String, String, String)>[
    ('GitHub', 'noreply@github.com', '[plume] Pull request #42 merged', 'Your pull request "Spring-based list selection" was merged into main by maya-chen.'),
    ('Linear', 'notifications@linear.app', 'PLM-118 moved to In Review', 'Arjun Mehta moved "Tray badge renders blurry at 1.5x" to In Review.'),
    ('Figma', 'no-reply@figma.com', 'Maya commented on Inbox v3', '"Should the date use tabular figures here?" — reply in Figma to continue the conversation.'),
    ('Stripe', 'receipts@stripe.com', 'Your receipt from Kettle Studio', 'Receipt #1849-2231 · Amount paid €24.00 · Thanks for your business.'),
    ('Airbnb', 'automated@airbnb.com', 'Your reservation is confirmed', 'Pack your bags! Your stay in Alfama, Lisbon is confirmed for Mar 9 – Mar 15.'),
    ('Google Calendar', 'calendar-notification@google.com', 'Reminder: Design sync @ 11:00', 'Design sync · Today 11:00 – 11:30 · Google Meet.'),
    ('The Browser', 'newsletter@thebrowser.example', 'Five essays worth your weekend', 'This week: the quiet return of the long read, a history of the paperclip, and why your houseplants like music.'),
    ('Spotify', 'no-reply@spotify.com', 'Your Release Radar is here', 'New music from artists you follow, updated every Friday.'),
    ('LinkedIn', 'messages-noreply@linkedin.com', 'You appeared in 23 searches this week', 'See who is looking at your profile and how you compare.'),
    ('Uniqlo', 'news@uniqlo.example', 'Autumn essentials — 20% off this week', 'Merino knits, HEATTECH and more. Offer ends Sunday.'),
  ];

  List<Message> _generate() {
    final now = DateTime.now();
    final out = <Message>[];
    var t = 0;
    for (final (who, subject, replies, category, labels) in _threads) {
      final threadId = 'th${t++}';
      final start = now.subtract(Duration(hours: 2 + t * 9 + _random.nextInt(6)));
      for (var i = 0; i < replies.length; i++) {
        final mine = i.isOdd;
        final from = mine ? _me : _people[who];
        final date = start.add(Duration(minutes: 47 * i));
        final latest = i == replies.length - 1;
        final id = 'm${_seq++}';
        final m = Message(
          accountId: _id,
          id: id,
          threadId: threadId,
          subject: i == 0 ? subject : 'Re: $subject',
          from: from,
          to: [mine ? _people[who] : _me],
          cc: who == 1 && i == 0 ? const [Address('finance@northwind.dev', 'Finance')] : const [],
          date: date,
          snippet: replies[i],
          isRead: !(latest && !mine && t <= 4),
          isFlagged: t == 2 || t == 6,
          mailboxIds: {
            if (!mine) 'INBOX',
            if (mine) 'SENT',
            category,
            ...labels,
          },
          attachments: t == 2 || t == 6
              ? [
                  AttachmentInfo(
                      partId: '2',
                      providerId: 'att$id',
                      filename: t == 2 ? 'Q4-budget-revised.xlsx' : 'Renewal-Contract-2026.pdf',
                      mimeType: t == 2 ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'application/pdf',
                      size: t == 2 ? 48213 : 231840),
                ]
              : const [],
          messageIdHeader: '<$id@example.com>',
        );
        _messages[id] = m;
        _bodies[id] = MessageBody(
          text: replies[i],
          html: '<p>${replies[i]}</p><p>${mine ? 'Alex' : from.shortName}</p>',
        );
        out.add(m);
      }
    }
    for (var i = 0; i < 46; i++) {
      final (name, email, subject, snippet) = _bulk[i % _bulk.length];
      final id = 'm${_seq++}';
      final category = switch (name) {
        'LinkedIn' => 'CATEGORY_SOCIAL',
        'Spotify' || 'Uniqlo' || 'The Browser' => 'CATEGORY_PROMOTIONS',
        _ => 'CATEGORY_UPDATES',
      };
      final date = now.subtract(Duration(hours: 1 + i * 13 + _random.nextInt(10), minutes: _random.nextInt(59)));
      final m = Message(
        accountId: _id,
        id: id,
        threadId: 'tb$i',
        subject: subject,
        from: Address(email, name),
        to: const [_me],
        date: date,
        snippet: snippet,
        isRead: i > 5 || _random.nextBool(),
        mailboxIds: {
          if (i % 9 != 8) 'INBOX',
          category,
          if (name == 'Stripe') 'Label_receipts',
        },
        listUnsubscribe: category == 'CATEGORY_PROMOTIONS' ? '<mailto:unsubscribe@example.com>' : null,
      );
      _messages[id] = m;
      _bodies[id] = name == 'The Browser' ? _newsletter() : MessageBody(text: snippet, html: '<p>$snippet</p>');
      final devHtml = File('${Platform.environment['PLUME_DEV_HTML_DIR'] ?? '/nonexistent'}/$name.html'); // TEMP-VERIFY
      if (devHtml.existsSync()) _bodies[id] = MessageBody(html: devHtml.readAsStringSync(), text: snippet); // TEMP-VERIFY
      out.add(m);
    }
    return out;
  }

  Message _arrival() {
    final who = _people[_random.nextInt(_people.length)];
    final id = 'm${_seq++}';
    const lines = [
      'Quick question about tomorrow — are we still on for 10?',
      'Sending over the notes from today. Let me know if I missed anything.',
      'Just landed! Will call you tonight.',
    ];
    final text = lines[_random.nextInt(lines.length)];
    final m = Message(
      accountId: _id,
      id: id,
      threadId: 'tn$id',
      subject: ['Quick question', 'Notes from today', 'Landed ✈️'][lines.indexOf(text)],
      from: who,
      to: const [_me],
      date: DateTime.now(),
      snippet: text,
      isRead: false,
      mailboxIds: const {'INBOX', 'CATEGORY_PERSONAL'},
    );
    _messages[id] = m;
    _bodies[id] = MessageBody(text: text, html: '<p>$text</p>');
    return m;
  }

  MessageBody _bodyFor(String id, Message? m) => MessageBody(text: m?.snippet ?? '', html: '<p>${m?.snippet ?? ''}</p>');

  MessageBody _newsletter() => const MessageBody(html: '''
<table width="100%" bgcolor="#f4f1ea" cellpadding="0" cellspacing="0"><tr><td align="center">
<table width="600" bgcolor="#ffffff" cellpadding="24" cellspacing="0" style="font-family:Georgia,serif;color:#222">
<tr><td style="background:#1f3a5f;color:#fff;font-size:28px;font-weight:bold">The Browser</td></tr>
<tr><td><h2 style="margin:0 0 8px 0">Five essays worth your weekend</h2>
<p style="line-height:1.6">This week: the quiet return of the long read, a history of the humble paperclip, and why your houseplants might actually like music.</p>
<p><a href="https://example.com/read" style="background:#1f3a5f;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">Read this week's issue</a></p>
<img src="https://example.com/tracking.gif" width="1" height="1"></td></tr>
<tr><td style="font-size:12px;color:#777">You are receiving this because you subscribed. <a href="https://example.com/unsub">Unsubscribe</a></td></tr>
</table></td></tr></table>''');
}
