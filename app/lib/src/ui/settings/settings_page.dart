import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../config.dart';
import '../../services/desktop.dart';
import '../../services/imap_connector.dart';
import '../../state/mail.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../actions.dart';
import '../common/logo.dart';
import '../onboarding/add_account.dart';
import '../onboarding/server_account_form.dart';
import '../shell/title_bar.dart';

/// Settings, laid out as M3 Expressive grouped lists.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surfaces = PlumeSurfaces.of(context);
    final desktop = ref.watch(desktopProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final statuses = ref.watch(syncStatusProvider).value ?? const {};

    return Scaffold(
      backgroundColor: surfaces.window,
      body: Column(
        children: [
          if (desktop.drawsWindowControls) const WindowTitleBar(),
          Expanded(
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
              child: Focus(
                autofocus: true,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                      children: [
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Back (Esc)',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Symbols.arrow_back_rounded),
                            ),
                            const SizedBox(width: 16),
                            Text('Settings', style: theme.textTheme.headlineMediumEmphasized),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _Section(title: 'Accounts', children: [
                          for (final a in accounts)
                            _AccountRow(account: a, status: statuses[a.id]),
                          _Row(
                            icon: Symbols.person_add_rounded,
                            title: 'Add account',
                            onTap: () => showAddAccountDialog(context),
                          ),
                        ]),
                        _Section(title: 'Appearance', children: [
                          _Row(
                            icon: Symbols.dark_mode_rounded,
                            title: 'Theme',
                            trailing: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                              ],
                              selected: {settings.themeMode},
                              onSelectionChanged: (v) => notifier.update((s) => s.copyWith(themeMode: v.first)),
                            ),
                          ),
                          _Row(
                            icon: Symbols.palette_rounded,
                            title: 'Colour',
                            subtitle: settings.colorSource == ColorSource.system
                                ? (desktop.appearance.accent != null ? 'Following your desktop accent colour' : 'Plume blue (your desktop has no accent colour)')
                                : 'Custom',
                            below: _ColorPicker(settings: settings, onChanged: notifier.update),
                          ),
                          _SwitchRow(
                            icon: Symbols.tab_rounded,
                            title: 'Inbox categories',
                            subtitle: 'Split Gmail inboxes into Primary, Promotions, Social and Updates',
                            value: settings.categoryTabs,
                            onChanged: (v) => notifier.update((s) => s.copyWith(categoryTabs: v)),
                          ),
                        ]),
                        _Section(title: 'Notifications', children: [
                          _SwitchRow(
                            icon: Symbols.notifications_rounded,
                            title: 'New mail notifications',
                            value: settings.notifications,
                            onChanged: (v) => notifier.update((s) => s.copyWith(notifications: v)),
                          ),
                          _SwitchRow(
                            icon: Symbols.filter_alt_rounded,
                            title: 'Only for Primary',
                            subtitle: 'Skip promotions, social and update emails',
                            value: settings.notifyPrimaryOnly,
                            enabled: settings.notifications,
                            onChanged: (v) => notifier.update((s) => s.copyWith(notifyPrimaryOnly: v)),
                          ),
                          _SwitchRow(
                            icon: Symbols.volume_up_rounded,
                            title: 'Sound',
                            value: settings.notificationSound,
                            enabled: settings.notifications,
                            onChanged: (v) => notifier.update((s) => s.copyWith(notificationSound: v)),
                          ),
                        ]),
                        _Section(title: 'Reading & sending', children: [
                          _Row(
                            icon: Symbols.image_rounded,
                            title: 'Images in messages',
                            subtitle: 'Loading images lets senders see when you open their mail',
                            trailing: SegmentedButton<RemoteImages>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: RemoteImages.ask, label: Text('Ask')),
                                ButtonSegment(value: RemoteImages.always, label: Text('Always')),
                              ],
                              selected: {settings.remoteImages},
                              onSelectionChanged: (v) => notifier.update((s) => s.copyWith(remoteImages: v.first)),
                            ),
                          ),
                          _Row(
                            icon: Symbols.arrow_forward_rounded,
                            title: 'After archiving or deleting',
                            trailing: DropdownMenu<AfterAction>(
                              initialSelection: settings.afterAction,
                              inputDecorationTheme: const InputDecorationTheme(isDense: true),
                              onSelected: (v) => notifier.update((s) => s.copyWith(afterAction: v)),
                              dropdownMenuEntries: const [
                                DropdownMenuEntry(value: AfterAction.nextOlder, label: 'Open older'),
                                DropdownMenuEntry(value: AfterAction.nextNewer, label: 'Open newer'),
                                DropdownMenuEntry(value: AfterAction.list, label: 'Back to list'),
                              ],
                            ),
                          ),
                          _Row(
                            icon: Symbols.undo_rounded,
                            title: 'Undo send',
                            subtitle: 'How long you can take a message back after sending',
                            trailing: DropdownMenu<int>(
                              initialSelection: settings.undoSendSeconds,
                              onSelected: (v) => notifier.update((s) => s.copyWith(undoSendSeconds: v)),
                              dropdownMenuEntries: const [
                                DropdownMenuEntry(value: 0, label: 'Off'),
                                DropdownMenuEntry(value: 5, label: '5 seconds'),
                                DropdownMenuEntry(value: 10, label: '10 seconds'),
                                DropdownMenuEntry(value: 20, label: '20 seconds'),
                                DropdownMenuEntry(value: 30, label: '30 seconds'),
                              ],
                            ),
                          ),
                        ]),
                        _Section(title: 'System', children: [
                          _SwitchRow(
                            icon: Symbols.background_replace_rounded,
                            title: 'Keep running when closed',
                            subtitle: desktop.hasTray
                                ? 'Plume stays in the tray and keeps checking for mail'
                                : 'No tray found; closing the window quits Plume',
                            value: settings.runInBackground && desktop.hasTray,
                            enabled: desktop.hasTray,
                            onChanged: (v) {
                              notifier.update((s) => s.copyWith(runInBackground: v));
                              unawaited(desktop.setPreventClose(v));
                            },
                          ),
                          const _AutostartRow(),
                          const _DefaultMailAppRow(),
                          _Row(
                            icon: Symbols.key_rounded,
                            title: 'Credentials',
                            subtitle: 'Stored in: ${ref.watch(servicesProvider).secrets.backend}',
                          ),
                        ]),
                        _Section(title: 'Help', children: [
                          _Row(
                            icon: Symbols.keyboard_rounded,
                            title: 'Keyboard shortcuts',
                            onTap: () => showDialog<void>(context: context, builder: (_) => const _ShortcutsDialog()),
                          ),
                          _Row(
                            leading: const ExcludeSemantics(child: PlumeLogo(size: 32)),
                            title: AppConfig.appName,
                            subtitle: 'Version 0.1.0 · ${AppConfig.appId}',
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(title, style: theme.textTheme.titleSmallEmphasized.copyWith(color: theme.colorScheme.primary)),
          ),
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: PlumeSurfaces.of(context).item,
                shape: RoundedRectangleBorder(borderRadius: groupedRadius(i, children.length)),
                clipBehavior: Clip.antiAlias,
                child: children[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({this.icon, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.below})
      : assert((icon == null) != (leading == null));

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                leading ?? Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 16), trailing!],
              ],
            ),
            if (below != null) Padding(padding: const EdgeInsets.only(left: 42, top: 14), child: below),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: _Row(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: enabled ? () => onChanged(!value) : null,
          trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
        ),
      );
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.settings, required this.onChanged});

  final AppSettings settings;
  final void Function(AppSettings Function(AppSettings)) onChanged;

  static const _swatches = [0xFF4C5BD4, 0xFF006A6A, 0xFF386A20, 0xFF8B5000, 0xFFB3261E, 0xFF984061, 0xFF6750A4, 0xFF5B5F71];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch({required Color color, required bool selected, required VoidCallback onTap, IconData? icon, String? tooltip}) {
      return Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SpringBuilder(
              value: selected ? 1 : 0,
              spring: Spring.spatialFast,
              builder: (context, t, _) => SizedBox.square(
                dimension: 44,
                child: Material(
                  color: color,
                  shape: RadialShapeBorder(RadialShape.lerp(Shapes.circle, Shapes.cookie9, unit(t)),
                      side: BorderSide(color: scheme.outlineVariant, width: selected ? 0 : 1)),
                  child: icon != null
                      ? Icon(icon, color: Colors.white, size: 20)
                      : (t > 0.05 ? Opacity(opacity: unit(t), child: const Icon(Symbols.check_rounded, color: Colors.white, size: 20)) : null),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        swatch(
          color: scheme.primary,
          selected: settings.colorSource == ColorSource.system,
          icon: Symbols.wallpaper_rounded,
          tooltip: 'Follow desktop',
          onTap: () => onChanged((s) => s.copyWith(colorSource: ColorSource.system)),
        ),
        for (final c in _swatches)
          swatch(
            color: Color(c),
            selected: settings.colorSource == ColorSource.custom && settings.customSeed == c,
            onTap: () => onChanged((s) => s.copyWith(colorSource: ColorSource.custom, customSeed: c)),
          ),
      ],
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account, required this.status});

  final Account account;
  final AccountSyncStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needsReauth = account.status == AccountStatus.needsReauth;
    final detail = needsReauth
        ? 'Needs you to sign in again'
        : switch (status?.phase) {
            SyncPhase.syncing => 'Syncing…',
            SyncPhase.offline => 'Offline · will retry',
            _ => status?.lastSynced == null ? account.email : '${account.email} · up to date${status!.pushConnected ? ', live' : ''}',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          MorphAvatar(
            name: account.displayName,
            colorKey: account.email,
            image: account.avatarUrl == null ? null : NetworkImage(account.avatarUrl!),
            size: 44,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.displayName, style: theme.textTheme.titleSmallEmphasized),
                Text(detail, style: theme.textTheme.bodyMedium?.copyWith(color: needsReauth ? scheme.error : scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (needsReauth)
            FilledButton.tonal(
              onPressed: () => unawaited(signInAgain(context, ref, account)),
              child: const Text('Sign in'),
            ),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Symbols.signature_rounded),
                onPressed: () => _editSignature(context, ref),
                child: const Text('Signature…'),
              ),
              if (account.provider == ImapConnector.kindId)
                MenuItemButton(
                  leadingIcon: const Icon(Symbols.dns_rounded),
                  onPressed: () => unawaited(showServerAccountDialog(context, account, mode: ServerFormMode.edit)),
                  child: const Text('Server settings…'),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Symbols.sync_rounded),
                onPressed: () => unawaited(ref.read(engineProvider).syncAccount(account.id)),
                child: const Text('Sync now'),
              ),
              MenuItemButton(
                leadingIcon: Icon(Symbols.logout_rounded, color: scheme.error),
                onPressed: () => _confirmRemove(context, ref),
                child: Text('Remove account', style: TextStyle(color: scheme.error)),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              tooltip: 'Account options',
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Symbols.more_vert_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSignature(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: account.signature ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signature'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 6,
            minLines: 3,
            autofocus: true,
            decoration: InputDecoration(hintText: 'Added to new messages from ${account.email}'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final trimmed = result.trim();
    await ref.read(storeProvider).saveAccount(
        trimmed.isEmpty ? account.copyWith(clearSignature: true) : account.copyWith(signature: trimmed));
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.logout_rounded),
        title: Text('Remove ${account.email}?'),
        content: const Text('Downloaded mail for this account is deleted from this computer. Nothing is deleted from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(accountsServiceProvider).remove(account);
    showSnack('${account.email} removed');
  }
}

class _AutostartRow extends ConsumerStatefulWidget {
  const _AutostartRow();

  @override
  ConsumerState<_AutostartRow> createState() => _AutostartRowState();
}

class _AutostartRowState extends ConsumerState<_AutostartRow> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(desktopProvider).isAutostartEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = ref.watch(desktopProvider);
    return _SwitchRow(
      icon: Symbols.power_settings_new_rounded,
      title: 'Start on login',
      subtitle: desktop.autostartSupported
          ? 'Open Plume in the background when you log in'
          : 'Your session doesn’t run autostart entries. Add “plume --background” to your compositor’s startup commands (e.g. exec-once in Hyprland).',
      value: _enabled ?? false,
      enabled: _enabled != null,
      onChanged: (v) async {
        setState(() => _enabled = v);
        await desktop.setAutostart(v);
      },
    );
  }
}

class _DefaultMailAppRow extends ConsumerStatefulWidget {
  const _DefaultMailAppRow();

  @override
  ConsumerState<_DefaultMailAppRow> createState() => _DefaultMailAppRowState();
}

class _DefaultMailAppRowState extends ConsumerState<_DefaultMailAppRow> with WidgetsBindingObserver {
  DefaultMailAppStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The default may have changed in the system settings meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final status = await ref.read(desktopProvider).defaultMailAppStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _makeDefault() async {
    setState(() => _busy = true);
    try {
      await ref.read(desktopProvider).makeDefaultMailApp();
    } catch (e) {
      showSnack('Couldn’t make Plume the default: $e');
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return _Row(
      icon: Symbols.alternate_email_rounded,
      title: 'Default mail app',
      subtitle: switch (status) {
        null => null,
        DefaultMailAppStatus.isDefault => 'Email links open in Plume',
        DefaultMailAppStatus.notDefault => 'Email links open in another app',
        DefaultMailAppStatus.notInstalled =>
          'Install Plume with tool/install.sh so email links can open it',
        DefaultMailAppStatus.outdatedEntry =>
          'Plume’s launcher entry is out of date. Run tool/install.sh again so email links can open it.',
        DefaultMailAppStatus.unsupported => 'Choose Plume as the email app in your system settings',
      },
      trailing: switch (status) {
        DefaultMailAppStatus.notDefault => FilledButton.tonal(
            onPressed: _busy ? null : _makeDefault,
            child: const Text('Make default'),
          ),
        DefaultMailAppStatus.isDefault => Icon(Symbols.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
        _ => null,
      },
    );
  }
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rows = [
      ('C', 'Compose'),
      ('/', 'Search'),
      ('J / K', 'Older / newer conversation'),
      ('Enter', 'Open conversation'),
      ('E', 'Archive'),
      ('#', 'Delete'),
      ('!', 'Report spam'),
      ('S', 'Star / unstar'),
      ('Shift+U / Shift+I', 'Mark unread / read'),
      ('R / A / F', 'Reply / reply all / forward'),
      ('X', 'Select conversation'),
      ('Esc', 'Close / clear selection'),
      ('Ctrl+Enter', 'Send'),
      ('F5', 'Check for mail'),
      ('Ctrl+,', 'Settings'),
    ];
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, label) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: Corners.all(Corners.small),
                      ),
                      child: Text(key, style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}
