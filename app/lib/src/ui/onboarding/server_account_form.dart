import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:plume_imap/plume_imap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/accounts.dart';
import '../../services/server_setup.dart';
import '../../state/services.dart';
import '../actions.dart';

final _log = Logger('plume.setup');

/// What the form is for.
enum ServerFormMode {
  /// Adding a new account.
  add,

  /// Changing an account's server settings, name or password.
  edit,

  /// Entering the password again after the server rejected it.
  reauth,
}

/// Opens the form for an existing mail server account in a dialog.
Future<void> showServerAccountDialog(BuildContext context, Account account, {required ServerFormMode mode}) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ServerAccountForm(
              mode: mode,
              account: account,
              onDone: (account, _) {
                Navigator.of(context).pop();
                showSnack(mode == ServerFormMode.reauth ? '${account.email} is connected again' : 'Settings saved');
              },
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );

enum _Busy { finding, checking }

/// Email + password sign-in for any IMAP/SMTP server. Server settings are
/// discovered from the address and can be reviewed or entered by hand.
class ServerAccountForm extends ConsumerStatefulWidget {
  const ServerAccountForm({
    super.key,
    this.mode = ServerFormMode.add,
    this.account,
    this.onBack,
    required this.onDone,
  }) : assert(mode == ServerFormMode.add || account != null);

  final ServerFormMode mode;

  /// The account being edited (not used when adding).
  final Account? account;
  final VoidCallback? onBack;

  /// Called with the account once it is saved and connected.
  /// [alreadyAdded] is true when the address was already in Plume and only
  /// its password and settings were updated.
  final void Function(Account account, bool alreadyAdded) onDone;

  @override
  ConsumerState<ServerAccountForm> createState() => _ServerAccountFormState();
}

class _ServerAccountFormState extends ConsumerState<ServerAccountForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController();
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController();
  final _emailFocus = FocusNode();
  var _imapSecurity = ConnectionSecurity.tls;
  var _smtpSecurity = ConnectionSecurity.tls;
  String? _smtpUsername;
  var _saveSentCopy = true;

  var _showServers = false;

  /// The user changed the server fields by hand; never overwrite them.
  var _serversEdited = false;

  /// The domain whose discovered (or guessed) settings fill the fields.
  String? _filledFor;
  var _obscure = true;
  _Busy? _busy;
  String? _error;
  String? _serverSaid;

  ProviderInfo? _provider;
  DiscoveredSettings? _discovered;
  String? _discoveryDomain;
  Future<DiscoveredSettings?>? _discovery;

  bool get _adding => widget.mode == ServerFormMode.add;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account != null) {
      _name.text = account.displayName == account.email ? '' : account.displayName;
      _email.text = account.email;
      _provider = providerInfoFor(account.email);
      try {
        _fill(MailServerSettings.fromJson(account.providerConfig));
      } on FormatException {
        _showServers = true;
      }
      _showServers = _showServers || widget.mode == ServerFormMode.edit;
      // Existing settings are the user's; discovery must not replace them.
      _serversEdited = true;
    }
    _emailFocus.addListener(() {
      // Look the servers up as soon as the address is complete, so that
      // signing in doesn't wait for it.
      if (!_emailFocus.hasFocus && _adding && _isEmail(_email.text.trim())) unawaited(_discover(_email.text.trim()));
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _username, _imapHost, _imapPort, _smtpHost, _smtpPort]) {
      c.dispose();
    }
    _emailFocus.dispose();
    super.dispose();
  }

  static bool _isEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  static String _domainOf(String email) => email.substring(email.lastIndexOf('@') + 1).toLowerCase();

  void _emailChanged(String value) {
    final email = value.trim();
    final provider = _isEmail(email) ? providerInfoFor(email) : null;
    if (provider?.name != _provider?.name) setState(() => _provider = provider);
  }

  Future<DiscoveredSettings?> _discover(String email) {
    final domain = _domainOf(email);
    final pending = _discovery;
    if (pending != null && _discoveryDomain == domain) return pending;
    _discoveryDomain = domain;
    _discovered = null;
    final future = _discovery = discoverSettings(email).then<DiscoveredSettings?>((found) => found, onError: (Object e) {
      _log.info('Server discovery failed: $e');
      return null;
    });
    unawaited(future.then((found) {
      if (!mounted || _discoveryDomain != domain) return;
      setState(() {
        _discovered = found;
        if (found != null && !_serversEdited) {
          _fill(found.settings);
          _filledFor = domain;
        }
      });
    }));
    return future;
  }

  void _fill(MailServerSettings s) {
    _imapHost.text = s.imap.host;
    _imapPort.text = '${s.imap.port}';
    _imapSecurity = s.imap.security;
    _smtpHost.text = s.smtp.host;
    _smtpPort.text = '${s.smtp.port}';
    _smtpSecurity = s.smtp.security;
    _username.text = s.username;
    _smtpUsername = s.smtpUsername == s.username ? null : s.smtpUsername;
    _saveSentCopy = s.saveSentCopy;
  }

  /// Common defaults when nothing could be discovered.
  void _fillGuess(String email) {
    final domain = _filledFor = _domainOf(email);
    _fill(
      MailServerSettings(
        imap: ServerEndpoint(host: 'imap.$domain', port: 993, security: ConnectionSecurity.tls),
        smtp: ServerEndpoint(host: 'smtp.$domain', port: 465, security: ConnectionSecurity.tls),
        username: email,
      ),
    );
  }

  /// The server fields as settings, or null (with [_error] set) if they are
  /// incomplete.
  MailServerSettings? _readServers() {
    ServerEndpoint? endpoint(TextEditingController host, TextEditingController port, ConnectionSecurity security) {
      final h = host.text.trim();
      final p = int.tryParse(port.text.trim());
      if (h.isEmpty || p == null || p < 1 || p > 65535) return null;
      return ServerEndpoint(host: h, port: p, security: security);
    }

    final imap = endpoint(_imapHost, _imapPort, _imapSecurity);
    final smtp = endpoint(_smtpHost, _smtpPort, _smtpSecurity);
    final username = _username.text.trim();
    if (imap == null || smtp == null || username.isEmpty) {
      _error = 'Fill in both servers, their ports and your username.';
      return null;
    }
    for (final e in [imap, smtp]) {
      if (e.security == ConnectionSecurity.none && !e.isLocal) {
        _error = 'Unencrypted connections are only allowed to this computer (like Proton Mail Bridge).';
        return null;
      }
    }
    return MailServerSettings(
      imap: imap,
      smtp: smtp,
      username: username,
      smtpUsername: _smtpUsername,
      saveSentCopy: _saveSentCopy,
    );
  }

  Future<void> _submit() async {
    if (_busy != null) return;
    final email = _email.text.trim();
    setState(() {
      _error = null;
      _serverSaid = null;
    });
    if (!_isEmail(email)) {
      setState(() => _error = 'Enter your full email address.');
      return;
    }
    final unsupported = (_provider ?? _discovered?.provider)?.unsupportedReason;
    if (unsupported != null) {
      setState(() => _error = unsupported);
      return;
    }
    if (_password.text.isEmpty && widget.mode != ServerFormMode.edit) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    if (_adding && !_serversEdited && _filledFor != _domainOf(email)) {
      setState(() => _busy = _Busy.finding);
      final found = await _discover(email);
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _busy = null;
          _showServers = true;
          // The guesses are now the user's to review; the next attempt uses
          // them as they are.
          _fillGuess(email);
          _error = 'Plume couldn’t find the server settings for ${_domainOf(email)}. '
              'Check them below; your provider’s help pages list them.';
        });
        return;
      }
      if (found.provider?.unsupportedReason != null) {
        setState(() {
          _busy = null;
          _error = found.provider!.unsupportedReason;
        });
        return;
      }
      _fill(found.settings);
      _filledFor = _domainOf(email);
    }
    final settings = _readServers();
    if (settings == null) {
      setState(() {
        _busy = null;
        _showServers = true;
      });
      return;
    }

    setState(() => _busy = _Busy.checking);
    final provider = _provider ?? _discovered?.provider;
    final accounts = ref.read(accountsServiceProvider);
    try {
      final typed = cleanPassword(_password.text, provider);
      final password = typed.isEmpty ? await accounts.tokenSourceFor(widget.account!).accessToken() : typed;
      final verified = await verifyServerAccount(settings, password);
      final Account account;
      if (_adding) {
        account = await accounts.addServerAccount(
          email: email,
          name: _name.text,
          settings: verified,
          password: password,
        );
      } else {
        final name = _name.text.trim();
        account = widget.account!.copyWith(displayName: name.isEmpty ? email : name);
        await accounts.updateServerAccount(account, settings: verified, password: typed.isEmpty ? null : password);
      }
      if (mounted) widget.onDone(account, false);
    } on ConnectionCheckException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeServerProblem(e, provider: provider);
        _serverSaid = e.serverMessage;
        // Anything but a wrong password is fixed in the server settings.
        if (e.failure != ConnectionFailure.authFailed) _showServers = true;
      });
    } on DuplicateAccountException catch (e) {
      if (!mounted) return;
      if (e.existingKind != null) {
        setState(() => _error = '${e.email} is already in Plume with ${e.existingKind == 'gmail' ? 'Google sign-in' : 'another sign-in'}. '
            'Remove it first to switch.');
      } else {
        // Its password and settings were updated in place.
        final existing = (await ref.read(storeProvider).accounts())
            .where((a) => a.email.toLowerCase() == e.email.toLowerCase())
            .firstOrNull;
        if (mounted && existing != null) widget.onDone(existing, true);
      }
    } on MailException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      _log.warning('Account setup failed: $e');
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _setSecurity({required bool imap, required ConnectionSecurity security}) {
    // Move the port along when it is still the other mode's default.
    const defaults = {
      true: {ConnectionSecurity.tls: '993', ConnectionSecurity.startTls: '143', ConnectionSecurity.none: '143'},
      false: {ConnectionSecurity.tls: '465', ConnectionSecurity.startTls: '587', ConnectionSecurity.none: '587'},
    };
    final port = imap ? _imapPort : _smtpPort;
    final old = imap ? _imapSecurity : _smtpSecurity;
    if (port.text.trim().isEmpty || port.text.trim() == defaults[imap]![old]) port.text = defaults[imap]![security]!;
    setState(() {
      _serversEdited = true;
      if (imap) {
        _imapSecurity = security;
      } else {
        _smtpSecurity = security;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = _provider ?? _discovered?.provider;
    final busy = _busy != null;
    final unsupported = provider?.unsupportedReason != null;

    final title = switch (widget.mode) {
      ServerFormMode.add => 'Other mail account',
      ServerFormMode.edit => 'Server settings',
      ServerFormMode.reauth => 'Sign in again',
    };
    final subtitle = switch (widget.mode) {
      ServerFormMode.add => 'iCloud, Fastmail, Yahoo, your own server, or Gmail with an app password.',
      ServerFormMode.edit => widget.account!.email,
      ServerFormMode.reauth => '${widget.account!.email} stopped accepting its password. Enter it again to keep getting mail.',
    };

    return AbsorbPointer(
      absorbing: busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onBack != null) ...[
                IconButton(
                  tooltip: _adding ? 'Back' : 'Close',
                  onPressed: widget.onBack,
                  icon: Icon(_adding ? Symbols.arrow_back_rounded : Symbols.close_rounded),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.headlineSmallEmphasized),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.mode != ServerFormMode.reauth) ...[
            TextField(
              controller: _name,
              autofocus: _adding,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Your name', hintText: 'Shown to people you write to'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            focusNode: _emailFocus,
            enabled: _adding,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            onChanged: _emailChanged,
            decoration: const InputDecoration(labelText: 'Email address'),
          ),
          const SizedBox(height: 12),
          if (!unsupported)
            TextField(
              controller: _password,
              autofocus: widget.mode == ServerFormMode.reauth,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => unawaited(_submit()),
              decoration: InputDecoration(
                labelText: widget.mode == ServerFormMode.edit
                    ? 'New password'
                    : (provider?.needsAppPassword == true ? 'App password' : 'Password'),
                helperText: widget.mode == ServerFormMode.edit ? 'Leave empty to keep the current password' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Symbols.visibility_rounded : Symbols.visibility_off_rounded),
                ),
              ),
            ),
          _Reveal(
            visible: provider != null && (provider.needsAppPassword || unsupported || provider.note != null),
            child: provider == null ? const SizedBox.shrink() : _ProviderNote(provider: provider),
          ),
          const SizedBox(height: 8),
          if (!unsupported) ...[
            _ServersToggle(
              expanded: _showServers,
              summary: _serversSummary(),
              onPressed: () => setState(() {
                _showServers = !_showServers;
                final email = _email.text.trim();
                if (_showServers && _imapHost.text.isEmpty && _isEmail(email)) {
                  final found = _discovered;
                  if (found != null) {
                    _fill(found.settings);
                  } else {
                    _fillGuess(email);
                  }
                }
              }),
            ),
            _Reveal(
              visible: _showServers,
              child: _ServerFields(
                imapHost: _imapHost,
                imapPort: _imapPort,
                imapSecurity: _imapSecurity,
                smtpHost: _smtpHost,
                smtpPort: _smtpPort,
                smtpSecurity: _smtpSecurity,
                username: _username,
                onEdited: () => _serversEdited = true,
                onSecurity: _setSecurity,
              ),
            ),
          ],
          _Reveal(
            visible: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.error_rounded, size: 20, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error ?? '', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
                        if (_serverSaid != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SelectableText(
                              'The server said: “$_serverSaid”',
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: unsupported ? null : () => unawaited(_submit()),
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(56))),
            child: AnimatedSwitcher(
              duration: Spring.effects.duration,
              child: busy
                  ? Row(
                      key: ValueKey(_busy),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LoadingIndicator(size: 28, color: scheme.onPrimary),
                        const SizedBox(width: 12),
                        Text(_busy == _Busy.finding ? 'Finding your mail server…' : 'Checking your password…'),
                      ],
                    )
                  : Text(_adding ? 'Sign in' : 'Save', key: const ValueKey('idle')),
            ),
          ),
          if (_adding) ...[
            const SizedBox(height: 12),
            Text(
              'Your password is kept in your system keyring and only sent to your mail server.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  String _serversSummary() =>
      _imapHost.text.isEmpty ? 'Found from your address' : '${_imapHost.text} · ${_smtpHost.text}';
}

/// Expands and fades its child in and out with the spatial spring.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: Spring.spatial.duration,
        curve: Spring.spatial.curve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: Spring.effects.duration,
          child: visible ? KeyedSubtree(key: const ValueKey(true), child: child) : const SizedBox(width: double.infinity),
        ),
      );
}

/// App-password guidance (or why password sign-in can't work) for a
/// well-known provider.
class _ProviderNote extends StatelessWidget {
  const _ProviderNote({required this.provider});

  final ProviderInfo provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unsupported = provider.unsupportedReason;
    final help = provider.appPasswordHelp ?? provider.helpUrl;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: unsupported != null ? scheme.errorContainer : scheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    unsupported != null
                        ? Symbols.block_rounded
                        : (provider.needsAppPassword ? Symbols.key_rounded : Symbols.info_rounded),
                    size: 20,
                    color: unsupported != null ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      unsupported ??
                          provider.note ??
                          '${provider.name} needs an app password. Your normal password won’t work here. '
                              'Create an app password and paste it above.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: unsupported != null ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              if (unsupported == null && help != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => unawaited(launchUrl(help, mode: LaunchMode.externalApplication)),
                    icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                    label: Text(provider.appPasswordHelp != null ? 'Create app password' : 'Learn more'),
                  ),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServersToggle extends StatelessWidget {
  const _ServersToggle({required this.expanded, required this.summary, required this.onPressed});

  final bool expanded;
  final String summary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: Corners.all(Corners.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            SpringBuilder(
              value: expanded ? 1 : 0,
              spring: Spring.spatialFast,
              builder: (context, t, _) => Transform.rotate(
                angle: t * 1.5708,
                child: Icon(Symbols.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text('Server settings', style: theme.textTheme.titleSmallEmphasized),
            const SizedBox(width: 12),
            if (!expanded)
              Expanded(
                child: Text(
                  summary,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerFields extends StatelessWidget {
  const _ServerFields({
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    required this.username,
    required this.onEdited,
    required this.onSecurity,
  });

  final TextEditingController imapHost;
  final TextEditingController imapPort;
  final ConnectionSecurity imapSecurity;
  final TextEditingController smtpHost;
  final TextEditingController smtpPort;
  final ConnectionSecurity smtpSecurity;
  final TextEditingController username;
  final VoidCallback onEdited;
  final void Function({required bool imap, required ConnectionSecurity security}) onSecurity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget server({
      required String label,
      required TextEditingController host,
      required TextEditingController port,
      required ConnectionSecurity security,
      required bool imap,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: host,
                    onChanged: (_) => onEdited(),
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Server'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: port,
                    onChanged: (_) => onEdited(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ConnectionSecurity>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ConnectionSecurity.tls, label: Text('SSL/TLS')),
                  ButtonSegment(value: ConnectionSecurity.startTls, label: Text('STARTTLS')),
                  ButtonSegment(value: ConnectionSecurity.none, label: Text('None')),
                ],
                selected: {security},
                onSelectionChanged: (s) => onSecurity(imap: imap, security: s.single),
              ),
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              server(label: 'Incoming mail (IMAP)', host: imapHost, port: imapPort, security: imapSecurity, imap: true),
              const SizedBox(height: 20),
              server(label: 'Outgoing mail (SMTP)', host: smtpHost, port: smtpPort, security: smtpSecurity, imap: false),
              const SizedBox(height: 20),
              TextField(
                controller: username,
                onChanged: (_) => onEdited(),
                decoration: const InputDecoration(labelText: 'Username', helperText: 'Usually your full email address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
