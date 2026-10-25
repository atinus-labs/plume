import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/avatars.dart';
import '../onboarding/add_account.dart';

/// Picks which account the navigation shows, including the unified view.
class AccountSwitcher extends ConsumerStatefulWidget {
  const AccountSwitcher({super.key, required this.t});

  /// Rail expansion progress.
  final double t;

  @override
  ConsumerState<AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends ConsumerState<AccountSwitcher> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final view = ref.watch(viewProvider);
    final statuses = ref.watch(syncStatusProvider).value ?? const {};
    // With a single account, "all inboxes" is that account.
    final current = accounts.where((a) => a.id == view.accountId).firstOrNull ??
        (accounts.length == 1 ? accounts.first : null);
    final needsAttention = accounts.any((a) => a.status == AccountStatus.needsReauth);
    final syncing = statuses.values.any((s) => s.phase == SyncPhase.syncing);
    final t = widget.t;

    Widget avatarFor(Account? account, {double size = 36}) => account == null
        ? _StackedAvatars(accounts: accounts, size: size)
        : MorphAvatar(
            name: account.displayName,
            colorKey: account.email,
            image: ref.watch(accountAvatarProvider(account)).value,
            size: size,
          );

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(300, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge))),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
      menuChildren: [
        _AccountItem(
          leading: _StackedAvatars(accounts: accounts, size: 36),
          title: 'All inboxes',
          subtitle: '${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}',
          selected: view.accountId == null,
          onTap: () => ref.read(viewProvider.notifier).show(view.forAccount(null)),
        ),
        for (final a in accounts)
          _AccountItem(
            leading: avatarFor(a),
            title: a.displayName,
            subtitle: a.email,
            selected: view.accountId == a.id,
            warning: a.status == AccountStatus.needsReauth ? 'Sign in again' : null,
            onTap: () => ref.read(viewProvider.notifier).show(view.forAccount(a.id)),
          ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12), child: Divider()),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.person_add_rounded),
          onPressed: () => showAddAccountDialog(context),
          child: const Text('Add account'),
        ),
      ],
      builder: (context, controller, _) {
        return Material(
          color: t > 0.5 ? scheme.surfaceContainerHigh : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: EdgeInsets.all(t > 0.5 ? 8 : 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Center(
                      child: Badge(
                        isLabelVisible: needsAttention,
                        backgroundColor: scheme.error,
                        smallSize: 10,
                        child: avatarFor(current, size: 40),
                      ),
                    ),
                  ),
                  if (t > 0.4)
                    Expanded(
                      child: Opacity(
                        opacity: unit((t - 0.4) / 0.6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              current?.displayName ?? 'All inboxes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLargeEmphasized,
                            ),
                            Text(
                              syncing ? 'Checking for mail…' : (current?.email ?? '${accounts.length} accounts'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (t > 0.6) Icon(Symbols.unfold_more_rounded, color: scheme.onSurfaceVariant, size: 20),
                  if (t > 0.6) const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountItem extends StatelessWidget {
  const _AccountItem({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.warning,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            onTap();
            MenuController.maybeOf(context)?.close();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelLargeEmphasized, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        warning ?? subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: warning != null ? scheme.error : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Symbols.check_rounded, color: scheme.onSecondaryContainer, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three overlapping account avatars for the unified view.
class _StackedAvatars extends ConsumerWidget {
  const _StackedAvatars({required this.accounts, required this.size});

  final List<Account> accounts;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (accounts.length <= 1) {
      return SizedBox.square(
        dimension: size,
        child: Material(
          color: scheme.tertiaryContainer,
          shape: RadialShapeBorder(Shapes.cookie9),
          child: Icon(Symbols.all_inbox_rounded, size: size * 0.5, color: scheme.onTertiaryContainer),
        ),
      );
    }
    final shown = accounts.take(3).toList();
    final small = size * 0.62;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - small) / (shown.length - 1).clamp(1, 3),
              top: i.isEven ? 0 : size - small,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.surfaceContainerHigh, width: 2)),
                child: MorphAvatar(name: shown[i].displayName, colorKey: shown[i].email, image: ref.watch(accountAvatarProvider(shown[i])).value, size: small - 4),
              ),
            ),
        ],
      ),
    );
  }
}
