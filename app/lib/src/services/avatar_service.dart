import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:plume_core/plume_core.dart';

import '../config.dart';

final _log = Logger('plume.avatars');

/// Common public webmail domains where domain favicons should not be used as
/// a personal sender's profile picture.
const Set<String> genericEmailDomains = {
  'gmail.com', 'googlemail.com', 'yahoo.com', 'ymail.com', 'rocketmail.com',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com',
  'icloud.com', 'me.com', 'mac.com',
  'proton.me', 'protonmail.com', 'pm.me',
  'aol.com', 'aim.com', 'zoho.com', 'mail.com', 'email.com',
  'gmx.com', 'gmx.net', 'gmx.de', 'web.de', 't-online.de',
  'fastmail.com', 'fastmail.fm', 'hey.com', 'tutanota.com', 'tuta.com',
  'yandex.com', 'yandex.ru', 'mail.ru', 'inbox.ru', 'list.ru', 'bk.ru',
  'naver.com', 'daum.net', 'hanmail.net', 'qq.com', '163.com', '126.com', 'sina.com',
};

/// Resolves, caches, and falls back profile pictures for senders and accounts.
final class AvatarService {
  AvatarService({
    String? cacheDirectory,
    HttpClient? httpClient,
  })  : _cacheDir = cacheDirectory ?? AppConfig.avatarCacheDir,
        _client = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  final String _cacheDir;
  final HttpClient _client;

  final Map<String, ImageProvider?> _memoryCache = {};
  final Map<String, Uint8List?> _rawBytesCache = {};
  final Map<String, DateTime> _negativeCache = {};
  final Map<String, Future<ImageProvider?>> _inFlight = {};

  static const _negativeTtl = Duration(days: 7);

  /// Synchronously returns a previously resolved image provider from memory.
  ImageProvider? getCached(String key) => _memoryCache[key.toLowerCase().trim()];

  /// Synchronously returns raw image bytes if cached in memory.
  Uint8List? getCachedBytes(String key) => _rawBytesCache[key.toLowerCase().trim()];

  /// Hashes a string using SHA-256 for privacy-preserving file names and queries.
  static String hashKey(String input) => sha256.convert(utf8.encode(input.toLowerCase().trim())).toString();

  /// Resolves an avatar for an incoming sender email address following the
  /// multi-layered fallback strategy:
  /// 1. Local disk/file cache.
  /// 2. Domain Favicon (for non-generic domains, via DuckDuckGo privacy icon proxy).
  /// 3. Gravatar (SHA-256, if enabled in settings and remote images allowed).
  /// 4. Negative caching + fallback to null (renders MorphAvatar monogram).
  Future<ImageProvider?> resolveSenderAvatar(
    String email, {
    bool allowRemote = true,
    bool fetchDomainFavicons = true,
    bool enableGravatar = false,
  }) async {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) return null;

    if (_memoryCache.containsKey(cleanEmail)) {
      return _memoryCache[cleanEmail];
    }

    final existingFuture = _inFlight[cleanEmail];
    if (existingFuture != null) return existingFuture;

    final future = _resolveSenderAvatarInternal(
      cleanEmail,
      allowRemote: allowRemote,
      fetchDomainFavicons: fetchDomainFavicons,
      enableGravatar: enableGravatar,
    );
    _inFlight[cleanEmail] = future;

    try {
      final result = await future;
      _memoryCache[cleanEmail] = result;
      return result;
    } finally {
      _inFlight.remove(cleanEmail);
    }
  }

  Future<ImageProvider?> _resolveSenderAvatarInternal(
    String email, {
    required bool allowRemote,
    required bool fetchDomainFavicons,
    required bool enableGravatar,
  }) async {
    final emailHash = hashKey(email);
    final domain = email.split('@').last.toLowerCase().trim();
    final isGeneric = genericEmailDomains.contains(domain);

    // 1. Check local disk cache for Gravatar or Domain icon
    final gravatarFile = File(p.join(_cacheDir, 'gravatar_$emailHash.png'));
    if (gravatarFile.existsSync()) {
      try {
        final bytes = await gravatarFile.readAsBytes();
        _rawBytesCache[email] = bytes;
        return FileImage(gravatarFile);
      } catch (_) {}
    }

    if (!isGeneric) {
      final domainHash = hashKey(domain);
      final domainFile = File(p.join(_cacheDir, 'domain_$domainHash.ico'));
      if (domainFile.existsSync()) {
        try {
          final bytes = await domainFile.readAsBytes();
          _rawBytesCache[email] = bytes;
          return FileImage(domainFile);
        } catch (_) {}
      }
    }

    if (!allowRemote) return null;

    // Check negative cache expiry
    final negativeUntil = _negativeCache[email];
    if (negativeUntil != null && DateTime.now().isBefore(negativeUntil)) {
      return null;
    }

    // 2. Fetch Domain Favicon if not a generic webmail provider
    if (fetchDomainFavicons && !isGeneric && domain.isNotEmpty) {
      final faviconImage = await _fetchDomainFavicon(domain, email);
      if (faviconImage != null) return faviconImage;
    }

    // 3. Fetch Gravatar (SHA-256) if enabled
    if (enableGravatar) {
      final gravatarImage = await _fetchGravatar(email, emailHash);
      if (gravatarImage != null) return gravatarImage;
    }

    // Cache miss for negative TTL
    _negativeCache[email] = DateTime.now().add(_negativeTtl);
    return null;
  }

  Future<ImageProvider?> _fetchDomainFavicon(String domain, String email) async {
    final domainHash = hashKey(domain);
    final domainFile = File(p.join(_cacheDir, 'domain_$domainHash.ico'));

    try {
      final url = Uri.parse('https://icons.duckduckgo.com/ip3/$domain.ico');
      final request = await _client.getUrl(url).timeout(const Duration(seconds: 3));
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == HttpStatus.ok) {
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final bytes = bytesBuilder.takeBytes();
        if (bytes.length > 80) {
          await domainFile.parent.create(recursive: true);
          await domainFile.writeAsBytes(bytes, flush: true);
          _rawBytesCache[email] = bytes;
          return FileImage(domainFile);
        }
      }
    } catch (e) {
      _log.fine('Favicon lookup failed for $domain: $e');
    }
    return null;
  }

  Future<ImageProvider?> _fetchGravatar(String email, String emailHash) async {
    final gravatarFile = File(p.join(_cacheDir, 'gravatar_$emailHash.png'));

    try {
      final url = Uri.parse('https://www.gravatar.com/avatar/$emailHash?s=128&d=404');
      final request = await _client.getUrl(url).timeout(const Duration(seconds: 3));
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == HttpStatus.ok) {
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final bytes = bytesBuilder.takeBytes();
        if (bytes.isNotEmpty) {
          await gravatarFile.parent.create(recursive: true);
          await gravatarFile.writeAsBytes(bytes, flush: true);
          _rawBytesCache[email] = bytes;
          return FileImage(gravatarFile);
        }
      }
    } catch (e) {
      _log.fine('Gravatar lookup failed for $email: $e');
    }
    return null;
  }

  /// Resolves an avatar for an added account following the fallback strategy:
  /// 1. Custom or stored avatar URL (network or file).
  /// 2. Gravatar (if enabled).
  /// 3. Fallback to null (renders M3 Expressive MorphAvatar monogram).
  Future<ImageProvider?> resolveAccountAvatar(
    Account account, {
    bool enableGravatar = false,
  }) async {
    final cacheKey = 'account:${account.id}';
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    final future = _resolveAccountAvatarInternal(
      account,
      enableGravatar: enableGravatar,
    );

    final result = await future;
    _memoryCache[cacheKey] = result;
    return result;
  }

  Future<ImageProvider?> _resolveAccountAvatarInternal(
    Account account, {
    required bool enableGravatar,
  }) async {
    // Tier 1: Custom or stored avatar URL (from provider OAuth or user selection)
    final url = account.avatarUrl?.trim();
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return NetworkImage(url);
      }
      final filePath = url.startsWith('file://') ? url.substring(7) : url;
      final file = File(filePath);
      if (file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          _rawBytesCache['account:${account.id}'] = bytes;
          return FileImage(file);
        } catch (_) {}
      }
    }

    // Tier 2: Gravatar on account email (if enabled)
    if (enableGravatar && account.email.isNotEmpty) {
      final emailHash = hashKey(account.email);
      final gravatar = await _fetchGravatar(account.email, emailHash);
      if (gravatar != null) return gravatar;
    }

    // Tier 3: Fallback to null (renders M3 Expressive MorphAvatar monogram)
    return null;
  }

  /// Clears the in-memory cache and in-flight requests.
  void clearMemoryCache() {
    _memoryCache.clear();
    _rawBytesCache.clear();
    _negativeCache.clear();
  }
}
