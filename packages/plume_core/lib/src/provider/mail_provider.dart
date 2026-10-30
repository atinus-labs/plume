import 'dart:typed_data';

import '../models/account.dart';
import '../models/mailbox.dart';
import '../models/message.dart';
import '../models/outgoing.dart';
import '../ops/mail_operation.dart';
import '../store/sync_store.dart';

/// Supplies OAuth access tokens (or other credentials) to a provider.
/// Implementations persist and refresh tokens; providers call
/// [accessToken] before each request batch and [invalidate] on a 401.
abstract interface class TokenSource {
  /// A currently valid access token. Throws [AuthException] when the user
  /// must sign in again.
  Future<String> accessToken();

  /// Marks the current token as rejected so the next call refreshes it.
  void invalidate();
}

/// Static facts about what a provider supports, used to adapt the UI.
final class ProviderCapabilities {
  const ProviderCapabilities({
    required this.labels,
    required this.categories,
    required this.serverSearch,
    required this.serverDrafts,
    required this.push,
  });

  /// Messages can be in several mailboxes at once (Gmail labels).
  final bool labels;

  /// The provider sorts the inbox into categories (Gmail tabs).
  final bool categories;
  final bool serverSearch;
  final bool serverDrafts;

  /// The provider can signal new mail in real time.
  final bool push;
}

/// What a sync pass found. The sync engine uses [newMessages] to post
/// notifications, so providers should include only messages that arrived
/// since the previous pass (not messages discovered by a backfill).
final class SyncResult {
  const SyncResult({this.newMessages = const [], this.fullResync = false});

  final List<Message> newMessages;

  /// True when the pass rebuilt the account from scratch.
  final bool fullResync;
}

/// A page of server search results. The provider has already written the
/// matching threads into the store.
final class SearchPage {
  const SearchPage({required this.threadIds, this.nextPageToken});

  final List<String> threadIds;
  final String? nextPageToken;
}

/// A page of older threads loaded on demand when the user scrolls past the
/// locally synced window.
final class LoadMoreResult {
  const LoadMoreResult({required this.loaded, required this.hasMore});

  final int loaded;
  final bool hasMore;
}

/// One mail provider connection for one account.
///
/// Providers own their sync algorithm and write through [SyncStore]; they
/// never talk to the UI. All methods may throw [MailException] subtypes.
abstract interface class MailProvider {
  Account get account;
  ProviderCapabilities get capabilities;

  /// Brings the local store up to date. Performs an initial or full sync
  /// when no cursor is stored, an incremental sync otherwise.
  Future<SyncResult> sync(SyncStore store);

  /// Fetches older threads in [mailboxId] (or all mail when null) beyond
  /// what is stored, writing them to the store. Paging cursors are kept by
  /// the provider in the store via [SyncStore.writeState].
  Future<LoadMoreResult> loadMore(SyncStore store, {String? mailboxId, int pageSize = 50});

  /// Downloads and stores the bodies of [messageIds].
  Future<void> fetchBodies(SyncStore store, List<String> messageIds);

  /// Downloads attachment bytes.
  Future<Uint8List> fetchAttachment(String messageId, AttachmentInfo attachment);

  /// How [operation] changes local state, applied optimistically before the
  /// server round trip. [mailboxes] are the account's current mailboxes.
  LocalMutation localEffect(MailOperation operation, List<Mailbox> mailboxes);

  /// The ids [messageIds] go by now. Providers whose message ids change
  /// (an IMAP move assigns new UIDs) map old ids to current ones, so that
  /// an undo's optimistic update still finds the messages it moved. Others
  /// return [messageIds] unchanged.
  List<String> currentMessageIds(List<String> messageIds);

  /// Applies [operation] on the server. [store] lets folder-based providers
  /// resolve thread ids to messages and record server-assigned changes
  /// (an IMAP move gives the message a new UID).
  Future<void> execute(SyncStore store, MailOperation operation);

  /// Sends a message, returning the provider message id.
  Future<String> send(OutgoingMessage message);

  /// Creates or updates a server draft, returning its draft id.
  Future<String> saveDraft(OutgoingMessage message);
  Future<void> deleteDraft(String draftId);

  /// The draft id of the draft stored as message [messageId], so that a
  /// draft found in a mailbox can be edited further. Null when the message
  /// is not a draft (any more).
  Future<String?> draftIdOf(String messageId);

  /// Server-side search using the provider's query syntax. Matching threads
  /// are written to the store before returning.
  Future<SearchPage> search(SyncStore store, String query, {String? pageToken});

  /// Real-time "something changed" signals. Each event should trigger an
  /// incremental [sync]. The stream may error with [MailException]s; the
  /// engine will resubscribe with backoff.
  Stream<void> watchChanges();

  Future<void> dispose();
}

/// Creates providers for accounts. The app registers one factory per
/// provider kind, which keeps provider packages decoupled from the app.
abstract interface class MailProviderFactory {
  String get kind;
  MailProvider create(Account account, TokenSource tokens);
}
