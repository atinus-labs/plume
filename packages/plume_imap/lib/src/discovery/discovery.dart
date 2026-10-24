import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../connection_check.dart';
import '../settings.dart';
import 'autoconfig.dart';
import 'dns.dart';
import 'email_address.dart';
import 'known_providers.dart';
import 'probe.dart';
import 'provider_info.dart';

final Logger _log = Logger('plume.discovery');

/// Finds the IMAP and SMTP settings for [email], the way Thunderbird does,
/// trying in order:
///
/// 1. Plume's built-in table of major providers.
/// 2. The domain's own autoconfig file, from `https://autoconfig.<domain>/`
///    or `https://<domain>/.well-known/autoconfig/`.
/// 3. Mozilla's ISP database (autoconfig.thunderbird.net).
/// 4. The domain's MX records: custom domains hosted by a known provider
///    (Google Workspace, Microsoft 365, Fastmail, Zoho, iCloud, Proton...),
///    else the ISP database entry for the mail host's domain.
/// 5. Guessing: `imap.`/`mail.<domain>` and `smtp.`/`mail.<domain>` on the
///    standard ports, accepted only if a real mail server answers.
///
/// Only HTTPS is used, and only the domain is sent, never the address.
/// Every failure (timeouts, bad XML, redirects to plain HTTP) just moves on
/// to the next step. Returns null when nothing was found within [timeout];
/// the UI then asks for the servers.
///
/// [client], [mxLookup] and [probe] replace the network for tests.
Future<DiscoveredSettings?> discoverSettings(
  String email, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
  MxLookup? mxLookup,
  ServerProbe? probe,
}) async {
  final address = EmailAddress.tryParse(email);
  if (address == null) return null;
  final httpClient = client ?? http.Client();
  final discovery = _Discovery(address, httpClient, mxLookup ?? DnsClient().lookupMx, probe ?? probeGreeting);
  try {
    return await discovery.run().timeout(
      timeout,
      onTimeout: () {
        _log.fine('Discovery for ${address.domain} timed out');
        return null;
      },
    );
  } finally {
    discovery.cancelled = true;
    if (client == null) httpClient.close();
  }
}

final class _Discovery {
  _Discovery(this.email, this._client, this._mxLookup, this._probe);

  final EmailAddress email;
  final http.Client _client;
  final MxLookup _mxLookup;
  final ServerProbe _probe;

  /// Set when the caller stopped waiting; remaining steps are skipped.
  bool cancelled = false;

  static const _httpTimeout = Duration(seconds: 8);
  static const _dnsTimeout = Duration(seconds: 8);
  static const _maxBody = 512 * 1024;

  String get _domain => email.domain;

  Future<DiscoveredSettings?> run() async {
    final known = knownProviderForDomain(_domain);
    if (known != null) {
      _log.fine('${email.domain}: built-in provider ${known.info.name}');
      return _fromKnown(known);
    }
    final steps = <Future<DiscoveredSettings?> Function()>[_ownAutoconfig, _ispdb, _mx, _guess];
    for (final step in steps) {
      if (cancelled) return null;
      final found = await step();
      if (found != null) return found;
    }
    _log.fine('$_domain: nothing found');
    return null;
  }

  DiscoveredSettings _fromKnown(KnownProvider known) =>
      DiscoveredSettings(settings: known.settingsFor(email), source: DiscoverySource.builtIn, provider: known.info);

  // 2. The domain's own autoconfig -------------------------------------------

  Future<DiscoveredSettings?> _ownAutoconfig() async {
    // Both locations are the domain owner's, so ask both at once and
    // prefer autoconfig.<domain>, as Thunderbird does.
    final fetches = [
      _fetch(Uri.https('autoconfig.$_domain', '/mail/config-v1.1.xml')),
      _fetch(Uri.https(_domain, '/.well-known/autoconfig/mail/config-v1.1.xml')),
    ];
    for (final fetch in fetches) {
      final found = _fromAutoconfig(await fetch, DiscoverySource.provider);
      if (found != null) {
        _log.fine('$_domain: found the provider\'s autoconfig');
        return found;
      }
    }
    return null;
  }

  // 3. Mozilla ISPDB -----------------------------------------------------------

  Future<DiscoveredSettings?> _ispdb([String? domain]) async {
    final lookup = domain ?? _domain;
    final found = _fromAutoconfig(
      await _fetch(Uri.https('autoconfig.thunderbird.net', '/v1.1/$lookup')),
      DiscoverySource.ispdb,
    );
    if (found != null) _log.fine('$_domain: found in ISPDB as $lookup');
    return found;
  }

  // 4. MX ---------------------------------------------------------------------

  Future<DiscoveredSettings?> _mx() async {
    List<MxRecord> records;
    try {
      records = await _mxLookup(_domain).timeout(_dnsTimeout);
    } on Object catch (e) {
      _log.fine('$_domain: MX lookup failed (${e.runtimeType})');
      return null;
    }
    if (records.isEmpty || cancelled) return null;
    final host = records.first.host;
    final known = knownProviderForMx(host);
    if (known != null) {
      _log.fine('$_domain: MX $host is ${known.info.name}');
      return _fromKnown(known);
    }
    // ISPDB lists many hosting companies under their own domain.
    for (final candidate in mxLookupDomains(host)) {
      if (candidate == _domain || cancelled) continue;
      final found = await _ispdb(candidate);
      if (found != null) return found;
    }
    return null;
  }

  // 5. Guess ------------------------------------------------------------------

  Future<DiscoveredSettings?> _guess() async {
    ServerEndpoint at(String prefix, int port, ConnectionSecurity security) =>
        ServerEndpoint(host: '$prefix.$_domain', port: port, security: security);
    // In order of preference: implicit TLS first, the specific name first.
    final imap = [
      at('imap', 993, ConnectionSecurity.tls),
      at('mail', 993, ConnectionSecurity.tls),
      at('imap', 143, ConnectionSecurity.startTls),
      at('mail', 143, ConnectionSecurity.startTls),
    ];
    final smtp = [
      at('smtp', 465, ConnectionSecurity.tls),
      at('mail', 465, ConnectionSecurity.tls),
      at('smtp', 587, ConnectionSecurity.startTls),
      at('mail', 587, ConnectionSecurity.startTls),
    ];
    Future<bool> probe(ServerEndpoint e, MailProtocol p) => _probe(e, p).catchError((Object _) => false);
    final results = await Future.wait([
      for (final e in imap) probe(e, MailProtocol.imap),
      for (final e in smtp) probe(e, MailProtocol.smtp),
    ]);
    ServerEndpoint? first(List<ServerEndpoint> candidates, int offset) {
      for (var i = 0; i < candidates.length; i++) {
        if (results[offset + i]) return candidates[i];
      }
      return null;
    }

    final foundImap = first(imap, 0);
    final foundSmtp = first(smtp, imap.length);
    if (foundImap == null || foundSmtp == null) return null;
    _log.fine('$_domain: guessed $foundImap and $foundSmtp');
    return DiscoveredSettings(
      settings: MailServerSettings(imap: foundImap, smtp: foundSmtp, username: email.address),
      source: DiscoverySource.guess,
    );
  }

  // Helpers -------------------------------------------------------------------

  DiscoveredSettings? _fromAutoconfig(String? body, DiscoverySource source) {
    if (body == null) return null;
    final result = parseAutoconfig(body, email);
    if (result == null) return null;
    var settings = result.settings;
    // Settings pointing at a provider we know get its hints (Gmail's app
    // password) and quirks (Gmail files sent mail itself).
    final known = knownProviderForImapHost(settings.imap.host);
    if (known != null && !known.saveSentCopy) settings = settings.copyWith(saveSentCopy: false);
    final name = result.displayName ?? known?.info.name ?? _domain;
    final ProviderInfo? info;
    if (result.oauthOnly) {
      info = ProviderInfo(
        name: name,
        unsupportedReason:
            known?.info.unsupportedReason ??
            "$name only allows signing in through its own sign-in page, which Plume doesn't support yet.",
      );
    } else {
      info = known?.info ?? (result.displayName == null ? null : ProviderInfo(name: name));
    }
    return DiscoveredSettings(settings: settings, source: source, provider: info);
  }

  /// GETs [url] over HTTPS, following at most three redirects (HTTPS only).
  /// Null on any failure.
  Future<String?> _fetch(Uri url) async {
    try {
      return await _fetchFollowing(url).timeout(_httpTimeout);
    } on Object catch (e) {
      _log.fine('Fetching from ${url.host} failed (${e.runtimeType})');
      return null;
    }
  }

  Future<String?> _fetchFollowing(Uri url) async {
    var current = url;
    for (var hop = 0; hop < 4; hop++) {
      // Never downgrade: a redirect to plain HTTP could be forged.
      if (current.scheme != 'https' || cancelled) return null;
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['accept'] = 'application/xml, text/xml;q=0.9, */*;q=0.1';
      final response = await _client.send(request);
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (location == null) return null;
        current = current.resolve(location);
        continue;
      }
      if (status != 200) {
        await response.stream.drain<void>();
        return null;
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        body.add(chunk);
        if (body.length > _maxBody) throw const FormatException('Autoconfig file too large');
      }
      var text = utf8.decode(body.takeBytes(), allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      return text;
    }
    return null;
  }
}

/// Domains to look up in ISPDB for a mail host: the host without its first
/// label, and its registrable domain (`mx1.mail.example.co.uk` gives
/// `mail.example.co.uk` and `example.co.uk`).
List<String> mxLookupDomains(String mxHost) {
  final labels = mxHost.split('.');
  final candidates = <String>[];
  if (labels.length > 2) candidates.add(labels.skip(1).join('.'));
  final base = registrableDomain(mxHost);
  if (!candidates.contains(base)) candidates.add(base);
  return candidates;
}

/// A cheap approximation of the registrable domain (eTLD+1) without the
/// Public Suffix List: two labels, or three under the common second-level
/// suffixes of country domains (co.uk, com.au, ne.jp...).
String registrableDomain(String host) {
  const secondLevel = {'co', 'com', 'net', 'org', 'ac', 'gov', 'edu', 'ne', 'or', 'go'};
  final labels = host.split('.');
  if (labels.length <= 2) return host;
  final countryCode = labels.last.length == 2;
  final keep = countryCode && secondLevel.contains(labels[labels.length - 2]) ? 3 : 2;
  return labels.skip(labels.length - keep).join('.');
}
