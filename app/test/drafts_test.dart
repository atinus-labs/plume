import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show QuillEditor;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/navigation.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/ui/actions.dart';
import 'package:plume/src/ui/compose/compose_host.dart';
import 'package:plume/src/ui/compose/compose_panel.dart';
import 'package:plume/src/ui/reader/message_card.dart';
import 'package:plume/src/ui/reader/reader_pane.dart';
import 'package:plume_core/plume_core.dart';

import 'support/demo_app.dart';

/// The demo account, which comes with a reply in Tokyo and a new message
/// in Drafts.
void main() {
  late WidgetTester t;
  late WidgetRef ref;
  late Services services;
  late Future<void> Function() settle;

  Future<void> start(WidgetTester tester) async {
    final app = await DemoApp.start(tester);
    t = tester;
    ref = app.ref;
    services = app.services;
    settle = app.settle;
  }

  Future<List<Message>> drafts() async => [
        for (final m in (await t.runAsync(() async {
          final threads = await services.store.watchThreads(const RoleFilter(MailboxRole.drafts)).first;
          return [
            for (final x in threads) ...await services.store.messagesInThreads(x.accountId, [x.id]),
          ];
        }))!)
          if (m.isDraft) m,
      ];

  String typed() => t.widget<QuillEditor>(find.byType(QuillEditor)).controller.document.toPlainText().trim();

  testWidgets('a reply drafted earlier opens from its conversation and saves without doubling up', (tester) async {
    await start(tester);
    final account = (await t.runAsync(services.store.accounts))!.single;
    await t.runAsync(() => services.store.saveAccount(account.copyWith(signature: 'Alex')));
    final tokyo = ref.read(visibleThreadsProvider).value!.firstWhere((x) => x.subject.contains('Tokyo'));
    openThread(ref, tokyo);
    await settle();

    expect(find.descendant(of: find.byType(ReaderPane), matching: find.byType(DraftCard)), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Edit'));
    await settle();

    expect(find.byType(ComposePanel), findsOneWidget);
    expect(typed(), startsWith('Count me in!'));
    // The quote is kept apart, as when the reply was first written.
    expect(typed(), isNot(contains('wrote:')));
    expect(find.text('Quoted text'), findsOneWidget);

    // Asking again brings the open window back instead of opening another.
    await t.tap(find.byTooltip('Minimise'));
    await settle();
    await t.tap(find.widgetWithText(FilledButton, 'Edit'));
    await settle();
    expect(find.byType(ComposePanel), findsOneWidget);
    expect(find.byType(QuillEditor), findsOneWidget);

    final editor = t.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    editor.replaceText(editor.document.length - 1, 0, ' See you there.', null);
    await t.tap(find.byTooltip('Save & close (Esc)'));
    await settle();
    expect(find.byType(ComposePanel), findsNothing);
    expect(find.text('Draft saved'), findsOneWidget);

    final saved = (await drafts()).firstWhere((m) => m.threadId == tokyo.id);
    final body = (await t.runAsync(() => services.store.body(saved.accountId, saved.id)))!;
    expect(body.text, contains('Ten minutes sounds about right. See you there.'));
    expect('\n-- \nAlex'.allMatches(body.text!), hasLength(1));
    expect('wrote:'.allMatches(body.text!), hasLength(1));
    expect('plume_signature'.allMatches(body.html!), hasLength(1));

    // And once more, to make sure it reads back the same.
    await t.tap(find.widgetWithText(FilledButton, 'Edit'));
    await settle();
    expect(typed(), 'Count me in! I could show how the compose window grows out of the button that opened it. '
        'Ten minutes sounds about right. See you there.');
  });

  testWidgets('a new message in Drafts opens to be written, and can be discarded', (tester) async {
    await start(tester);
    ref.read(viewProvider.notifier).show(const MailView(ViewKind.drafts));
    await settle();

    await t.tap(find.text('Packing list for Lisbon'));
    await settle();
    expect(find.byType(ComposePanel), findsOneWidget);
    expect(typed(), startsWith('Sunscreen'));
    // Nothing to read, so the reader stays as it was.
    expect(ref.read(openThreadProvider), isNull);

    await t.tap(find.byTooltip('Discard draft'));
    await settle();
    expect(find.byType(ComposePanel), findsNothing);
    expect((await drafts()).map((m) => m.subject), isNot(contains('Packing list for Lisbon')));
  });

  testWidgets('a draft kept on this device opens from Drafts and goes to the server once closed', (tester) async {
    await start(tester);
    final account = (await t.runAsync(services.store.accounts))!.single;
    // As if written offline: saved here, and not uploaded yet.
    final kept = (await t.runAsync(() => services.store.saveLocalDraft(OutgoingMessage(
          accountId: account.id,
          from: Address(account.email, account.displayName),
          subject: 'Written on the train',
          textBody: 'Tickets are booked.',
          htmlBody: '<p>Tickets are booked.</p>',
        ))))!;
    ref.read(viewProvider.notifier).show(const MailView(ViewKind.drafts));
    await settle();

    await t.tap(find.text('Written on the train'));
    await settle();
    expect(find.byType(ComposePanel), findsOneWidget);
    expect(typed(), 'Tickets are booked.');

    final editor = t.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    editor.replaceText(editor.document.length - 1, 0, ' See you Friday.', null);
    await t.tap(find.byTooltip('Save & close (Esc)'));
    await settle();
    expect(find.text('Draft saved'), findsOneWidget);

    final saved = (await drafts()).where((m) => m.subject == 'Written on the train').single;
    expect(saved.id, isNot(LocalDraft.messageIdOf(kept.id)), reason: 'the server copy took its place');
    final body = (await t.runAsync(() => services.store.body(saved.accountId, saved.id)))!;
    expect(body.text, contains('Tickets are booked. See you Friday.'));
  });

  testWidgets('a forwarded HTML message keeps its layout and images, in its draft too', (tester) async {
    await start(tester);
    final thread = ref.read(visibleThreadsProvider).value!.first;
    final original = (await t.runAsync(() => services.store.messagesInThreads(thread.accountId, [thread.id])))!.last
        .copyWith(attachments: const [
      AttachmentInfo(
          partId: '2', filename: 'logo.png', mimeType: 'image/png', size: 4, contentId: 'logo@shop', isInline: true),
      AttachmentInfo(partId: '3', filename: 'receipt.pdf', mimeType: 'application/pdf', size: 64),
    ]);
    await t.runAsync(() => services.store.saveBody(original.accountId, original.id, MessageBody(
          html: '<html><head><style>p { color: red }</style></head><body><img src="cid:logo@shop" alt="Shop">'
              '<p><a href="https://shop.example/order/1">View order</a></p></body></html>',
          inlineParts: {'logo@shop': Uint8List.fromList([137, 80, 78, 71])},
        )));

    Future<void> expectQuoted() async {
      expect(find.text('Forwarded message'), findsOneWidget);
      // The image goes with the quote, not among the attachments.
      expect(find.textContaining('receipt.pdf'), findsOneWidget);
      expect(find.textContaining('logo.png'), findsNothing);
      await t.tap(find.byTooltip('Save & close (Esc)'));
      await settle();
      // After the next sync, Drafts shows only the server's copy.
      await t.runAsync(() => services.engine.syncAccount(original.accountId));
      await settle();
      final saved = (await drafts()).where((m) => m.subject == 'Fwd: ${original.subject}').single;
      final body = (await t.runAsync(() => services.store.body(saved.accountId, saved.id)))!;
      expect(body.html,
          contains('<img src="cid:logo@shop" alt="Shop"><p><a href="https://shop.example/order/1">View order</a></p>'));
      expect(body.html, isNot(contains('color: red')));
      expect(body.text, contains('View order <https://shop.example/order/1>'));
      expect(
        [for (final a in saved.attachments) (a.filename, a.contentId)],
        [('receipt.pdf', null), ('logo.png', 'logo@shop')],
      );
    }

    ref.read(composeProvider.notifier).forward(original);
    await settle();
    await expectQuoted();

    // Opened from Drafts and saved again, it stays the same.
    ref.read(viewProvider.notifier).show(const MailView(ViewKind.drafts));
    await settle();
    await t.tap(find.text('Fwd: ${original.subject}'));
    await settle();
    await expectQuoted();
  });

  testWidgets('letters typed into the message are text, not mail shortcuts', (tester) async {
    await start(tester);
    final thread = ref.read(visibleThreadsProvider).value!.first;
    openThread(ref, thread);
    await settle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await settle();
    expect(find.byType(ComposePanel), findsOneWidget);

    await t.tap(find.byType(QuillEditor));
    await t.pump();
    for (final key in [
      LogicalKeyboardKey.keyE, // archive
      LogicalKeyboardKey.keyR, // reply
      LogicalKeyboardKey.keyA, // reply all
      LogicalKeyboardKey.keyF, // forward
      LogicalKeyboardKey.keyC, // compose
      LogicalKeyboardKey.keyJ, // next conversation
      LogicalKeyboardKey.keyS, // star
      LogicalKeyboardKey.keyX, // select
      LogicalKeyboardKey.slash, // search
    ]) {
      // Unhandled, so the platform hands it to the editor as typed text.
      expect(await t.sendKeyEvent(key), isFalse, reason: key.keyLabel);
    }
    await settle();

    expect(find.byType(ComposePanel), findsOneWidget);
    expect(ref.read(openThreadProvider), keyOf(thread));
    expect(ref.read(selectionProvider), isEmpty);
    final still = ref.read(visibleThreadsProvider).value!.firstWhere((x) => x.key == thread.key);
    expect(still.isFlagged, thread.isFlagged);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<QuillEditor>(), isNotNull);
  });

  testWidgets('a message closed by mistake opens again from the snackbar', (tester) async {
    await start(tester);
    ref.read(composeProvider.notifier).newMessage();
    await settle();
    await t.enterText(find.widgetWithText(TextField, 'Subject'), 'Before I forget');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(find.byType(ComposePanel), findsNothing);

    await t.tap(find.text('Open'));
    await settle();
    expect(find.byType(ComposePanel), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Before I forget'), findsOneWidget);
  });
}
