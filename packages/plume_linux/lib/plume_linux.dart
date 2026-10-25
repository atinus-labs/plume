/// Linux desktop integration over D-Bus: notifications, tray, portals,
/// autostart, default applications and session monitors.
///
/// Every component degrades gracefully: when its service is missing it
/// reports itself unavailable instead of throwing.
library;

export 'src/autostart.dart'
    show
        Autostart,
        AutostartException,
        isDesktopEntryEnabled,
        quoteExecArgument;
export 'src/desktop_environment.dart';
export 'src/mime_apps.dart';
export 'src/notifications/desktop_notifications.dart';
export 'src/notifications/markup.dart';
export 'src/notifications/notification_request.dart' hide NotifyArguments;
export 'src/portal/portal_appearance.dart';
export 'src/system/connectivity_monitor.dart';
export 'src/system/sleep_monitor.dart';
export 'src/tray/status_notifier_tray.dart';
export 'src/tray/tray_menu.dart' show TrayMenuItem;
export 'src/tray/tray_pixmap.dart';
