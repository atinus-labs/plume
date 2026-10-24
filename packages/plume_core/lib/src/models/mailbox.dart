/// Well-known mailbox purposes, modelled after JMAP (RFC 8621) roles.
///
/// Providers map their native folders/labels onto these so the UI and the
/// unified views can work across accounts without knowing provider details.
enum MailboxRole {
  inbox,
  sent,
  drafts,
  trash,
  junk,

  /// Gmail "Important" and similar priority markers.
  important,

  /// Provider categories such as Gmail's Promotions/Social tabs. The specific
  /// category is identified by [Mailbox.category].
  category,

  /// A dedicated archive folder (IMAP). Gmail has no archive mailbox; archived
  /// mail simply lacks the inbox label.
  archive,

  /// Server-side outbox / scheduled folders.
  scheduled,
}

/// Inbox categories that some providers (Gmail) sort mail into.
enum MailCategory { primary, social, promotions, updates, forums }

/// Whether a mailbox is created by the provider or by the user.
enum MailboxKind { system, user }

/// A folder or label. A message may belong to several mailboxes (labels) or
/// exactly one (folders); the data model treats both as a set membership.
final class Mailbox {
  const Mailbox({
    required this.accountId,
    required this.id,
    required this.name,
    this.role,
    this.category,
    this.kind = MailboxKind.user,
    this.parentId,
    this.color,
    this.unreadThreads = 0,
    this.totalThreads = 0,
    this.sortOrder = 0,
    this.hidden = false,
  });

  final String accountId;

  /// Provider identifier (Gmail label id, IMAP path...).
  final String id;

  /// Display name. For nested labels this is the leaf segment.
  final String name;
  final MailboxRole? role;
  final MailCategory? category;
  final MailboxKind kind;
  final String? parentId;

  /// Optional ARGB label colour supplied by the provider.
  final int? color;
  final int unreadThreads;
  final int totalThreads;
  final int sortOrder;

  /// Provider-internal mailboxes that should not be listed (e.g. Gmail's
  /// UNREAD/STARRED pseudo-labels, which are mapped to keywords instead).
  final bool hidden;

  Mailbox copyWith({int? unreadThreads, int? totalThreads, String? name, int? color}) => Mailbox(
        accountId: accountId,
        id: id,
        name: name ?? this.name,
        role: role,
        category: category,
        kind: kind,
        parentId: parentId,
        color: color ?? this.color,
        unreadThreads: unreadThreads ?? this.unreadThreads,
        totalThreads: totalThreads ?? this.totalThreads,
        sortOrder: sortOrder,
        hidden: hidden,
      );

  @override
  bool operator ==(Object other) =>
      other is Mailbox &&
      other.accountId == accountId &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.category == category &&
      other.kind == kind &&
      other.parentId == parentId &&
      other.color == color &&
      other.unreadThreads == unreadThreads &&
      other.totalThreads == totalThreads &&
      other.sortOrder == sortOrder &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(accountId, id, name, role, category, kind, parentId, color,
      unreadThreads, totalThreads, sortOrder, hidden);

  @override
  String toString() => 'Mailbox($accountId/$id "$name" ${role?.name ?? ''})';
}
