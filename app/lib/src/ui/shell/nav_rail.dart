import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/settings.dart';
import '../compose/compose_host.dart';
import 'account_switcher.dart';

const _collapsedWidth = 88.0;
const _expandedWidth = 272.0;

/// The M3 Expressive navigation rail. Springs between a compact icon rail
/// and an expanded rail with labels, label list and counts.
class NavRail extends ConsumerWidget {
  const NavRail({super.key, required this.expanded, this.onOpenSettings, this.inDrawer = false});

  final bool expanded;
  final VoidCallback? onOpenSettings;

  /// Rendered inside a modal drawer on compact windows.
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpringBuilder(
      value: expanded ? 1 : 0,
      spring: Spring.spatial,
      builder: (context, t, _) {
        // Overshoot past the expanded width is welcome; below the collapsed
        // width it would squeeze the icons, so that side is clamped.
        final width = math.max(_collapsedWidth, _collapsedWidth + (_expandedWidth - _collapsedWidth) * t);
        return SizedBox(
          width: width,
          child: _RailBody(t: t, inDrawer: inDrawer, onOpenSettings: onOpenSettings),
        );
      },
    );
  }
}

class _RailBody extends ConsumerWidget {
  const _RailBody({required this.t, required this.inDrawer, this.onOpenSettings});

  final double t;
  final bool inDrawer;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final settings = ref.watch(settingsProvider);
    final showLabels = t > 0.5;
    final accountId = view.accountId;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final mailboxes = ref.watch(mailboxesProvider(accountId)).value ?? const <Mailbox>[];
    final labels = mailboxes.where((m) => m.kind == MailboxKind.user && !m.hidden).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final categories = ref.watch(hasCategoriesProvider) && settings.categoryTabs;
    final hasArchive = mailboxes.any((m) => m.role == MailboxRole.archive);
    final folderAccounts = {
      for (final a in accounts)
        if (ref.watch(usesFoldersProvider(a.id))) a.id,
    };
    final labelsTitle = switch (labels.where((l) => folderAccounts.contains(l.accountId)).length) {
      0 => 'Labels',
      final n when n == labels.length => 'Folders',
      _ => 'Labels and folders',
    };

    MailView make(ViewKind kind) => MailView(kind, accountId: accountId, category: kind == ViewKind.inbox && categories ? MailCategory.primary : null);
    bool isActive(ViewKind kind, {String? mailboxId}) =>
        view.kind == kind && (kind != ViewKind.label || view.mailboxId == mailboxId);

    final inboxUnread = ref
            .watch(unreadCountProvider(RoleFilter(MailboxRole.inbox,
                accountIds: accountId == null ? null : {accountId},
                category: categories ? MailCategory.primary : null)))
            .value ??
        0;
    final drafts = ref.watch(threadsProvider(RoleFilter(MailboxRole.drafts, accountIds: accountId == null ? null : {accountId}))).value?.length ?? 0;

    final destinations = <Widget>[
      _Destination(icon: Symbols.inbox_rounded, label: 'Inbox', t: t, active: isActive(ViewKind.inbox), badge: inboxUnread, onTap: () => _go(context, ref, make(ViewKind.inbox))),
      _Destination(icon: Symbols.star_rounded, label: 'Starred', t: t, active: isActive(ViewKind.starred), onTap: () => _go(context, ref, make(ViewKind.starred))),
      _Destination(icon: Symbols.send_rounded, label: 'Sent', t: t, active: isActive(ViewKind.sent), onTap: () => _go(context, ref, make(ViewKind.sent))),
      _Destination(icon: Symbols.draft_rounded, label: 'Drafts', t: t, active: isActive(ViewKind.drafts), badge: drafts, badgeMuted: true, onTap: () => _go(context, ref, make(ViewKind.drafts))),
      if (hasArchive)
        _Destination(icon: Symbols.archive_rounded, label: 'Archive', t: t, active: isActive(ViewKind.archive), onTap: () => _go(context, ref, make(ViewKind.archive))),
      _Destination(icon: Symbols.stacks_rounded, label: 'All mail', t: t, active: isActive(ViewKind.allMail), onTap: () => _go(context, ref, make(ViewKind.allMail))),
      _Destination(icon: Symbols.report_rounded, label: 'Spam', t: t, active: isActive(ViewKind.junk), onTap: () => _go(context, ref, make(ViewKind.junk))),
      _Destination(icon: Symbols.delete_rounded, label: 'Trash', t: t, active: isActive(ViewKind.trash), onTap: () => _go(context, ref, make(ViewKind.trash))),
    ];

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.md),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: inDrawer
              ? const SizedBox(height: 8)
              : IconButton(
                  tooltip: showLabels ? 'Collapse navigation' : 'Expand navigation',
                  onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(railExpanded: !s.railExpanded)),
                  icon: Icon(showLabels ? Symbols.menu_open_rounded : Symbols.menu_rounded),
                ),
        ),
        const SizedBox(height: Space.sm),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: _ComposeFab(t: t, onPressed: () {
            if (inDrawer) Navigator.of(context).maybePop();
            ref.read(composeProvider.notifier).newMessage();
          }),
        ),
        const SizedBox(height: Space.lg),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ...destinations,
                if (labels.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  if (showLabels)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Opacity(
                        opacity: unit((t - 0.5) * 2),
                        child: Text(labelsTitle, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider()),
                  for (final label in labels)
                    _Destination(
                      icon: folderAccounts.contains(label.accountId) ? Symbols.folder_rounded : Symbols.label_rounded,
                      iconColor: label.color == null ? null : harmonize(Color(label.color!), theme.colorScheme),
                      label: accounts.length > 1 && accountId == null ? '${label.name} · ${_accountShort(accounts, label.accountId)}' : label.name,
                      t: t,
                      active: isActive(ViewKind.label, mailboxId: label.id) && view.accountId == label.accountId,
                      badge: label.unreadThreads,
                      badgeMuted: true,
                      onTap: () => _go(context, ref, MailView(ViewKind.label, accountId: label.accountId, mailboxId: label.id)),
                    ),
                ],
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: _Destination(
            icon: Symbols.settings_rounded,
            label: 'Settings',
            t: t,
            active: false,
            onTap: () {
              if (inDrawer) Navigator.of(context).maybePop();
              onOpenSettings?.call();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: AccountSwitcher(t: t),
        ),
      ],
    );
  }

  static String _accountShort(List<Account> accounts, String id) {
    final a = accounts.where((a) => a.id == id).firstOrNull;
    if (a == null) return '';
    final at = a.email.indexOf('@');
    return at > 0 ? a.email.substring(0, at) : a.email;
  }

  void _go(BuildContext context, WidgetRef ref, MailView view) {
    ref.read(viewProvider.notifier).show(view);
    if (inDrawer) Navigator.of(context).maybePop();
  }
}

/// A rail destination. Collapsed: an icon in a pill indicator. Expanded:
/// a full-width pill with label and count.
class _Destination extends StatefulWidget {
  const _Destination({
    required this.icon,
    required this.label,
    required this.t,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.badgeMuted = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final double t;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  final bool badgeMuted;
  final Color? iconColor;

  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = widget.t;
    final labelOpacity = unit((t - 0.35) / 0.65);
    final fg = widget.active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    final content = LayoutBuilder(builder: (context, constraints) {
      final rowWidth = constraints.maxWidth;
      return SizedBox(
      height: 52,
      child: Stack(
        children: [
          // The active indicator grows from the icon outwards.
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SpringBuilder(
                value: widget.active ? 1 : 0,
                spring: Spring.spatialFast,
                builder: (context, a, _) {
                  final ut = unit(t);
                  final fullWidth = math.min(rowWidth, 64 + (rowWidth - 64) * ut);
                  final w = (fullWidth * (0.55 + 0.45 * a)).clamp(0.0, rowWidth);
                  return Padding(
                    padding: EdgeInsets.only(left: math.max(0.0, (fullWidth - w) / 2 * (1 - ut))),
                    child: Opacity(
                      opacity: unit(a),
                      child: Container(
                        width: w,
                        height: t > 0.5 ? 52 : 36,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: Corners.all(Corners.full),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_hover && !widget.active)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: math.min(rowWidth, 64 + (rowWidth - 64) * unit(t)),
                  height: t > 0.5 ? 52 : 36,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: Corners.all(Corners.full),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Row(
              children: [
                SizedBox(
                  width: math.min(64.0, rowWidth),
                  child: Center(
                    child: Badge(
                      isLabelVisible: widget.badge > 0 && t < 0.5 && !widget.badgeMuted,
                      label: Text(widget.badge > 99 ? '99+' : '${widget.badge}'),
                      child: SpringBuilder(
                        value: widget.active ? 1 : 0,
                        spring: Spring.effects,
                        builder: (context, f, _) => Icon(
                          widget.icon,
                          fill: unit(f),
                          weight: 400 + 100 * unit(f),
                          color: widget.iconColor ?? fg,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                if (labelOpacity > 0)
                  Expanded(
                    child: Opacity(
                      opacity: labelOpacity,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: (widget.active ? theme.textTheme.labelLargeEmphasized : theme.textTheme.labelLarge)
                                  ?.copyWith(color: fg),
                            ),
                          ),
                          if (widget.badge > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 16, left: 8),
                              child: Text(
                                '${widget.badge}',
                                style: (widget.badgeMuted ? theme.textTheme.labelMedium : theme.textTheme.labelMediumEmphasized)
                                    ?.copyWith(color: widget.badgeMuted ? scheme.onSurfaceVariant : scheme.primary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    });

    return Tooltip(
      message: t < 0.5 ? widget.label : '',
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: content),
      ),
    );
  }
}

/// The compose FAB, extending into a labelled FAB as the rail expands.
class _ComposeFab extends StatelessWidget {
  const _ComposeFab({required this.t, required this.onPressed});

  final double t;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = math.max(56.0, 56 + (136 - 56) * t);
    return Tooltip(
      message: t < 0.5 ? 'Compose (C)' : '',
      child: SizedBox(
        width: width,
        height: 56,
        child: Material(
          color: scheme.primaryContainer,
          elevation: 2,
          shadowColor: scheme.shadow.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Row(
              children: [
                SizedBox(width: 56, child: Icon(Symbols.edit_rounded, color: scheme.onPrimaryContainer, weight: 500)),
                if (t > 0.3)
                  Expanded(
                    child: Opacity(
                      opacity: unit((t - 0.3) / 0.7),
                      child: Text(
                        'Compose',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: theme.textTheme.titleSmallEmphasized.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
