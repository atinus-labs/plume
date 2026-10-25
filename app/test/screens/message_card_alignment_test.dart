import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/ui/common/format.dart';
import 'package:plume/src/ui/reader/message_card.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

void main() {
  testWidgets('message card header aligns date with action buttons', (tester) async {
    final message = Message(
      accountId: 'a1',
      id: 'm1',
      threadId: 't1',
      subject: 'Test subject',
      from: const Address('sender@example.com', 'Sender'),
      date: DateTime.utc(2026, 10, 10, 12),
      isRead: true,
      mailboxIds: const {'INBOX'},
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: PlumeTheme.build(brightness: Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageCard(
                message: message,
                initiallyExpanded: true,
                index: 0,
                count: 1,
                myEmail: 'me@example.org',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dateCenter = tester.getCenter(find.text(listDate(message.date)));
    final starCenter = tester.getCenter(find.byTooltip('Star'));
    final replyCenter = tester.getCenter(find.byTooltip('Reply'));
    final moreCenter = tester.getCenter(find.byTooltip('More'));

    expect((dateCenter.dy - starCenter.dy).abs(), lessThan(1.5));
    expect((starCenter.dy - replyCenter.dy).abs(), lessThan(1.0));
    expect((replyCenter.dy - moreCenter.dy).abs(), lessThan(1.0));
  });
}
