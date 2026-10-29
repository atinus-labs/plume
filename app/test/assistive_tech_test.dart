import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plume/src/platform/linux/assistive_tech.dart';
import 'package:plume/src/services/accounts.dart';
import 'package:plume/src/services/desktop.dart';
import 'package:plume/src/state/mail.dart';
import 'package:plume/src/state/services.dart';
import 'package:plume/src/state/settings.dart';
import 'package:plume/src/ui/app.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_store/plume_store.dart';

import 'support/demo_services.dart';

TestDefaultBinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  const channel = MethodChannel('plume/accessibility');

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AssistiveTech.instance.value = true;
  });

  testWidgets('semantics are left out until a screen reader is listening', (tester) async {
    final semantics = tester.ensureSemantics();
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'assistiveTech' ? false : null);
    await AssistiveTech.instance.watch();
    expect(AssistiveTech.instance.value, isFalse);

    // No accounts, so the welcome page.
    final store = DriftMailStore.inMemory();
    addTearDown(() => tester.runAsync(store.close));
    final accounts = AccountsService(store: store, connectors: const []);
    final container = ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(Services(
          store: store,
          engine: MailEngine(store: store, factories: accounts.factories, tokenSourceFor: accounts.tokenSourceFor),
          desktop: HeadlessDesktop(),
          secrets: NoSecrets(),
          accounts: accounts,
          initialSettings: const AppSettings(),
        )),
        accountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PlumeApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Plume'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);

    // The runner reports that Orca has started.
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('assistiveTech', true)),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Welcome to Plume'), findsOneWidget);
    semantics.dispose();

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Drift closes its queries on timers.
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
