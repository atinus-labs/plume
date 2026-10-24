import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services.dart';

/// Where the theme colour comes from.
enum ColorSource {
  /// The desktop accent colour (portal), falling back to the brand colour.
  system,
  custom,
}

/// What to show after archiving or deleting the open conversation.
enum AfterAction { nextOlder, nextNewer, list }

/// Whether to load images from the internet in messages, which can reveal
/// to senders that and when a message was read.
enum RemoteImages { ask, always }

@immutable
final class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.colorSource = ColorSource.system,
    this.customSeed = 0xFF4C5BD4,
    this.notifications = true,
    this.notifyPrimaryOnly = true,
    this.notificationSound = true,
    this.runInBackground = true,
    this.undoSendSeconds = 5,
    this.remoteImages = RemoteImages.ask,
    this.trustedImageSenders = const {},
    this.categoryTabs = true,
    this.afterAction = AfterAction.nextOlder,
    this.railExpanded = true,
    this.listWidth = 420,
  });

  final ThemeMode themeMode;
  final ColorSource colorSource;
  final int customSeed;
  final bool notifications;

  /// Only notify for mail in the Primary category (Gmail).
  final bool notifyPrimaryOnly;
  final bool notificationSound;

  /// Keep running in the tray when the window is closed.
  final bool runInBackground;
  final int undoSendSeconds;
  final RemoteImages remoteImages;

  /// Lower-cased sender addresses whose images always load.
  final Set<String> trustedImageSenders;

  /// Split the inbox into Primary/Promotions/Social/Updates.
  final bool categoryTabs;
  final AfterAction afterAction;
  final bool railExpanded;
  final double listWidth;

  AppSettings copyWith({
    ThemeMode? themeMode,
    ColorSource? colorSource,
    int? customSeed,
    bool? notifications,
    bool? notifyPrimaryOnly,
    bool? notificationSound,
    bool? runInBackground,
    int? undoSendSeconds,
    RemoteImages? remoteImages,
    Set<String>? trustedImageSenders,
    bool? categoryTabs,
    AfterAction? afterAction,
    bool? railExpanded,
    double? listWidth,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        colorSource: colorSource ?? this.colorSource,
        customSeed: customSeed ?? this.customSeed,
        notifications: notifications ?? this.notifications,
        notifyPrimaryOnly: notifyPrimaryOnly ?? this.notifyPrimaryOnly,
        notificationSound: notificationSound ?? this.notificationSound,
        runInBackground: runInBackground ?? this.runInBackground,
        undoSendSeconds: undoSendSeconds ?? this.undoSendSeconds,
        remoteImages: remoteImages ?? this.remoteImages,
        trustedImageSenders: trustedImageSenders ?? this.trustedImageSenders,
        categoryTabs: categoryTabs ?? this.categoryTabs,
        afterAction: afterAction ?? this.afterAction,
        railExpanded: railExpanded ?? this.railExpanded,
        listWidth: listWidth ?? this.listWidth,
      );

  Map<String, Object?> toJson() => {
        'themeMode': themeMode.name,
        'colorSource': colorSource.name,
        'customSeed': customSeed,
        'notifications': notifications,
        'notifyPrimaryOnly': notifyPrimaryOnly,
        'notificationSound': notificationSound,
        'runInBackground': runInBackground,
        'undoSendSeconds': undoSendSeconds,
        'remoteImages': remoteImages.name,
        'trustedImageSenders': trustedImageSenders.toList(),
        'categoryTabs': categoryTabs,
        'afterAction': afterAction.name,
        'railExpanded': railExpanded,
        'listWidth': listWidth,
      };

  static AppSettings fromJson(Map<String, Object?> j) {
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return AppSettings(
      themeMode: pick(ThemeMode.values, j['themeMode'], d.themeMode),
      colorSource: pick(ColorSource.values, j['colorSource'], d.colorSource),
      customSeed: (j['customSeed'] as num?)?.toInt() ?? d.customSeed,
      notifications: j['notifications'] as bool? ?? d.notifications,
      notifyPrimaryOnly: j['notifyPrimaryOnly'] as bool? ?? d.notifyPrimaryOnly,
      notificationSound: j['notificationSound'] as bool? ?? d.notificationSound,
      runInBackground: j['runInBackground'] as bool? ?? d.runInBackground,
      undoSendSeconds: (j['undoSendSeconds'] as num?)?.toInt() ?? d.undoSendSeconds,
      remoteImages: pick(RemoteImages.values, j['remoteImages'], d.remoteImages),
      trustedImageSenders: ((j['trustedImageSenders'] as List?) ?? const []).cast<String>().toSet(),
      categoryTabs: j['categoryTabs'] as bool? ?? d.categoryTabs,
      afterAction: pick(AfterAction.values, j['afterAction'], d.afterAction),
      railExpanded: j['railExpanded'] as bool? ?? d.railExpanded,
      listWidth: (j['listWidth'] as num?)?.toDouble() ?? d.listWidth,
    );
  }
}

/// App settings, persisted in the store's settings table.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app.settings';
  Timer? _saveTimer;

  @override
  AppSettings build() {
    ref.onDispose(() => _saveTimer?.cancel());
    return ref.read(servicesProvider).initialSettings;
  }

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    // Debounced so that dragging the pane divider does not hammer the DB.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(ref.read(servicesProvider).store.writeSetting(_key, jsonEncode(state.toJson())));
    });
  }

  static Future<AppSettings> load(Future<String?> raw) async {
    final value = await raw;
    if (value == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(value) as Map<String, Object?>);
    } catch (_) {
      return const AppSettings();
    }
  }

  static const storageKey = _key;
}
