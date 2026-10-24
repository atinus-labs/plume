/// IMAP/SMTP mail provider for Plume: works with any standard mail server,
/// with Gmail extensions used when available, plus server auto-discovery.
library;

export 'src/connection_check.dart';
export 'src/discovery/discovery.dart' show discoverSettings;
export 'src/discovery/dns.dart' show MxLookup, MxRecord;
export 'src/discovery/known_providers.dart' show providerInfoFor;
export 'src/discovery/probe.dart' show ServerProbe;
export 'src/discovery/provider_info.dart';
export 'src/imap/imap_client.dart' show ImapClientConfig;
export 'src/imap/login_check.dart' show ImapLoginInfo, checkImapLogin;
export 'src/mail_sender.dart';
export 'src/provider/context.dart' show ImapSyncConfig;
export 'src/provider/imap_provider.dart' show ImapProvider;
export 'src/provider/imap_provider_factory.dart' show ImapProviderFactory;
export 'src/settings.dart';
export 'src/smtp/smtp_client.dart' show SmtpConfig;
export 'src/smtp/smtp_mail_sender.dart' show SmtpMailSender, checkSmtpLogin;
