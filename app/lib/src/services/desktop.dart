import 'dart:async';
import 'dart:ui';

/// Events coming from the desktop shell (tray, notifications, launcher).
sealed class DesktopEvent {
  const DesktopEvent();
}

/// Bring the window up (tray click, launcher, second instance).
final class ShowWindowEvent extends DesktopEvent {
  const ShowWindowEvent({this.activationToken, this.toggle = false});

  final String? activationToken;

  /// Tray left-click toggles visibility instead of always showing.
  final bool toggle;
}

/// Open a conversation (notification click).
final class OpenThreadEvent extends DesktopEvent {
  const OpenThreadEvent(this.accountId, this.threadId, {this.activationToken});

  final String accountId;
  final String threadId;
  final String? activationToken;
}

/// An action button on a new-mail notification.
final class NotificationActionEvent extends DesktopEvent {
  const NotificationActionEvent(this.action, this.accountId, this.messageIds, this.threadIds);

  /// `archive` or `read`.
  final String action;
  final String accountId;
  final List<String> messageIds;
  final List<String> threadIds;
}

final class ComposeEvent extends DesktopEvent {
  const ComposeEvent({this.activationToken});

  final String? activationToken;
}

final class SyncNowEvent extends DesktopEvent {
  const SyncNowEvent();
}

final class QuitEvent extends DesktopEvent {
  const QuitEvent();
}

/// The system woke up or the network came back.
final class WakeEvent extends DesktopEvent {
  const WakeEvent();
}

/// The user tried to close the window.
final class CloseRequestedEvent extends DesktopEvent {
  const CloseRequestedEvent();
}

/// Window visibility/focus changed.
final class WindowStateEvent extends DesktopEvent {
  const WindowStateEvent({required this.visible, required this.focused, required this.maximized});

  final bool visible;
  final bool focused;
  final bool maximized;
}

/// A new-mail notification to post.
final class MailNotification {
  const MailNotification({
    required this.accountId,
    required this.title,
    required this.body,
    this.threadId,
    this.messageIds = const [],
    this.threadIds = const [],
    this.avatarRgba,
    this.avatarSize = 0,
    this.sound = true,
  });

  final String accountId;
  final String title;
  final String body;

  /// The thread to open on click; null for summary notifications.
  final String? threadId;
  final List<String> messageIds;
  final List<String> threadIds;
  final List<int>? avatarRgba;
  final int avatarSize;
  final bool sound;
}

/// Appearance preferences published by the desktop.
final class SystemAppearance {
  const SystemAppearance({this.brightness, this.accent, this.highContrast = false});

  /// Null when the desktop has no preference.
  final Brightness? brightness;
  final Color? accent;
  final bool highContrast;
}

/// Everything the app needs from the host desktop. Linux implements it over
/// D-Bus; other platforms (and tests) use [HeadlessDesktop].
abstract interface class DesktopIntegration {
  Future<void> start();

  Stream<DesktopEvent> get events;

  /// Whether the app should draw its own minimise/maximise/close buttons.
  bool get drawsWindowControls;

  /// Whether a tray icon is shown (so closing can safely hide the window).
  bool get hasTray;

  /// Whether the session runs XDG autostart entries.
  bool get autostartSupported;

  SystemAppearance get appearance;
  Stream<SystemAppearance> get appearanceChanges;

  Future<void> showWindow({String? activationToken});
  Future<void> hideWindow();
  Future<bool> isWindowVisible();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> startWindowMove();
  Future<void> setPreventClose(bool prevent);
  Future<void> quit();

  /// Updates the tray badge.
  Future<void> setUnreadCount(int count);

  Future<void> notify(MailNotification notification);

  Future<bool> isAutostartEnabled();
  Future<void> setAutostart(bool enabled);

  Future<void> dispose();
}

/// No desktop shell: used on platforms without tray/notification support
/// and in tests.
final class HeadlessDesktop implements DesktopIntegration {
  final _events = StreamController<DesktopEvent>.broadcast();

  @override
  Future<void> start() async {}
  @override
  Stream<DesktopEvent> get events => _events.stream;
  @override
  bool get drawsWindowControls => false;
  @override
  bool get hasTray => false;
  @override
  bool get autostartSupported => false;
  @override
  SystemAppearance get appearance => const SystemAppearance();
  @override
  Stream<SystemAppearance> get appearanceChanges => const Stream.empty();
  @override
  Future<void> showWindow({String? activationToken}) async {}
  @override
  Future<void> hideWindow() async {}
  @override
  Future<bool> isWindowVisible() async => true;
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> startWindowMove() async {}
  @override
  Future<void> setPreventClose(bool prevent) async {}
  @override
  Future<void> quit() async {}
  @override
  Future<void> setUnreadCount(int count) async {}
  @override
  Future<void> notify(MailNotification notification) async {}
  @override
  Future<bool> isAutostartEnabled() async => false;
  @override
  Future<void> setAutostart(bool enabled) async {}
  @override
  Future<void> dispose() => _events.close();
}
