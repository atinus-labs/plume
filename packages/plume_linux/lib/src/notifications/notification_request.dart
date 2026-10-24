import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../pixels.dart';
import 'markup.dart';

/// Well-known capability strings from the Desktop Notifications spec, plus
/// KDE's inline reply.
abstract final class NotificationCapabilities {
  static const actions = 'actions';
  static const actionIcons = 'action-icons';
  static const body = 'body';
  static const bodyHyperlinks = 'body-hyperlinks';
  static const bodyImages = 'body-images';
  static const bodyMarkup = 'body-markup';
  static const iconMulti = 'icon-multi';
  static const iconStatic = 'icon-static';
  static const persistence = 'persistence';
  static const sound = 'sound';
  static const inlineReply = 'inline-reply';
}

/// Standard notification categories relevant to a mail client.
abstract final class NotificationCategories {
  static const email = 'email';
  static const emailArrived = 'email.arrived';
  static const emailBounced = 'email.bounced';
  static const network = 'network';
  static const networkError = 'network.error';
}

/// Notification urgency (the `urgency` hint).
enum NotificationUrgency {
  low(0),
  normal(1),
  critical(2);

  const NotificationUrgency(this.value);
  final int value;
}

/// One action button. Use [NotificationAction.defaultKey] for the action
/// invoked when the notification body itself is clicked.
class NotificationAction {
  const NotificationAction(this.key, this.label);

  /// The action invoked by clicking the notification (label usually hidden).
  const NotificationAction.byDefault([this.label = 'Open']) : key = defaultKey;

  static const defaultKey = 'default';

  final String key;
  final String label;

  @override
  String toString() => 'NotificationAction($key, $label)';
}

/// KDE-style inline reply (only sent when the server has `inline-reply`).
class NotificationInlineReply {
  const NotificationInlineReply({
    this.label = 'Reply',
    this.placeholder,
    this.submitButtonText,
    this.submitButtonIconName,
  });

  final String label;
  final String? placeholder;
  final String? submitButtonText;
  final String? submitButtonIconName;

  /// The action key KDE uses for the reply field.
  static const actionKey = 'inline-reply';
}

/// The notification image: raw pixels or a file / themed icon.
sealed class NotificationImage {
  const NotificationImage();

  /// Raw RGBA pixels, e.g. from Flutter's `ImageByteFormat.rawRgba` (which is
  /// premultiplied; set [premultiplied] to false for straight alpha).
  factory NotificationImage.rgba(
    Uint8List bytes, {
    required int width,
    required int height,
    bool premultiplied,
  }) = NotificationImageData;

  /// An image file (absolute path) or a themed icon name.
  const factory NotificationImage.path(String pathOrIconName) =
      NotificationImagePath;
}

final class NotificationImageData extends NotificationImage {
  NotificationImageData(
    this.bytes, {
    required this.width,
    required this.height,
    this.premultiplied = true,
  }) {
    if (width <= 0 || height <= 0 || bytes.length != width * height * 4) {
      throw ArgumentError(
        'Expected ${width}x$height RGBA (${width * height * 4} bytes), '
        'got ${bytes.length} bytes',
      );
    }
  }

  final Uint8List bytes;
  final int width;
  final int height;
  final bool premultiplied;

  /// The `(iiibiiay)` value: width, height, rowstride, has_alpha,
  /// bits_per_sample, channels, data.
  DBusStruct toDBus() {
    final straight = premultiplied ? unpremultiplyRgba(bytes) : bytes;
    return DBusStruct([
      DBusInt32(width),
      DBusInt32(height),
      DBusInt32(width * 4),
      const DBusBoolean(true),
      DBusInt32(8),
      DBusInt32(4),
      DBusArray.byte(straight),
    ]);
  }
}

final class NotificationImagePath extends NotificationImage {
  const NotificationImagePath(this.path);
  final String path;
}

/// Everything needed for one `Notify` call.
class NotificationRequest {
  const NotificationRequest({
    required this.summary,
    this.body = '',
    this.bodyIsMarkup = false,
    this.appIcon,
    this.image,
    this.actions = const [],
    this.category,
    this.urgency,
    this.timeout,
    this.replacesId = 0,
    this.desktopEntry,
    this.soundName,
    this.suppressSound = false,
    this.resident = false,
    this.transient = false,
    this.inlineReply,
    this.extraHints = const {},
  });

  /// Single-line title (sender or subject). Never markup.
  final String summary;

  /// Body text. Plain text unless [bodyIsMarkup]; plain text is escaped when
  /// the server supports markup.
  final String body;

  /// Set when [body] already contains spec markup (`<b>`, `<i>`, `<a>` ...).
  /// It is passed through as-is on markup servers and stripped to plain
  /// text on others.
  final bool bodyIsMarkup;

  /// Icon name from the theme, or an absolute file path.
  final String? appIcon;

  /// Large image (e.g. sender avatar).
  final NotificationImage? image;

  /// Action buttons; dropped when the server lacks the `actions` capability.
  final List<NotificationAction> actions;

  /// e.g. [NotificationCategories.emailArrived].
  final String? category;

  final NotificationUrgency? urgency;

  /// `null` uses the server default; [Duration.zero] never expires.
  final Duration? timeout;

  /// Id of a notification to replace (0 for a new one).
  final int replacesId;

  /// Overrides the default `desktop-entry` hint.
  final String? desktopEntry;

  /// Themed sound, e.g. `message-new-email`.
  final String? soundName;

  final bool suppressSound;

  /// Keep the notification after an action is invoked.
  final bool resident;

  /// Bypass the server's persistence (do not keep in history).
  final bool transient;

  /// Inline reply field (KDE `inline-reply` capability).
  final NotificationInlineReply? inlineReply;

  /// Additional hints, sent verbatim (they win over generated hints).
  final Map<String, DBusValue> extraHints;

  static const soundNewEmail = 'message-new-email';
}

/// The fully resolved arguments of an `org.freedesktop.Notifications.Notify`
/// call. Pure data so it can be unit-tested without a bus.
class NotifyArguments {
  NotifyArguments({
    required this.appName,
    required this.replacesId,
    required this.appIcon,
    required this.summary,
    required this.body,
    required this.actions,
    required this.hints,
    required this.expireTimeout,
  });

  /// Builds the call for [request] against a server with [capabilities] and
  /// spec version [specVersion] (affects the image hint name).
  factory NotifyArguments.build(
    NotificationRequest request, {
    required Set<String> capabilities,
    required String appName,
    required String defaultDesktopEntry,
    String specVersion = '1.2',
  }) {
    final markup = capabilities.contains(NotificationCapabilities.bodyMarkup);
    final String body;
    if (request.bodyIsMarkup) {
      body = markup ? request.body : stripNotificationMarkup(request.body);
    } else {
      body = markup ? escapeNotificationMarkup(request.body) : request.body;
    }

    final actions = <String>[];
    if (capabilities.contains(NotificationCapabilities.actions)) {
      for (final a in request.actions) {
        actions
          ..add(a.key)
          ..add(a.label);
      }
    }

    final hints = <String, DBusValue>{};
    final desktopEntry = request.desktopEntry ?? defaultDesktopEntry;
    if (desktopEntry.isNotEmpty) {
      hints['desktop-entry'] = DBusString(desktopEntry);
    }
    if (request.category != null) {
      hints['category'] = DBusString(request.category!);
    }
    if (request.urgency != null) {
      hints['urgency'] = DBusByte(request.urgency!.value);
    }
    if (request.soundName != null) {
      hints['sound-name'] = DBusString(request.soundName!);
    }
    if (request.suppressSound) {
      hints['suppress-sound'] = const DBusBoolean(true);
    }
    if (request.resident) hints['resident'] = const DBusBoolean(true);
    if (request.transient) hints['transient'] = const DBusBoolean(true);

    final version = _SpecVersion.parse(specVersion);
    switch (request.image) {
      case final NotificationImageData data:
        final name = version.atLeast(1, 2)
            ? 'image-data'
            : version.atLeast(1, 1)
            ? 'image_data'
            : 'icon_data';
        hints[name] = data.toDBus();
      case NotificationImagePath(:final path):
        final name = version.atLeast(1, 2) ? 'image-path' : 'image_path';
        hints[name] = DBusString(_iconReference(path));
      case null:
        break;
    }

    final reply = request.inlineReply;
    if (reply != null &&
        capabilities.contains(NotificationCapabilities.inlineReply)) {
      actions
        ..add(NotificationInlineReply.actionKey)
        ..add(reply.label);
      if (reply.placeholder != null) {
        hints['x-kde-reply-placeholder-text'] = DBusString(reply.placeholder!);
      }
      if (reply.submitButtonText != null) {
        hints['x-kde-reply-submit-button-text'] = DBusString(
          reply.submitButtonText!,
        );
      }
      if (reply.submitButtonIconName != null) {
        hints['x-kde-reply-submit-button-icon-name'] = DBusString(
          reply.submitButtonIconName!,
        );
      }
    }

    hints.addAll(request.extraHints);

    final timeout = request.timeout;
    return NotifyArguments(
      appName: appName,
      replacesId: request.replacesId,
      appIcon: request.appIcon == null ? '' : _iconReference(request.appIcon!),
      summary: request.summary,
      body: body,
      actions: actions,
      hints: hints,
      expireTimeout: timeout == null
          ? -1
          : timeout.inMilliseconds.clamp(0, 0x7fffffff),
    );
  }

  final String appName;
  final int replacesId;
  final String appIcon;
  final String summary;
  final String body;
  final List<String> actions;
  final Map<String, DBusValue> hints;
  final int expireTimeout;

  /// The `susssasa{sv}i` argument list.
  List<DBusValue> toDBus() => [
    DBusString(appName),
    DBusUint32(replacesId),
    DBusString(appIcon),
    DBusString(summary),
    DBusString(body),
    DBusArray.string(actions),
    DBusDict.stringVariant(hints),
    DBusInt32(expireTimeout),
  ];
}

/// Absolute paths become `file://` URIs; icon names and URIs pass through.
String _iconReference(String value) =>
    value.startsWith('/') ? Uri.file(value).toString() : value;

class _SpecVersion {
  const _SpecVersion(this.major, this.minor);

  factory _SpecVersion.parse(String s) {
    final parts = s.split('.');
    return _SpecVersion(
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 2,
    );
  }

  final int major;
  final int minor;

  bool atLeast(int maj, int min) =>
      major > maj || (major == maj && minor >= min);
}
