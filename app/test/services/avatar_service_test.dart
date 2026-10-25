import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plume/src/services/avatar_service.dart';
import 'package:plume_core/plume_core.dart';

void main() {
  late Directory tempDir;
  late AvatarService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plume_avatar_test_');
    service = AvatarService(cacheDirectory: tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AvatarService hashing and domain classification', () {
    test('hashKey produces deterministic SHA-256 hex string', () {
      final hash1 = AvatarService.hashKey('test@example.com');
      final hash2 = AvatarService.hashKey('  TEST@Example.com ');
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64));
    });

    test('genericEmailDomains contains major webmail providers', () {
      expect(genericEmailDomains.contains('gmail.com'), isTrue);
      expect(genericEmailDomains.contains('yahoo.com'), isTrue);
      expect(genericEmailDomains.contains('outlook.com'), isTrue);
      expect(genericEmailDomains.contains('proton.me'), isTrue);
      expect(genericEmailDomains.contains('github.com'), isFalse);
      expect(genericEmailDomains.contains('stripe.com'), isFalse);
    });

    test('resolveSenderAvatar returns null for empty or invalid emails', () async {
      expect(await service.resolveSenderAvatar(''), isNull);
      expect(await service.resolveSenderAvatar('   '), isNull);
      expect(await service.resolveSenderAvatar('not-an-email'), isNull);
    });
  });

  group('Sender avatar resolution and caching', () {
    test('returns FileImage when local cached avatar file exists on disk', () async {
      final email = 'user@customdomain.org';
      final emailHash = AvatarService.hashKey(email);
      final cachedFile = File(p.join(tempDir.path, 'gravatar_$emailHash.png'));
      await cachedFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final result = await service.resolveSenderAvatar(email, allowRemote: false);
      expect(result, isA<FileImage>());
      expect((result as FileImage).file.path, equals(cachedFile.path));
      expect(service.getCached(email), equals(result));
    });

    test('returns FileImage when cached domain favicon exists on disk', () async {
      final email = 'notifications@github.com';
      final domainHash = AvatarService.hashKey('github.com');
      final cachedFile = File(p.join(tempDir.path, 'domain_$domainHash.ico'));
      await cachedFile.writeAsBytes([0x00, 0x00, 0x01, 0x00]);

      final result = await service.resolveSenderAvatar(email, allowRemote: false);
      expect(result, isA<FileImage>());
      expect((result as FileImage).file.path, equals(cachedFile.path));
    });

    test('negative caching prevents repeated queries for unknown senders', () async {
      final email = 'unknown@nowhere12345.org';
      final first = await service.resolveSenderAvatar(email, allowRemote: false);
      expect(first, isNull);

      final second = await service.resolveSenderAvatar(email, allowRemote: false);
      expect(second, isNull);
    });
  });

  group('Added accounts multi-layered avatar resolution', () {
    test('Tier 1: returns NetworkImage when account has http/https avatarUrl', () async {
      const account = Account(
        id: 'acc1',
        provider: 'gmail',
        email: 'user@gmail.com',
        displayName: 'User Name',
        avatarUrl: 'https://lh3.googleusercontent.com/a/photo.jpg',
        color: 0xFF4C5BD4,
      );

      final result = await service.resolveAccountAvatar(account);
      expect(result, isA<NetworkImage>());
      expect((result as NetworkImage).url, equals(account.avatarUrl));
    });

    test('Tier 1: returns FileImage when account has local file avatarUrl', () async {
      final customFile = File(p.join(tempDir.path, 'custom_avatar.png'));
      await customFile.writeAsBytes([1, 2, 3, 4]);

      final account = Account(
        id: 'acc2',
        provider: 'imap',
        email: 'me@myserver.com',
        displayName: 'Me',
        avatarUrl: customFile.path,
        color: 0xFF4C5BD4,
      );

      final result = await service.resolveAccountAvatar(account);
      expect(result, isA<FileImage>());
      expect((result as FileImage).file.path, equals(customFile.path));
    });

    test('Tier 2: falls back to null (M3 monogram icon) when mail provider does not send an avatar', () async {
      const account = Account(
        id: 'acc3',
        provider: 'imap',
        email: 'ren@domain.org',
        displayName: 'Ren',
        color: 0xFF0B8A6E,
      );

      final result = await service.resolveAccountAvatar(account, enableGravatar: false);
      expect(result, isNull);
    });
  });
}
