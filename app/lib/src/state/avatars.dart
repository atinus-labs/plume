import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_core/plume_core.dart';

import '../services/avatar_service.dart';
import 'settings.dart';

/// Central singleton provider for the [AvatarService].
final avatarServiceProvider = Provider<AvatarService>((ref) => AvatarService());

/// Resolves a sender's avatar following the multi-layered fallback sequence.
final senderAvatarProvider = FutureProvider.family<ImageProvider?, String>((ref, email) {
  final cleanEmail = email.trim();
  if (cleanEmail.isEmpty) return Future.value(null);

  final settings = ref.watch(settingsProvider);
  if (!settings.showSenderAvatars) return Future.value(null);

  final service = ref.watch(avatarServiceProvider);
  final allowRemote = settings.remoteImages == RemoteImages.always ||
      settings.trustedImageSenders.contains(cleanEmail.toLowerCase());

  return service.resolveSenderAvatar(
    cleanEmail,
    allowRemote: allowRemote,
    fetchDomainFavicons: settings.fetchDomainFavicons,
    enableGravatar: settings.enableGravatar,
  );
});

/// Resolves an account's avatar following the fallback sequence:
/// 1. Custom / stored avatarUrl (provider OAuth or user picked).
/// 2. Gravatar on account email (if enabled in settings).
/// 3. Fallback to null (renders M3 Expressive MorphAvatar monogram).
final accountAvatarProvider = FutureProvider.family<ImageProvider?, Account>((ref, account) {
  final service = ref.watch(avatarServiceProvider);
  final settings = ref.watch(settingsProvider);

  return service.resolveAccountAvatar(
    account,
    enableGravatar: settings.enableGravatar,
  );
});
