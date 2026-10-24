/// Gmail provider for Plume: Google OAuth (loopback + PKCE), the Gmail REST
/// API for data, and IMAP IDLE as a real-time change doorbell. Pure Dart.
///
/// Typical wiring:
///
/// ```dart
/// final oauth = GoogleOAuth(GoogleOAuthConfig(clientId: id, clientSecret: secret));
///
/// // Adding an account.
/// final tokens = await oauth.signIn(openBrowser: launch);
/// await secrets.write(accountId, jsonEncode(tokens.toJson()));
/// // Account(email: tokens.email, displayName: tokens.name, avatarUrl: tokens.picture, provider: 'gmail', ...)
///
/// // Engine: one factory, one token source per account.
/// final engine = MailEngine(
///   factories: [const GmailProviderFactory()],
///   tokenSourceFor: (account) => GoogleTokenSource.deferred(
///     oauth,
///     load: () async => GoogleTokens.fromJson(jsonDecode(await secrets.read(account.id))),
///     onTokensChanged: (t) => secrets.write(account.id, jsonEncode(t.toJson())),
///   ),
///   ...
/// );
/// ```
library;

export 'package:plume_mime/plume_mime.dart' show BuiltMessage, MimeMessageBuilder;

export 'src/api/gmail_api.dart' show BatchResult, GmailApi, GmailFormat;
export 'src/api/gmail_client.dart'
    show BatchFailure, BatchOutcome, BatchSuccess, GmailClient, GmailClientConfig, GoogleApiError;
export 'src/api/gmail_request.dart' show GmailRequest;
export 'src/api/gmail_types.dart';
export 'src/api/quota.dart' show GmailQuota;
export 'src/auth/google_oauth.dart' show GoogleOAuth, GoogleOAuthConfig;
export 'src/auth/google_token_source.dart' show GoogleTokenSource;
export 'src/auth/google_tokens.dart' show GoogleTokens;
export 'src/auth/loopback_receiver.dart' show GoogleSignInException, SignInFailure;
export 'src/imap/imap_doorbell.dart' show GmailImapDoorbell, ImapConnector, ImapDoorbellConfig;
export 'src/mapping/label_mapper.dart' show GmailLabels;
export 'src/provider/gmail_provider.dart' show GmailProvider, GmailSyncConfig;
export 'src/provider/gmail_provider_factory.dart' show GmailProviderFactory;
export 'src/util/backoff.dart' show RetryBackoff, Sleep;
