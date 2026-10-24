import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('plume.secrets');

/// Stores credentials outside the mail database.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Human-readable backend name for the settings screen.
  String get backend;
}

/// The system keyring (Secret Service on Linux: GNOME Keyring, KWallet,
/// KeePassXC; Keystore on Android), falling back to a private file when no
/// keyring is running, which is common on minimal Wayland setups. The file
/// fallback is protected by file permissions only, which the settings screen
/// tells the user.
final class SystemSecretStore implements SecretStore {
  SystemSecretStore({required String fallbackDir}) : _fallback = _FileSecrets(fallbackDir);

  final _storage = const FlutterSecureStorage(
    lOptions: LinuxOptions(),
    aOptions: AndroidOptions(),
  );
  final _FileSecrets _fallback;
  bool? _keyringWorks;

  @override
  String get backend => _keyringWorks == false ? 'Private file, readable only by you (no keyring found)' : 'System keyring';

  Future<bool> _keyring() async {
    if (_keyringWorks != null) return _keyringWorks!;
    try {
      await _storage.read(key: 'plume.probe');
      _keyringWorks = true;
    } catch (e) {
      _log.warning('System keyring unavailable, using file fallback: $e');
      _keyringWorks = false;
    }
    return _keyringWorks!;
  }

  @override
  Future<String?> read(String key) async {
    if (await _keyring()) {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    }
    return _fallback.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (await _keyring()) {
      try {
        await _storage.write(key: key, value: value);
        await _fallback.delete(key);
        return;
      } catch (e) {
        _log.warning('Keyring write failed, using file fallback: $e');
      }
    }
    await _fallback.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (await _keyring()) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
    await _fallback.delete(key);
  }
}

/// A JSON file readable only by the user. Lightly obfuscated so secrets do
/// not show up in casual greps; the real protection is the file mode.
final class _FileSecrets {
  _FileSecrets(String dir) : _file = File(p.join(dir, 'secrets.json'));

  final File _file;

  Future<Map<String, String>> _load() async {
    if (!await _file.exists()) return {};
    try {
      final decoded = jsonDecode(utf8.decode(base64.decode((await _file.readAsString()).trim())));
      return (decoded as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, String> data) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(base64.encode(utf8.encode(jsonEncode(data))));
    if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
    await tmp.rename(_file.path);
  }

  Future<String?> read(String key) async => (await _load())[key];

  Future<void> write(String key, String value) async {
    final data = await _load();
    data[key] = value;
    await _save(data);
  }

  Future<void> delete(String key) async {
    final data = await _load();
    if (data.remove(key) != null) await _save(data);
  }
}
