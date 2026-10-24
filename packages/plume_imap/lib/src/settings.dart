/// How the connection to a mail server is secured.
enum ConnectionSecurity {
  /// TLS from the first byte (IMAP 993, SMTP 465).
  tls,

  /// A plain connection upgraded with STARTTLS before anything else is sent
  /// (IMAP 143, SMTP 587). Fails if the server does not offer STARTTLS;
  /// never falls back to plain text.
  startTls,

  /// No encryption. Only offered for local bridges such as Proton Mail
  /// Bridge on 127.0.0.1.
  none,
}

/// One server: where it is and how to secure the connection.
final class ServerEndpoint {
  const ServerEndpoint({required this.host, required this.port, required this.security});

  final String host;
  final int port;
  final ConnectionSecurity security;

  /// True for loopback hosts, the only place [ConnectionSecurity.none] is
  /// acceptable.
  bool get isLocal => host == 'localhost' || host == '127.0.0.1' || host == '::1';

  ServerEndpoint copyWith({String? host, int? port, ConnectionSecurity? security}) => ServerEndpoint(
        host: host ?? this.host,
        port: port ?? this.port,
        security: security ?? this.security,
      );

  Map<String, Object?> toJson() => {'host': host, 'port': port, 'security': security.name};

  static ServerEndpoint fromJson(Map<String, Object?> json) {
    final host = json['host'];
    final port = json['port'];
    final security = json['security'];
    if (host is! String || host.isEmpty || port is! int || security is! String) {
      throw FormatException('Invalid server endpoint: $json');
    }
    return ServerEndpoint(
      host: host,
      port: port,
      security: ConnectionSecurity.values.asNameMap()[security] ??
          (throw FormatException('Unknown connection security "$security"')),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerEndpoint && other.host == host && other.port == port && other.security == security;

  @override
  int get hashCode => Object.hash(host, port, security);

  @override
  String toString() => '$host:$port (${security.name})';
}

/// Everything needed to reach an account's servers except the password,
/// which lives in the system keyring. Stored as `Account.providerConfig`.
final class MailServerSettings {
  const MailServerSettings({
    required this.imap,
    required this.smtp,
    required this.username,
    String? smtpUsername,
    this.saveSentCopy = true,
  }) : _smtpUsername = smtpUsername; // ignore: prefer_initializing_formals

  final ServerEndpoint imap;
  final ServerEndpoint smtp;

  /// IMAP login name (usually the email address).
  final String username;
  final String? _smtpUsername;

  /// SMTP login name; the IMAP one unless the server needs a different one.
  String get smtpUsername => _smtpUsername ?? username;

  /// Whether a copy of sent mail is appended to the Sent folder. Off for
  /// servers that file sent mail themselves (Gmail), which would otherwise
  /// end up with two copies.
  final bool saveSentCopy;

  MailServerSettings copyWith({
    ServerEndpoint? imap,
    ServerEndpoint? smtp,
    String? username,
    String? smtpUsername,
    bool? saveSentCopy,
  }) =>
      MailServerSettings(
        imap: imap ?? this.imap,
        smtp: smtp ?? this.smtp,
        username: username ?? this.username,
        smtpUsername: smtpUsername ?? _smtpUsername,
        saveSentCopy: saveSentCopy ?? this.saveSentCopy,
      );

  Map<String, Object?> toJson() => {
        'imap': imap.toJson(),
        'smtp': smtp.toJson(),
        'username': username,
        if (_smtpUsername != null) 'smtpUsername': _smtpUsername,
        'saveSentCopy': saveSentCopy,
      };

  /// Throws [FormatException] when [json] is not a valid settings object.
  static MailServerSettings fromJson(Map<String, Object?> json) {
    final imap = json['imap'];
    final smtp = json['smtp'];
    final username = json['username'];
    if (imap is! Map || smtp is! Map || username is! String) {
      throw const FormatException('Incomplete mail server settings');
    }
    return MailServerSettings(
      imap: ServerEndpoint.fromJson(imap.cast<String, Object?>()),
      smtp: ServerEndpoint.fromJson(smtp.cast<String, Object?>()),
      username: username,
      smtpUsername: json['smtpUsername'] as String?,
      saveSentCopy: json['saveSentCopy'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MailServerSettings &&
      other.imap == imap &&
      other.smtp == smtp &&
      other.username == username &&
      other._smtpUsername == _smtpUsername &&
      other.saveSentCopy == saveSentCopy;

  @override
  int get hashCode => Object.hash(imap, smtp, username, _smtpUsername, saveSentCopy);

  @override
  String toString() => 'MailServerSettings(imap: $imap, smtp: $smtp, user: $username)';
}
