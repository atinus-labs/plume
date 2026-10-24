import '../settings.dart';

/// What we know about a well-known mail provider, used to guide the user
/// through password setup.
final class ProviderInfo {
  const ProviderInfo({
    required this.name,
    this.needsAppPassword = false,
    this.appPasswordHelp,
    this.unsupportedReason,
    this.note,
    this.helpUrl,
  });

  /// Display name, e.g. "Gmail" or "iCloud Mail".
  final String name;

  /// The provider rejects the account's normal password over IMAP/SMTP and
  /// needs an app-specific one.
  final bool needsAppPassword;

  /// Where the user creates that app password.
  final Uri? appPasswordHelp;

  /// When set, password sign-in cannot work for this provider (Outlook.com
  /// only accepts OAuth); the UI shows this instead of the form.
  final String? unsupportedReason;

  /// A short setup hint for the password form, e.g. "Turn on IMAP access
  /// in the GMX web mail settings first".
  final String? note;

  /// A page explaining [note], when it is not [appPasswordHelp].
  final Uri? helpUrl;
}

/// Where discovered settings came from, from most to least trustworthy.
enum DiscoverySource {
  /// Plume's own table of major providers.
  builtIn,

  /// The provider's own autoconfig file (`autoconfig.<domain>`, `.well-known`).
  provider,

  /// Mozilla's ISP database (the same one Thunderbird uses).
  ispdb,

  /// Common host names (`imap.<domain>`...) that accepted a connection.
  guess,
}

/// Settings found for an email address.
final class DiscoveredSettings {
  const DiscoveredSettings({required this.settings, required this.source, this.provider});

  final MailServerSettings settings;
  final DiscoverySource source;
  final ProviderInfo? provider;
}
