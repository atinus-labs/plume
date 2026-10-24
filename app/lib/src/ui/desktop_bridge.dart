import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../services/avatar_renderer.dart';
import '../services/desktop.dart';
import '../state/mail.dart';
import '../state/navigation.dart';
import '../state/services.dart';
import '../state/settings.dart';
import 'actions.dart';
import 'compose/compose_host.dart';

final _log = Logger('plume.bridge');

/// Connects the desktop shell (tray, notifications, window) with the mail
/// engine and the UI state. Lives at the root of the widget tree.
class DesktopBridge extends ConsumerStatefulWidget {
  const DesktopBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopBridge> createState() => _DesktopBridgeState();
}

class _DesktopBridgeState extends ConsumerState<DesktopBridge> {
  final _subs = <StreamSubscription<Object?>>[];
  bool _visible = true;
  bool _focused = true;

  DesktopIntegration get _desktop => ref.read(desktopProvider);
  MailEngine get _engine => ref.read(engineProvider);

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_desktop.events.listen(_onDesktopEvent))
      ..add(_engine.newMail.listen((e) => unawaited(_onNewMail(e))))
      ..add(_engine.outboxEvents.listen(_onOutbox));
    // Window events from before this widget existed (e.g. starting hidden
    // with --background) were not observed; ask for the current state.
    unawaited(_desktop.isWindowVisible().then((visible) {
      _visible = visible;
      _focused = visible;
      _engine.foreground = visible;
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  Future<void> _onDesktopEvent(DesktopEvent event) async {
    switch (event) {
      case ShowWindowEvent(:final activationToken, :final toggle):
        if (toggle && _visible && await _desktop.isWindowVisible()) {
          await _desktop.hideWindow();
        } else {
          await _desktop.showWindow(activationToken: activationToken);
        }
      case OpenThreadEvent(:final accountId, :final threadId, :final activationToken):
        await _desktop.showWindow(activationToken: activationToken);
        ref.read(openThreadProvider.notifier).open((accountId: accountId, threadId: threadId));
        unawaited(applyThreadAction(ref, MailAction.markRead, [(accountId: accountId, threadId: threadId)], announce: false));
      case NotificationActionEvent(:final action, :final accountId, :final threadIds):
        final keys = [for (final t in threadIds) (accountId: accountId, threadId: t)];
        await applyThreadAction(ref, action == 'archive' ? MailAction.archive : MailAction.markRead, keys, announce: false);
      case ComposeEvent(:final activationToken):
        await _desktop.showWindow(activationToken: activationToken);
        ref.read(composeProvider.notifier).newMessage();
      case SyncNowEvent():
        _engine.syncAll();
      case QuitEvent():
        await _quit();
      case WakeEvent():
        _engine.wake();
      case CloseRequestedEvent():
        final background = ref.read(settingsProvider).runInBackground && _desktop.hasTray;
        if (background) {
          await _desktop.hideWindow();
        } else {
          await _quit();
        }
      case WindowStateEvent(:final visible, :final focused):
        _visible = visible;
        _focused = focused;
        _engine.foreground = visible;
    }
  }

  Future<void> _quit() async {
    try {
      await _engine.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _desktop.quit();
  }

  Future<void> _onNewMail(NewMailEvent event) async {
    final settings = ref.read(settingsProvider);
    if (!settings.notifications) return;
    // The user is looking at the app; a banner would only interrupt.
    if (_visible && _focused) return;
    final store = ref.read(storeProvider);
    final mailboxes = await store.mailboxes(event.accountId);
    final otherCategories = {
      for (final m in mailboxes)
        if (m.role == MailboxRole.category && m.category != MailCategory.primary) m.id,
    };
    var messages = event.messages.where((m) => !m.isRead && !m.isDraft).toList();
    if (settings.notifyPrimaryOnly) {
      messages = messages.where((m) => !m.mailboxIds.any(otherCategories.contains)).toList();
    }
    if (messages.isEmpty) return;
    final accounts = ref.read(accountMapProvider);
    final account = accounts[event.accountId];
    final multi = accounts.length > 1;
    final scheme = PlumeTheme.build(brightness: Brightness.light).colorScheme;

    try {
      if (messages.length <= 3) {
        for (final m in messages) {
          final sender = m.from?.displayName ?? 'Unknown sender';
          final avatar = await renderAvatarRgba(name: sender, key: m.from?.email ?? m.id, scheme: scheme, size: 96);
          await _desktop.notify(MailNotification(
            accountId: event.accountId,
            title: sender,
            body: [
              if (m.subject.isNotEmpty) m.subject,
              if (m.snippet.isNotEmpty) m.snippet,
              if (multi && account != null) account.email,
            ].join('\n'),
            threadId: m.threadId,
            messageIds: [m.id],
            threadIds: [m.threadId],
            avatarRgba: avatar,
            avatarSize: 96,
            sound: settings.notificationSound,
          ));
        }
      } else {
        final senders = <String>[];
        for (final m in messages) {
          final name = m.from?.displayName;
          if (name != null && !senders.contains(name)) senders.add(name);
        }
        await _desktop.notify(MailNotification(
          accountId: event.accountId,
          title: '${messages.length} new messages',
          body: [senders.take(4).join(', '), if (multi && account != null) account.email].join('\n'),
          messageIds: [for (final m in messages) m.id],
          threadIds: {for (final m in messages) m.threadId}.toList(),
          sound: settings.notificationSound,
        ));
      }
    } catch (e, st) {
      _log.warning('Posting a notification failed', e, st);
    }
  }

  void _onOutbox(OutboxEvent event) {
    switch (event) {
      case OutboxSent():
        showSnack('Message sent', duration: const Duration(seconds: 3));
      case OutboxFailed(:final error, :final willRetry):
        if (willRetry) {
          showSnack('Couldn’t send yet. Plume will keep trying.');
        } else {
          showSnack(
            'Message not sent: $error',
            actionLabel: 'Edit',
            duration: const Duration(seconds: 10),
            onAction: () async {
              final taken = await ref.read(storeProvider).takeOutgoing(event.outboxId);
              if (taken != null) ref.read(composeProvider.notifier).reopen(taken.message);
            },
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tray badge: unread conversations in the (primary) unified inbox.
    final categories = ref.watch(hasCategoriesProvider) && ref.watch(settingsProvider).categoryTabs;
    ref.listen(
      unreadCountProvider(RoleFilter(MailboxRole.inbox, category: categories ? MailCategory.primary : null)),
      (_, next) {
        final count = next.value;
        if (count != null) unawaited(_desktop.setUnreadCount(count));
      },
    );
    ref.listen(settingsProvider.select((s) => s.runInBackground), (_, next) {
      unawaited(_desktop.setPreventClose(next && _desktop.hasTray));
    });
    return widget.child;
  }
}
