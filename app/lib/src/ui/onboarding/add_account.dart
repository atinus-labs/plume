import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_gmail/plume_gmail.dart' show GoogleSignInException, SignInFailure;
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../services/accounts.dart';
import '../../services/imap_connector.dart';
import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/services.dart';
import '../actions.dart';
import 'server_account_form.dart';

/// Opens the add-account dialog.
Future<void> showAddAccountDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const Dialog(child: SingleChildScrollView(child: AddAccountPanel(inDialog: true))),
    );

/// Signs [account] in again after its credentials stopped working: the
/// password form for mail server accounts, the browser for the others.
Future<void> signInAgain(BuildContext context, WidgetRef ref, Account account) async {
  if (account.provider == ImapConnector.kindId) {
    await showServerAccountDialog(context, account, mode: ServerFormMode.reauth);
    return;
  }
  try {
    await ref.read(accountsServiceProvider).reauthenticate(account);
    showSnack('${account.email} is connected again');
  } catch (e) {
    showSnack('Sign-in didn’t complete: $e');
  }
}

enum _Step { pick, server, googleSetup }

/// Provider picker, the mail server form, and the browser sign-in progress
/// state. Used on the welcome screen and in the add-account dialog.
class AddAccountPanel extends ConsumerStatefulWidget {
  const AddAccountPanel({super.key, this.inDialog = false});

  final bool inDialog;

  @override
  ConsumerState<AddAccountPanel> createState() => _AddAccountPanelState();
}

class _AddAccountPanelState extends ConsumerState<AddAccountPanel> {
  var _step = _Step.pick;
  String? _signingIn;
  String? _error;
  Completer<void>? _cancel;

  Future<void> _add(AccountConnector connector) async {
    final cancel = _cancel = Completer<void>();
    setState(() {
      _signingIn = connector.kind;
      _error = null;
    });
    try {
      final account = await ref.read(accountsServiceProvider).add(connector.kind, cancel: cancel.future);
      if (mounted) _finished(account, alreadyAdded: false);
    } on DuplicateAccountException catch (e) {
      if (!mounted) return;
      if (e.existingKind != null) {
        setState(() => _error = '${e.email} is already in Plume with a mail server sign-in. Remove it first to switch.');
        return;
      }
      if (widget.inDialog) Navigator.of(context).pop();
      showSnack('${e.email} is already in Plume. Its sign-in was refreshed.');
    } on GoogleSignInException catch (e) {
      if (mounted && e.reason != SignInFailure.cancelled) setState(() => _error = _friendly(e));
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _signingIn = null);
    }
  }

  void _finished(Account account, {required bool alreadyAdded}) {
    ref.read(viewProvider.notifier).show(ref.read(viewProvider).forAccount(null, inboxCategory: ref.read(inboxCategoryProvider)));
    if (widget.inDialog) Navigator.of(context).pop();
    showSnack(alreadyAdded ? '${account.email} was already in Plume. Its settings were updated.' : '${account.email} added');
  }

  static String _friendly(Object e) => switch (e) {
        GoogleSignInException(reason: SignInFailure.accessDenied) => 'Access wasn’t granted. Plume needs permission to read and send your mail.',
        GoogleSignInException(reason: SignInFailure.missingScopes) =>
          'Some permissions were unticked. Sign in again and allow all of them so Plume can manage your mail.',
        GoogleSignInException(reason: SignInFailure.timedOut) => 'Sign-in timed out. Please try again.',
        GoogleSignInException(:final message) => 'Sign-in didn’t complete: $message',
        _ => 'Sign-in didn’t complete: $e',
      };

  void _go(_Step step) => setState(() {
        _step = step;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_signingIn != null) {
      content = _Waiting(onCancel: () {
        if (!(_cancel?.isCompleted ?? true)) _cancel!.complete();
        setState(() => _signingIn = null);
      });
    } else {
      content = switch (_step) {
        _Step.pick => _picker(context),
        _Step.server => ServerAccountForm(
            onBack: () => _go(_Step.pick),
            onDone: (account, alreadyAdded) => _finished(account, alreadyAdded: alreadyAdded),
          ),
        _Step.googleSetup => _GoogleSetup(
            onBack: () => _go(_Step.pick),
            onConfigured: () => _go(_Step.pick),
          ),
      };
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedSize(
          duration: Spring.spatial.duration,
          curve: Spring.spatial.curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Spring.effects.duration,
            child: KeyedSubtree(key: ValueKey((_step, _signingIn != null)), child: content),
          ),
        ),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connectors = {for (final c in ref.watch(accountsServiceProvider).connectors) c.kind: c};
    final google = connectors['gmail'];
    final server = connectors[ImapConnector.kindId];
    final demo = connectors['demo'];
    final googleReady = google?.isConfigured ?? false;
    final options = <_ProviderOption>[
      if (google != null)
        _ProviderOption(
          icon: Symbols.mail_rounded,
          title: 'Google',
          subtitle: googleReady ? 'Sign in with your Google account in the browser' : 'Needs a one-time setup first',
          onTap: googleReady ? () => unawaited(_add(google)) : () => _go(_Step.googleSetup),
        ),
      if (server != null)
        _ProviderOption(
          icon: Symbols.alternate_email_rounded,
          title: 'Other mail',
          subtitle: 'iCloud, Fastmail, Yahoo, your own server, or Gmail with an app password',
          onTap: () => _go(_Step.server),
        ),
      if (demo != null)
        _ProviderOption(
          icon: Symbols.science_rounded,
          title: 'Demo account',
          subtitle: 'Made-up mail to look around with',
          onTap: () => unawaited(_add(demo)),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.inDialog) ...[
          Text('Add an account', style: theme.textTheme.headlineSmallEmphasized),
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _ProviderTile(option: options[i], radius: groupedRadius(i, options.length)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
          ),
        const SizedBox(height: 16),
        Text(
          'Plume talks to your mail provider directly. Your mail and passwords stay on this computer.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

final class _ProviderOption {
  const _ProviderOption({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// One row of the provider list. The icon's shape blooms on hover.
class _ProviderTile extends StatefulWidget {
  const _ProviderTile({required this.option, required this.radius});

  final _ProviderOption option;
  final BorderRadius radius;

  @override
  State<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<_ProviderTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final option = widget.option;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: widget.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: option.onTap,
        onHover: (h) => setState(() => _hovered = h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              SpringBuilder(
                value: _hovered ? 1 : 0,
                spring: Spring.spatialFast,
                builder: (context, t, child) => SizedBox.square(
                  dimension: 44,
                  child: Material(
                    color: Color.lerp(scheme.secondaryContainer, scheme.primaryContainer, unit(t)),
                    shape: RadialShapeBorder(RadialShape.lerp(Shapes.circle, Shapes.cookie9, unit(t))),
                    child: child,
                  ),
                ),
                child: Icon(option.icon, size: 22, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title, style: theme.textTheme.titleMediumEmphasized),
                    const SizedBox(height: 2),
                    Text(option.subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Symbols.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const LoadingIndicator(size: 64, contained: true),
        const SizedBox(height: 20),
        Text('Continue in your browser', style: theme.textTheme.titleLargeEmphasized),
        const SizedBox(height: 8),
        Text(
          'A Google sign-in page opened in your browser. Come back here when you’re done.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// One-time setup when no Google OAuth client is configured: Google requires
/// every app that reads Gmail to have its own client.
class _GoogleSetup extends StatefulWidget {
  const _GoogleSetup({required this.onBack, required this.onConfigured});

  final VoidCallback onBack;
  final VoidCallback onConfigured;

  @override
  State<_GoogleSetup> createState() => _GoogleSetupState();
}

class _GoogleSetupState extends State<_GoogleSetup> {
  String? _error;

  Future<void> _choose() async {
    final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
    if (file == null) return;
    try {
      await GoogleClient.install(await file.readAsString());
      widget.onConfigured();
    } on FormatException catch (e) {
      setState(() => _error = 'That doesn’t look like a Google OAuth client file (${e.message}).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = [
      'Open Google Cloud Console, create a project and enable the Gmail API.',
      'In Google Auth Platform → Branding, fill in the app name, emails, home page and '
          'privacy policy links, and add the links’ domain under Authorized domains. Publishing needs them.',
      'Under Audience, make sure the user type is External, then click Publish app.',
      'Under Data access, add https://mail.google.com/, userinfo.email, userinfo.profile and openid.',
      'Under Clients, create a “Desktop app” client and download its JSON right away. '
          'Google shows the secret only once.',
      'Choose the file below, then pick Google again to sign in. When Google says the app '
          'isn’t verified, choose Advanced → Go to Plume.',
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(tooltip: 'Back', onPressed: widget.onBack, icon: const Icon(Symbols.arrow_back_rounded)),
                const SizedBox(width: 4),
                Expanded(child: Text('Set up Google sign-in', style: theme.textTheme.titleMediumEmphasized)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Google requires a one-time setup before Plume can read Gmail:',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}.', style: theme.textTheme.bodyMedium)),
                    Expanded(child: Text(steps[i], style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _choose,
                  icon: const Icon(Symbols.upload_file_rounded),
                  label: const Text('Choose client file…'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('https://console.cloud.google.com/apis/credentials'),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Open Cloud Console'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
            const SizedBox(height: 12),
            Text(
              'Rather skip this? Go back and choose Other mail to use Gmail with an app password.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
