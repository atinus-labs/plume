import '../settings.dart';
import 'email_address.dart';
import 'provider_info.dart';

/// How a provider spells the login name.
enum LoginName {
  /// The full address, `jane@example.com` (almost everyone).
  address,

  /// Only the part before the `@`, `jane`.
  localPart;

  String of(EmailAddress email) => this == address ? email.address : email.localPart;
}

/// A built-in provider: where its servers are and how to talk to the user
/// about signing in.
final class KnownProvider {
  const KnownProvider({
    required this.info,
    required this.imap,
    required this.smtp,
    this.domains = const {},
    this.mxSuffixes = const [],
    this.imapLogin = LoginName.address,
    this.smtpLogin = LoginName.address,
    this.saveSentCopy = true,
  });

  final ProviderInfo info;

  /// Address domains served by this provider.
  final Set<String> domains;

  /// MX host suffixes identifying custom domains hosted here
  /// (`google.com` matches `aspmx.l.google.com`).
  final List<String> mxSuffixes;

  final ServerEndpoint imap;
  final ServerEndpoint smtp;
  final LoginName imapLogin;
  final LoginName smtpLogin;

  /// False for providers that file sent mail themselves.
  final bool saveSentCopy;

  MailServerSettings settingsFor(EmailAddress email) {
    final imapUser = imapLogin.of(email);
    final smtpUser = smtpLogin.of(email);
    return MailServerSettings(
      imap: imap,
      smtp: smtp,
      username: imapUser,
      smtpUsername: smtpUser == imapUser ? null : smtpUser,
      saveSentCopy: saveSentCopy,
    );
  }

  /// Whether [mxHost] (lower case, no trailing dot) belongs to this provider.
  bool hostsMx(String mxHost) => mxSuffixes.any((s) => mxHost == s || mxHost.endsWith('.$s'));
}

const _tls = ConnectionSecurity.tls;
const _startTls = ConnectionSecurity.startTls;

const _microsoftOAuthOnly =
    'Microsoft no longer allows password sign-in for IMAP and SMTP; it requires its own '
    "sign-in, which Plume doesn't support yet.";

// Every entry was checked against the provider's own documentation on
// 2026-10-24; the source is noted above it.

// https://support.google.com/mail/answer/7126229 (IMAP/SMTP),
// https://support.google.com/accounts/answer/185833 (app passwords, need 2-Step Verification).
// Gmail files sent mail on its own: appending a copy would duplicate it.
final _gmail = KnownProvider(
  info: ProviderInfo(
    name: 'Gmail',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://myaccount.google.com/apppasswords'),
    note:
        'Google only lets other mail apps sign in with an app password. Turn on 2-Step Verification '
        'for your Google Account, then create an app password and use it here.',
  ),
  domains: const {'gmail.com', 'googlemail.com'},
  imap: const ServerEndpoint(host: 'imap.gmail.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.gmail.com', port: 465, security: _tls),
  saveSentCopy: false,
);

// Same servers; https://support.google.com/a/answer/176600 and /a/answer/6260879.
// Password sign-in ended for Workspace in May 2025, but app passwords still
// work where the administrator allows them.
final _googleWorkspace = KnownProvider(
  info: ProviderInfo(
    name: 'Google Workspace',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://myaccount.google.com/apppasswords'),
    note:
        'Use an app password from your Google Account (2-Step Verification must be on). '
        'Your organization may have turned app passwords off.',
  ),
  mxSuffixes: const ['google.com', 'googlemail.com'],
  imap: _gmail.imap,
  smtp: _gmail.smtp,
  saveSentCopy: false,
);

// https://support.apple.com/en-us/102525 (servers; the IMAP user name is the
// address without the domain, SMTP wants the full address; port 587 only),
// https://support.apple.com/en-us/102654 (app-specific passwords).
final _icloudInfo = ProviderInfo(
  name: 'iCloud Mail',
  needsAppPassword: true,
  appPasswordHelp: Uri.parse('https://account.apple.com/account/manage'),
  note:
      'Apple requires an app-specific password for other mail apps. Create one under '
      'Sign-In and Security at account.apple.com (two-factor authentication must be on).',
);
final _icloud = KnownProvider(
  info: _icloudInfo,
  domains: const {'icloud.com', 'me.com', 'mac.com'},
  imap: const ServerEndpoint(host: 'imap.mail.me.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.mail.me.com', port: 587, security: _startTls),
  imapLogin: LoginName.localPart,
);

// Custom domains on iCloud+ (MX mx01/mx02.mail.icloud.com,
// https://support.apple.com/en-us/102374). The login is the Apple Account's
// iCloud address, which cannot be derived from the custom one.
final _icloudCustomDomain = KnownProvider(
  info: ProviderInfo(
    name: 'iCloud Mail',
    needsAppPassword: true,
    appPasswordHelp: _icloudInfo.appPasswordHelp,
    note:
        'Sign in with your iCloud Mail address (such as name@icloud.com) and an app-specific '
        'password from account.apple.com.',
  ),
  mxSuffixes: const ['mail.icloud.com'],
  imap: _icloud.imap,
  smtp: _icloud.smtp,
);

// https://help.yahoo.com/kb/SLN4075.html (servers),
// https://help.yahoo.com/kb/SLN15241.html (app passwords).
// Yahoo Japan (yahoo.co.jp) is a separate company and not included.
final _yahoo = KnownProvider(
  info: ProviderInfo(
    name: 'Yahoo Mail',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://login.yahoo.com/account/security'),
    note:
        'Yahoo requires an app password for other mail apps. Create one under '
        'Account Security, "Generate app password".',
  ),
  domains: const {
    'yahoo.com', 'ymail.com', 'rocketmail.com', 'yahoo.co.uk', 'yahoo.ie', 'yahoo.fr', 'yahoo.de', //
    'yahoo.it', 'yahoo.es', 'yahoo.ca', 'yahoo.com.au', 'yahoo.co.nz', 'yahoo.co.in', 'yahoo.in',
    'yahoo.com.br', 'yahoo.com.mx', 'yahoo.com.ar', 'yahoo.se', 'yahoo.dk', 'yahoo.no', 'yahoo.fi',
    'yahoo.at', 'yahoo.be', 'yahoo.nl', 'yahoo.pl', 'yahoo.gr', 'yahoo.ro', 'yahoo.co.id',
    'yahoo.com.sg', 'yahoo.com.ph', 'yahoo.com.my', 'yahoo.com.vn', 'yahoo.com.tw', 'yahoo.com.hk',
    'yahoo.co.za',
  },
  imap: const ServerEndpoint(host: 'imap.mail.yahoo.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.mail.yahoo.com', port: 465, security: _tls),
);

// https://help.aol.com/articles/create-and-manage-app-password. AOL's IMAP
// article names export.imap.aol.com; imap.aol.com (used by Thunderbird and
// every client guide) resolves to the same servers.
final _aol = KnownProvider(
  info: ProviderInfo(
    name: 'AOL Mail',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://login.aol.com/myaccount/security'),
    note: 'AOL requires an app password for other mail apps. Create one under Account Security.',
  ),
  domains: const {'aol.com', 'aim.com'},
  imap: const ServerEndpoint(host: 'imap.aol.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.aol.com', port: 465, security: _tls),
);

// https://www.fastmail.help/hc/en-us/articles/1500000278342 (servers),
// https://www.fastmail.help/hc/en-us/articles/360058752854 (app passwords are
// mandatory). MX in1-smtp.messagingengine.com for custom domains.
final _fastmail = KnownProvider(
  info: ProviderInfo(
    name: 'Fastmail',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://www.fastmail.help/hc/en-us/articles/360058752854'),
    note:
        'Fastmail needs an app password with IMAP and SMTP access (Settings, Privacy & Security). '
        'Not available on the Basic plan.',
  ),
  domains: const {
    'fastmail.com', 'fastmail.fm', 'fastmail.net', 'fastmail.org', 'fastmail.us', 'fastmail.uk', //
    'fastmail.co.uk', 'fastmail.de', 'fastmail.fr', 'fastmail.nl', 'fastmail.se', 'fastmail.es',
    'fastmail.jp', 'fastmail.in', 'fastmail.cn', 'fastmail.mx', 'fastmail.to', 'fastmail.tw',
    'sent.com', 'eml.cc', 'mailbolt.com', 'imap.cc',
  },
  mxSuffixes: const ['messagingengine.com'],
  imap: const ServerEndpoint(host: 'imap.fastmail.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.fastmail.com', port: 465, security: _tls),
);

// https://www.zoho.com/mail/help/imap-access.html, /zoho-smtp.html. Personal
// accounts use imap/smtp.zoho.<region>; organizations (custom domains) on
// paid plans use imappro/smtppro. Zoho only documents the .com names; the
// regional ones exist in DNS and are what Zoho shows in each data center.
const _zohoRegions = {
  'zoho.com': ['zoho.com', 'zohomail.com'],
  'zoho.eu': ['zohomail.eu'],
  'zoho.in': ['zohomail.in'],
  'zoho.com.au': ['zohomail.com.au'],
  'zoho.jp': <String>[],
  'zohocloud.ca': <String>[],
  'zoho.sa': <String>[],
  'zoho.uk': <String>[],
};
final _zohoInfo = ProviderInfo(
  name: 'Zoho Mail',
  helpUrl: Uri.parse('https://www.zoho.com/mail/help/imap-access.html'),
  note:
      'Turn on IMAP access in Zoho Mail (Settings, Mail Accounts, IMAP). With two-factor '
      'authentication on, use an app-specific password.',
);
final _zoho = [
  for (final MapEntry(key: region, value: domains) in _zohoRegions.entries) ...[
    if (domains.isNotEmpty)
      KnownProvider(
        info: _zohoInfo,
        domains: domains.toSet(),
        imap: ServerEndpoint(host: 'imap.$region', port: 993, security: _tls),
        smtp: ServerEndpoint(host: 'smtp.$region', port: 465, security: _tls),
      ),
    KnownProvider(
      info: _zohoInfo,
      mxSuffixes: [region],
      imap: ServerEndpoint(host: 'imappro.$region', port: 993, security: _tls),
      smtp: ServerEndpoint(host: 'smtppro.$region', port: 465, security: _tls),
    ),
  ],
];

// https://hilfe.gmx.net/pop-imap/imap/imap-serverdaten.html,
// https://hilfe.gmx.net/pop-imap/einschalten.html (IMAP is off by default).
final _gmxDe = KnownProvider(
  info: ProviderInfo(
    name: 'GMX',
    helpUrl: Uri.parse('https://hilfe.gmx.net/pop-imap/einschalten.html'),
    note:
        'Turn on POP3/IMAP access in the GMX web mail settings first. With two-factor '
        'authentication on, use an app password.',
  ),
  domains: const {'gmx.net', 'gmx.de', 'gmx.at', 'gmx.ch', 'gmx.eu', 'gmx.biz', 'gmx.org', 'gmx.info'},
  imap: const ServerEndpoint(host: 'imap.gmx.net', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'mail.gmx.net', port: 465, security: _tls),
);

// https://support.gmx.com/pop-imap/imap/server.html (international GMX).
final _gmxCom = KnownProvider(
  info: ProviderInfo(
    name: 'GMX',
    helpUrl: Uri.parse('https://support.gmx.com/pop-imap/imap/server.html'),
    note: 'Turn on POP3/IMAP access in the GMX web mail settings first.',
  ),
  domains: const {'gmx.com'},
  imap: const ServerEndpoint(host: 'imap.gmx.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'mail.gmx.com', port: 465, security: _tls),
);

// https://hilfe.web.de/pop-imap/imap/imap-serverdaten.html
final _webDe = KnownProvider(
  info: ProviderInfo(
    name: 'WEB.DE',
    helpUrl: Uri.parse('https://hilfe.web.de/pop-imap/einschalten.html'),
    note: 'Turn on POP3/IMAP access in the WEB.DE web mail settings first.',
  ),
  domains: const {'web.de'},
  imap: const ServerEndpoint(host: 'imap.web.de', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.web.de', port: 465, security: _tls),
);

// https://support.mail.com/pop-imap/imap/server.html,
// https://support.mail.com/pop-imap/toggle.html (Premium only). mail.com has
// about 200 vanity domains; the common ones are listed, the rest are found
// through ISPDB or their MX (mx00.mail.com).
final _mailCom = KnownProvider(
  info: ProviderInfo(
    name: 'mail.com',
    helpUrl: Uri.parse('https://support.mail.com/pop-imap/toggle.html'),
    note: 'IMAP and SMTP need mail.com Premium and must be turned on in the web mail settings.',
  ),
  domains: const {
    'mail.com', 'email.com', 'usa.com', 'post.com', 'consultant.com', 'engineer.com', 'myself.com', //
    'dr.com', 'techie.com', 'writeme.com', 'cheerful.com', 'europe.com', 'asia.com', 'iname.com',
  },
  mxSuffixes: const ['mail.com'],
  imap: const ServerEndpoint(host: 'imap.mail.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.mail.com', port: 465, security: _tls),
);

// https://yandex.com/support/yandex-360/customers/mail/en/mail-clients/others
// (login is the part before the @; app passwords required). Custom domains
// on Yandex 360 (MX mx.yandex.net) sign in with the full address.
final _yandexInfo = ProviderInfo(
  name: 'Yandex Mail',
  needsAppPassword: true,
  appPasswordHelp: Uri.parse('https://id.yandex.com/security/app-passwords'),
  note: 'Turn on IMAP in Yandex Mail settings (Email clients), then create an app password of type Mail.',
);
final _yandex = KnownProvider(
  info: _yandexInfo,
  domains: const {'yandex.com', 'yandex.ru', 'ya.ru', 'yandex.by', 'yandex.kz', 'yandex.ua'},
  imap: const ServerEndpoint(host: 'imap.yandex.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.yandex.com', port: 465, security: _tls),
  imapLogin: LoginName.localPart,
  smtpLogin: LoginName.localPart,
);
final _yandexCustomDomain = KnownProvider(
  info: _yandexInfo,
  mxSuffixes: const ['mx.yandex.net', 'mx.yandex.ru'],
  imap: _yandex.imap,
  smtp: _yandex.smtp,
);

// https://kb.mailbox.org/en/business/e-mail/e-mail-configuration
final _mailboxOrg = KnownProvider(
  info: const ProviderInfo(
    name: 'mailbox.org',
    note: 'With two-factor authentication on, create an application password in the mailbox.org settings.',
  ),
  domains: const {'mailbox.org'},
  mxSuffixes: const ['mailbox.org'],
  imap: const ServerEndpoint(host: 'imap.mailbox.org', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp.mailbox.org', port: 465, security: _tls),
);

// https://posteo.de/en/help/how-do-i-set-up-posteo-in-an-email-client-pop3-imap-and-smtp,
// https://posteo.de/en/help/app-passwords. Domains from Posteo's own ISPDB entry.
final _posteo = KnownProvider(
  info: ProviderInfo(
    name: 'Posteo',
    helpUrl: Uri.parse('https://posteo.de/en/help/app-passwords'),
    note:
        'If Posteo refuses your password, create an app password under Settings, '
        'My account, Password and security.',
  ),
  domains: const {
    'posteo.de', 'posteo.at', 'posteo.be', 'posteo.ca', 'posteo.ch', 'posteo.cl', 'posteo.co', //
    'posteo.co.uk', 'posteo.com', 'posteo.com.br', 'posteo.cr', 'posteo.cz', 'posteo.dk', 'posteo.ee',
    'posteo.es', 'posteo.eu', 'posteo.fi', 'posteo.gl', 'posteo.gr', 'posteo.hn', 'posteo.hr', 'posteo.hu',
    'posteo.ie', 'posteo.in', 'posteo.is', 'posteo.it', 'posteo.jp', 'posteo.la', 'posteo.li', 'posteo.lt',
    'posteo.lu', 'posteo.me', 'posteo.mx', 'posteo.my', 'posteo.net', 'posteo.nl', 'posteo.no', 'posteo.nz',
    'posteo.org', 'posteo.pe', 'posteo.pl', 'posteo.pm', 'posteo.pt', 'posteo.ro', 'posteo.se', 'posteo.sg',
    'posteo.si', 'posteo.tn', 'posteo.uk', 'posteo.us',
  },
  imap: const ServerEndpoint(host: 'posteo.de', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'posteo.de', port: 465, security: _tls),
);

// Proton Mail has no IMAP; Proton Mail Bridge (paid plans) serves it on this
// computer: 127.0.0.1, IMAP 1143 and SMTP 1025 by default
// (https://proton.me/support/comprehensive-guide-to-bridge-settings).
// Bridge's STARTTLS uses a self-signed certificate that strict validation
// rejects, and Bridge accepts sign-in without it (proton-bridge sets
// AllowInsecureAuth for SMTP; its IMAP server does not advertise
// LOGINDISABLED), so plain loopback is used: the traffic never leaves the
// machine. MX mail.protonmail.ch for custom domains.
final _proton = KnownProvider(
  info: ProviderInfo(
    name: 'Proton Mail',
    needsAppPassword: true,
    appPasswordHelp: Uri.parse('https://proton.me/mail/bridge'),
    note:
        'Proton Mail works through Proton Mail Bridge (paid plans). Install Bridge on this '
        'computer, sign in there, and use the username and password Bridge shows.',
  ),
  domains: const {'proton.me', 'protonmail.com', 'protonmail.ch', 'pm.me'},
  mxSuffixes: const ['protonmail.ch'],
  imap: const ServerEndpoint(host: '127.0.0.1', port: 1143, security: ConnectionSecurity.none),
  smtp: const ServerEndpoint(host: '127.0.0.1', port: 1025, security: ConnectionSecurity.none),
);

// https://support.microsoft.com/en-us/office/pop-imap-and-smtp-settings-for-outlook-com-d088b986-291d-42b8-9564-9c414e2aa040
// ("Outlook.com requires the use of Modern Auth / OAuth2"; basic
// authentication ended on 2024-09-16). Domains from Mozilla's ISPDB entry.
final _outlook = KnownProvider(
  info: const ProviderInfo(name: 'Outlook.com', unsupportedReason: _microsoftOAuthOnly),
  domains: const {
    'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'windowslive.com', //
    'outlook.at', 'outlook.be', 'outlook.cl', 'outlook.cz', 'outlook.de', 'outlook.dk', 'outlook.es',
    'outlook.fr', 'outlook.hu', 'outlook.ie', 'outlook.in', 'outlook.it', 'outlook.jp', 'outlook.kr',
    'outlook.lv', 'outlook.my', 'outlook.ph', 'outlook.pt', 'outlook.sa', 'outlook.sg', 'outlook.sk',
    'outlook.co.id', 'outlook.co.il', 'outlook.co.th', 'outlook.com.ar', 'outlook.com.au', 'outlook.com.br',
    'outlook.com.gr', 'outlook.com.tr', 'outlook.com.vn', 'hotmail.be', 'hotmail.ca', 'hotmail.cl',
    'hotmail.cz', 'hotmail.de', 'hotmail.dk', 'hotmail.es', 'hotmail.fi', 'hotmail.fr', 'hotmail.gr',
    'hotmail.hu', 'hotmail.it', 'hotmail.lt', 'hotmail.lv', 'hotmail.my', 'hotmail.nl', 'hotmail.no',
    'hotmail.ph', 'hotmail.rs', 'hotmail.se', 'hotmail.sg', 'hotmail.sk', 'hotmail.co.id', 'hotmail.co.il',
    'hotmail.co.in', 'hotmail.co.jp', 'hotmail.co.kr', 'hotmail.co.th', 'hotmail.co.uk', 'hotmail.co.za',
    'hotmail.com.ar', 'hotmail.com.au', 'hotmail.com.br', 'hotmail.com.hk', 'hotmail.com.tr',
    'hotmail.com.tw', 'hotmail.com.vn', 'live.at', 'live.be', 'live.ca', 'live.cl', 'live.cn', 'live.de',
    'live.dk', 'live.fi', 'live.fr', 'live.hk', 'live.ie', 'live.in', 'live.it', 'live.jp', 'live.nl',
    'live.no', 'live.ru', 'live.se', 'live.co.jp', 'live.co.kr', 'live.co.uk', 'live.co.za', 'live.com.ar',
    'live.com.au', 'live.com.mx', 'live.com.my', 'live.com.ph', 'live.com.pt', 'live.com.sg', 'livemail.tw',
  },
  imap: const ServerEndpoint(host: 'outlook.office365.com', port: 993, security: _tls),
  smtp: const ServerEndpoint(host: 'smtp-mail.outlook.com', port: 587, security: _startTls),
);

// Custom domains on Microsoft 365: MX <tenant>.mail.protection.outlook.com,
// or *.mx.microsoft for newer DNSSEC-enabled domains. Basic authentication
// for IMAP was switched off in 2022.
const _microsoft365 = KnownProvider(
  info: ProviderInfo(name: 'Microsoft 365', unsupportedReason: _microsoftOAuthOnly),
  mxSuffixes: ['protection.outlook.com', 'mx.microsoft'],
  imap: ServerEndpoint(host: 'outlook.office365.com', port: 993, security: _tls),
  smtp: ServerEndpoint(host: 'smtp.office365.com', port: 587, security: _startTls),
);

/// Every built-in provider.
final List<KnownProvider> knownProviders = [
  _gmail,
  _googleWorkspace,
  _icloud,
  _icloudCustomDomain,
  _yahoo,
  _aol,
  _fastmail,
  ..._zoho,
  _gmxDe,
  _gmxCom,
  _webDe,
  _mailCom,
  _yandex,
  _yandexCustomDomain,
  _mailboxOrg,
  _posteo,
  _proton,
  _outlook,
  _microsoft365,
];

final Map<String, KnownProvider> _byDomain = {
  for (final p in knownProviders)
    for (final d in p.domains) d: p,
};

/// The built-in provider serving addresses at [domain] (lower case).
KnownProvider? knownProviderForDomain(String domain) => _byDomain[domain];

/// The built-in provider hosting custom domains whose MX is [mxHost].
KnownProvider? knownProviderForMx(String mxHost) {
  final host = mxHost.toLowerCase();
  for (final p in knownProviders) {
    if (p.hostsMx(host)) return p;
  }
  return null;
}

/// What Plume knows about the provider of [email], from the built-in table
/// only (no network), so the UI can show hints while the user types: that
/// Gmail needs an app password, that Outlook.com cannot be used, and so on.
/// Null for unknown domains and incomplete addresses.
ProviderInfo? providerInfoFor(String email) {
  final parsed = EmailAddress.tryParse(email);
  if (parsed == null) return null;
  return knownProviderForDomain(parsed.domain)?.info;
}

/// The built-in provider whose IMAP server is [host], preferring the
/// custom-domain variant (an autoconfig file for a custom domain pointing at
/// imap.gmail.com is Google Workspace, not Gmail).
KnownProvider? knownProviderForImapHost(String host) {
  // 127.0.0.1 could be any local bridge, not necessarily Proton's.
  final matches = knownProviders.where((p) => p.imap.host == host && !p.imap.isLocal);
  return matches.where((p) => p.mxSuffixes.isNotEmpty).firstOrNull ?? matches.firstOrNull;
}
