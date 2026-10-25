import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/navigation.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../actions.dart';
import '../common/empty_state.dart';
import '../common/format.dart';
import '../search/search_field.dart';
import 'thread_tile.dart';

/// The message list: search, title, category tabs and grouped conversations.
class ThreadListPane extends ConsumerStatefulWidget {
  const ThreadListPane({super.key, this.onOpenDrawer});

  /// Shown as a menu button on compact windows without a rail.
  final VoidCallback? onOpenDrawer;

  @override
  ConsumerState<ThreadListPane> createState() => _ThreadListPaneState();
}

class _ThreadListPaneState extends ConsumerState<ThreadListPane> {
  final _scroll = ScrollController();
  bool _loadingMore = false;
  bool _noMore = false;
  ThreadFilter? _lastFilter;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_loadingMore || _noMore || !_scroll.hasClients) return;
    if (ref.read(searchProvider).active) return;
    if (_scroll.position.extentAfter > 600) return;
    final filter = ref.read(viewProvider).toFilter();
    setState(() => _loadingMore = true);
    unawaited(ref.read(engineProvider).loadMore(filter).then((more) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _noMore = !more;
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(viewProvider);
    final filter = view.toFilter();
    if (filter != _lastFilter) {
      _lastFilter = filter;
      _noMore = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    final threads = ref.watch(visibleThreadsProvider);
    final accounts = ref.watch(accountMapProvider);
    final statuses = ref.watch(syncStatusProvider).value ?? const {};
    final search = ref.watch(searchProvider);
    final relevant = view.accountId == null ? statuses.values : [?statuses[view.accountId]];
    final initialSync = relevant.isNotEmpty && relevant.every((s) => !s.initialSyncDone);
    final syncing = relevant.any((s) => s.phase == SyncPhase.syncing);

    return Column(
      children: [
        _Header(onOpenDrawer: widget.onOpenDrawer),
        AnimatedSwitcher(
          duration: Spring.effects.duration,
          child: (syncing && !initialSync) || search.searchingServer
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: WavyProgressIndicator(height: 8),
                )
              : const SizedBox(height: 24),
        ),
        Expanded(
          child: threads.when(
            loading: () => const Center(child: LoadingIndicator()),
            error: (e, _) => EmptyState(icon: Symbols.error_rounded, title: 'Couldn’t load mail', message: '$e'),
            data: (list) {
              if (list.isEmpty) {
                if (initialSync && !search.active) {
                  return const EmptyState(
                    icon: Symbols.downloading_rounded,
                    shape: null,
                    title: 'Setting up your inbox',
                    message: 'Plume is downloading your recent mail. This only takes a moment the first time.',
                    action: LoadingIndicator(),
                  );
                }
                return _emptyFor(view, search);
              }
              return _GroupedList(
                threads: list,
                accounts: accounts,
                controller: _scroll,
                unified: view.accountId == null && accounts.length > 1,
                grouped: !search.active,
                footer: _loadingMore
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: LoadingIndicator(size: 36)))
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyFor(MailView view, SearchState search) {
    if (search.active) {
      return EmptyState(
        icon: Symbols.search_off_rounded,
        shape: Shapes.clover4,
        title: 'No results',
        message: search.serverResults == null
            ? 'Nothing in your downloaded mail matches. Press Enter to search the server.'
            : 'No messages match “${search.query}”.',
      );
    }
    return switch (view.kind) {
      ViewKind.inbox => EmptyState(
          icon: Symbols.done_all_rounded,
          shape: Shapes.sunny,
          title: 'You’re all caught up',
          message: view.category == null || view.category == MailCategory.primary
              ? 'Nothing new in your inbox.'
              : 'Nothing in ${_categoryName(view.category!)}.',
        ),
      ViewKind.starred => EmptyState(
          icon: Symbols.star_rounded, shape: Shapes.burst, title: 'No starred mail', message: 'Star important messages to find them here.'),
      ViewKind.drafts => const EmptyState(icon: Symbols.draft_rounded, title: 'No drafts'),
      ViewKind.archive => const EmptyState(icon: Symbols.archive_rounded, title: 'Nothing archived'),
      ViewKind.sent => const EmptyState(icon: Symbols.send_rounded, title: 'Nothing sent yet'),
      ViewKind.junk => EmptyState(icon: Symbols.verified_user_rounded, shape: Shapes.gem, title: 'No spam', message: 'Hooray, no spam here.'),
      ViewKind.trash => EmptyState(icon: Symbols.delete_rounded, shape: Shapes.puffy, title: 'Trash is empty'),
      _ => const EmptyState(icon: Symbols.mail_rounded, title: 'No conversations'),
    };
  }
}

String _categoryName(MailCategory c) => switch (c) {
      MailCategory.primary => 'Primary',
      MailCategory.social => 'Social',
      MailCategory.promotions => 'Promotions',
      MailCategory.updates => 'Updates',
      MailCategory.forums => 'Forums',
    };

String viewTitle(MailView view, List<Mailbox> mailboxes) => switch (view.kind) {
      ViewKind.inbox => 'Inbox',
      ViewKind.starred => 'Starred',
      ViewKind.sent => 'Sent',
      ViewKind.drafts => 'Drafts',
      ViewKind.archive => 'Archive',
      ViewKind.allMail => 'All mail',
      ViewKind.junk => 'Spam',
      ViewKind.trash => 'Trash',
      ViewKind.label => mailboxes.where((m) => m.id == view.mailboxId).firstOrNull?.name ?? 'Label',
    };

/// Search, title and tabs, or the contextual selection toolbar.
class _Header extends ConsumerWidget {
  const _Header({this.onOpenDrawer});

  final VoidCallback? onOpenDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (onOpenDrawer != null)
                IconButton(onPressed: onOpenDrawer, icon: const Icon(Symbols.menu_rounded), tooltip: 'Navigation'),
              const Expanded(child: SearchField()),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: Spring.standardFast.duration,
            switchInCurve: Spring.standardFast.curve,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: child),
            ),
            child: selection.isEmpty ? const _TitleRow(key: ValueKey('title')) : _SelectionBar(key: const ValueKey('sel'), count: selection.length),
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(viewProvider);
    final search = ref.watch(searchProvider);
    final mailboxes = ref.watch(mailboxesProvider(view.accountId)).value ?? const <Mailbox>[];
    final tabs = view.kind == ViewKind.inbox && ref.watch(hasCategoriesProvider) && ref.watch(settingsProvider).categoryTabs;
    final accounts = ref.watch(accountMapProvider);
    final scope = view.accountId == null
        ? (accounts.length > 1 ? 'All accounts' : null)
        : accounts[view.accountId]?.email;
    final unread = view.kind == ViewKind.inbox
        ? ref.watch(unreadCountProvider(view.toFilter())).value ?? 0
        : 0;

    if (search.active) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                search.serverResults == null ? 'Downloaded mail' : 'Results from the server',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const _SyncButton(),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        viewTitle(view, mailboxes),
                        style: theme.textTheme.headlineMediumEmphasized,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: Corners.all(Corners.full)),
                        child: Text('$unread new', style: theme.textTheme.labelMediumEmphasized.copyWith(color: theme.colorScheme.onPrimary)),
                      ),
                    ],
                  ],
                ),
              ),
              if (scope != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(
                    scope,
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              const _SyncButton(),
            ],
          ),
        ),
        if (tabs) ...[
          const SizedBox(height: 12),
          _CategoryTabs(view: view),
        ],
      ],
    );
  }
}

class _SyncButton extends ConsumerStatefulWidget {
  const _SyncButton();

  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(syncStatusProvider).value ?? const {};
    final syncing = statuses.values.any((s) => s.phase == SyncPhase.syncing);

    if (syncing) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.reset();
      }
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return IconButton(
      tooltip: syncing ? 'Checking for mail…' : 'Check for mail (F5)',
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      onPressed: () => ref.read(engineProvider).syncAll(),
      icon: RotationTransition(
        turns: _controller,
        child: Icon(
          Symbols.sync_rounded,
          color: syncing ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Inbox category chips (Gmail tabs) with an expressive selection morph.
class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs({required this.view});

  final MailView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const items = [
      (MailCategory.primary, 'Primary', Symbols.inbox_rounded),
      (MailCategory.promotions, 'Promotions', Symbols.sell_rounded),
      (MailCategory.social, 'Social', Symbols.group_rounded),
      (MailCategory.updates, 'Updates', Symbols.info_rounded),
      (MailCategory.forums, 'Forums', Symbols.forum_rounded),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final (category, label, icon) in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TabChip(
                label: label,
                icon: icon,
                selected: view.category == category,
                unreadFilter: RoleFilter(MailboxRole.inbox,
                    accountIds: view.accountId == null ? null : {view.accountId!}, category: category),
                onTap: () => ref.read(viewProvider.notifier).show(view.withCategory(category)),
              ),
            ),
          _TabChip(
            label: 'Everything',
            icon: Symbols.all_inbox_rounded,
            selected: view.category == null,
            onTap: () => ref.read(viewProvider.notifier).show(view.withCategory(null)),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends ConsumerWidget {
  const _TabChip({required this.label, required this.icon, required this.selected, required this.onTap, this.unreadFilter});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ThreadFilter? unreadFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = unreadFilter == null || selected ? 0 : (ref.watch(unreadCountProvider(unreadFilter!)).value ?? 0);
    return SpringBuilder(
      value: selected ? 1 : 0,
      spring: Spring.spatialFast,
      builder: (context, t, _) {
        final s = unit(t);
        return Material(
          color: Color.lerp(Colors.transparent, scheme.secondaryContainer, s),
          shape: RoundedRectangleBorder(
            borderRadius: Corners.all(10 + 10 * s),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 1 - s)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The icon grows in only on the selected chip, keeping the
                  // row compact enough to show every category.
                  ClipRect(
                    child: Align(
                      widthFactor: s,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(icon, size: 18, fill: 1, color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ),
                  Text(
                    label,
                    style: (selected ? theme.textTheme.labelLargeEmphasized : theme.textTheme.labelLarge)?.copyWith(
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: Corners.all(Corners.full)),
                      child: Text('$unread', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimary)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bulk actions for selected conversations.
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selection = ref.watch(selectionProvider);
    final list = ref.watch(visibleThreadsProvider).value ?? const <ThreadSummary>[];
    final selected = list.where((t) => selection.contains(t.key)).toList();
    final keys = selected.map(keyOf).toList();
    final anyUnread = selected.any((t) => t.isUnread);
    final view = ref.watch(viewProvider);
    final inTrash = view.kind == ViewKind.trash;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: scheme.primaryContainer,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IconTheme.merge(
            data: IconThemeData(color: scheme.onPrimaryContainer),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Clear selection (Esc)',
                  onPressed: () => ref.read(selectionProvider.notifier).clear(),
                  icon: const Icon(Symbols.close_rounded),
                ),
                Text('$count selected', style: theme.textTheme.titleSmallEmphasized.copyWith(color: scheme.onPrimaryContainer)),
                const Spacer(),
                IconButton(
                  tooltip: 'Select all',
                  onPressed: () => ref.read(selectionProvider.notifier).setAll(list.map((t) => t.key)),
                  icon: const Icon(Symbols.select_all_rounded),
                ),
                IconButton(
                  tooltip: inTrash ? 'Restore' : 'Archive',
                  onPressed: () => applyThreadAction(ref, inTrash ? MailAction.restore : MailAction.archive, keys),
                  icon: Icon(inTrash ? Symbols.restore_from_trash_rounded : Symbols.archive_rounded),
                ),
                IconButton(
                  tooltip: inTrash ? 'Delete forever' : 'Delete',
                  onPressed: () => applyThreadAction(ref, inTrash ? MailAction.deleteForever : MailAction.trash, keys),
                  icon: Icon(inTrash ? Symbols.delete_forever_rounded : Symbols.delete_rounded),
                ),
                IconButton(
                  tooltip: anyUnread ? 'Mark as read' : 'Mark as unread',
                  onPressed: () => applyThreadAction(ref, anyUnread ? MailAction.markRead : MailAction.markUnread, keys),
                  icon: Icon(anyUnread ? Symbols.drafts_rounded : Symbols.mark_email_unread_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The list grouped into date sections of connected rows.
class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.threads,
    required this.accounts,
    required this.controller,
    required this.unified,
    required this.grouped,
    this.footer,
  });

  final List<ThreadSummary> threads;
  final Map<String, Account> accounts;
  final ScrollController controller;
  final bool unified;
  final bool grouped;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final entries = <Object>[];
    if (grouped) {
      String? current;
      var groupStart = 0;
      for (var i = 0; i < threads.length; i++) {
        final label = dateGroup(threads[i].lastDate);
        if (label != current) {
          if (current != null) _closeGroup(entries, groupStart);
          entries.add(label);
          groupStart = entries.length;
          current = label;
        }
        entries.add(threads[i]);
      }
      _closeGroup(entries, groupStart);
    } else {
      entries.addAll(threads);
      _closeGroup(entries, 0);
    }

    final theme = Theme.of(context);
    return Scrollbar(
      controller: controller,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        itemCount: entries.length + (footer == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == entries.length) return footer!;
          final entry = entries[i];
          if (entry is String) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 ? 4 : 18, 16, 8),
              child: Text(entry, style: theme.textTheme.labelLargeEmphasized.copyWith(color: theme.colorScheme.primary)),
            );
          }
          final item = entry as _Positioned;
          return ThreadTile(
            key: ValueKey(item.thread.key),
            thread: item.thread,
            index: item.index,
            groupSize: item.size,
            account: accounts[item.thread.accountId],
            showAccountDot: unified,
          );
        },
      ),
    );
  }

  /// Replaces the raw threads after [start] with positioned entries.
  static void _closeGroup(List<Object> entries, int start) {
    final size = entries.length - start;
    for (var i = start; i < entries.length; i++) {
      entries[i] = _Positioned(entries[i] as ThreadSummary, i - start, size);
    }
  }
}

final class _Positioned {
  const _Positioned(this.thread, this.index, this.size);

  final ThreadSummary thread;
  final int index;
  final int size;
}
