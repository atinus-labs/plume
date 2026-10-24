import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Build- and install-time configuration.
abstract final class AppConfig {
  static const appId = 'org.atinus.plume';
  static const appName = 'Plume';

  /// Development mode with a generated demo account instead of real mail.
  static const demo = bool.fromEnvironment('PLUME_DEMO');

  static const _buildClientId = String.fromEnvironment('PLUME_GOOGLE_CLIENT_ID');
  static const _buildClientSecret = String.fromEnvironment('PLUME_GOOGLE_CLIENT_SECRET');

  /// Directory for user configuration (`$XDG_CONFIG_HOME/plume`).
  static String get configDir {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(Platform.environment['HOME'] ?? '.', '.config');
    return p.join(base, 'plume');
  }

  /// Where a Google OAuth client file (as downloaded from Google Cloud
  /// Console) is looked up when the build does not embed one.
  static String get googleClientFile => p.join(configDir, 'google-oauth-client.json');
}

/// A Google OAuth "Desktop app" client.
final class GoogleClient {
  const GoogleClient(this.id, this.secret);

  final String id;
  final String secret;

  /// Resolves the client from build-time defines, falling back to the
  /// client file in the config directory. Returns null when neither exists.
  static GoogleClient? resolve() {
    if (AppConfig._buildClientId.isNotEmpty) {
      return const GoogleClient(AppConfig._buildClientId, AppConfig._buildClientSecret);
    }
    final file = File(AppConfig.googleClientFile);
    if (!file.existsSync()) return null;
    try {
      return parse(file.readAsStringSync());
    } on FormatException {
      return null;
    }
  }

  /// Parses Google's client JSON (`{"installed": {...}}`).
  static GoogleClient parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) throw const FormatException('Not a JSON object');
    final section = (decoded['installed'] ?? decoded['web'] ?? decoded) as Map<String, Object?>;
    final id = section['client_id'];
    final secret = section['client_secret'];
    if (id is! String || id.isEmpty) throw const FormatException('Missing client_id');
    return GoogleClient(id, secret is String ? secret : '');
  }

  /// Validates and stores a client file chosen by the user.
  static Future<GoogleClient> install(String json) async {
    final client = parse(json);
    final file = File(AppConfig.googleClientFile);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
    return client;
  }
}
