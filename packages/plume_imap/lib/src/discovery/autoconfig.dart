import 'package:xml/xml.dart';

import '../settings.dart';
import 'email_address.dart';

/// What a Thunderbird-style autoconfig file (a provider's own, or Mozilla's
/// ISPDB) says about an address.
final class AutoconfigResult {
  const AutoconfigResult({required this.settings, this.displayName, this.oauthOnly = false});

  final MailServerSettings settings;

  /// The provider's name, e.g. "Posteo".
  final String? displayName;

  /// The servers only accept OAuth2, so password sign-in cannot work.
  /// [settings] then describes those servers anyway.
  final bool oauthOnly;
}

/// One `incomingServer` / `outgoingServer` entry we could use.
final class _Server {
  const _Server(this.endpoint, this.username, {required this.password, required this.oauth, required this.order});

  final ServerEndpoint endpoint;
  final String username;

  /// Accepts a password (PLAIN or LOGIN over TLS).
  final bool password;
  final bool oauth;

  /// Position in the file, to keep the provider's order among equals.
  final int order;

  int get _rank => switch (endpoint.security) {
    ConnectionSecurity.tls => 0,
    ConnectionSecurity.startTls => 1,
    ConnectionSecurity.none => 2,
  };

  static int compare(_Server a, _Server b) {
    final byRank = a._rank.compareTo(b._rank);
    return byRank != 0 ? byRank : a.order.compareTo(b.order);
  }
}

/// Authentication values that mean "a password works". `password-encrypted`
/// (CRAM-MD5) is included: servers offering it accept PLAIN over TLS too.
const _passwordMethods = {'password-cleartext', 'plain', 'password-encrypted', 'secure'};

/// Parses an autoconfig document ([format](https://wiki.mozilla.org/Thunderbird:Autoconfiguration:ConfigFileFormat))
/// for [email]. Only IMAP and SMTP are considered (POP3 is ignored). Among
/// usable servers SSL/TLS is preferred over STARTTLS; unencrypted servers
/// are only accepted on this computer. Returns null for anything malformed
/// or unusable.
AutoconfigResult? parseAutoconfig(String xml, EmailAddress email) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on Exception {
    return null;
  }
  final root = document.rootElement;
  if (root.name.local != 'clientConfig') return null;
  final provider = root.getElement('emailProvider');
  if (provider == null) return null;

  var order = 0;
  List<_Server> servers(String element, String type) => [
    for (final e in provider.findElements(element))
      if (e.getAttribute('type')?.toLowerCase() == type) ?_parseServer(e, email, order++),
  ]..sort(_Server.compare);

  final imap = servers('incomingServer', 'imap');
  final smtp = servers('outgoingServer', 'smtp');
  if (imap.isEmpty || smtp.isEmpty) return null;

  final displayName = provider.getElement('displayName')?.innerText.trim();
  final name = displayName == null || displayName.isEmpty ? null : displayName;

  final imapPassword = imap.where((s) => s.password).firstOrNull;
  final smtpPassword = smtp.where((s) => s.password).firstOrNull;
  if (imapPassword != null && smtpPassword != null) {
    return AutoconfigResult(settings: _settings(imapPassword, smtpPassword), displayName: name);
  }
  // No password route on one side. If that side offers OAuth2, the provider
  // simply needs its own sign-in; otherwise (NTLM, client certificates...)
  // the file is of no use to us.
  final imapOauth = imapPassword ?? imap.where((s) => s.oauth).firstOrNull;
  final smtpOauth = smtpPassword ?? smtp.where((s) => s.oauth).firstOrNull;
  if (imapOauth == null || smtpOauth == null) return null;
  return AutoconfigResult(settings: _settings(imapOauth, smtpOauth), displayName: name, oauthOnly: true);
}

MailServerSettings _settings(_Server imap, _Server smtp) => MailServerSettings(
  imap: imap.endpoint,
  smtp: smtp.endpoint,
  username: imap.username,
  smtpUsername: smtp.username == imap.username ? null : smtp.username,
);

final RegExp _hostname = RegExp(r'^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$');

_Server? _parseServer(XmlElement element, EmailAddress email, int order) {
  String? text(String name) {
    final value = element.getElement(name)?.innerText.trim();
    return value == null || value.isEmpty ? null : _substitute(value, email);
  }

  final host = text('hostname')?.toLowerCase();
  final port = int.tryParse(text('port') ?? '');
  if (host == null || !_hostname.hasMatch(host) || port == null || port < 1 || port > 65535) return null;
  final security = switch (text('socketType')?.toUpperCase()) {
    'SSL' => ConnectionSecurity.tls,
    'STARTTLS' => ConnectionSecurity.startTls,
    'PLAIN' => ConnectionSecurity.none,
    _ => null,
  };
  if (security == null) return null;
  final endpoint = ServerEndpoint(host: host, port: port, security: security);
  if (security == ConnectionSecurity.none && !endpoint.isLocal) return null;

  var username = text('username');
  if (username == null || username.contains('%')) username = email.address;

  final methods = [for (final a in element.findElements('authentication')) a.innerText.trim().toLowerCase()];
  return _Server(
    endpoint,
    username,
    // No <authentication> means the default, password-cleartext.
    password: methods.isEmpty || methods.any(_passwordMethods.contains),
    oauth: methods.contains('oauth2'),
    order: order,
  );
}

String _substitute(String value, EmailAddress email) => value
    .replaceAll('%EMAILADDRESS%', email.address)
    .replaceAll('%EMAILLOCALPART%', email.localPart)
    .replaceAll('%EMAILDOMAIN%', email.domain);
