import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plume_core/plume_core.dart';

import '../imap/imap_client.dart';

/// How a server folder takes part in sync.
enum FolderSync {
  /// Not synced: containers (\Noselect), virtual folders (\All, \Flagged)
  /// and, in Gmail mode, label folders (their mail comes from All Mail).
  none,

  /// Synced every pass.
  always,
}

/// A server folder and the mailbox it maps to.
final class ImapFolder {
  const ImapFolder({
    required this.path,
    required this.mailboxId,
    required this.role,
    required this.delimiter,
    required this.sync,
    this.status,
    this.gmailAll = false,
  });

  /// Decoded full name, as used in commands (`INBOX` normalized).
  final String path;

  /// The [Mailbox.id] of this folder's messages.
  final String mailboxId;
  final MailboxRole? role;
  final String? delimiter;
  final FolderSync sync;
  final ImapMailboxStatus? status;

  /// Gmail's All Mail folder (\All).
  final bool gmailAll;

  bool get isInbox => role == MailboxRole.inbox;

  @override
  String toString() => 'ImapFolder($path → $mailboxId ${role?.name ?? ''})';
}

/// Gmail categories as Plume mailboxes, with the ids, names and order the
/// Gmail API provider uses so the inbox tabs behave the same.
const gmailCategories = <(String id, MailCategory category, String name, String query, int order)>[
  ('CATEGORY_PERSONAL', MailCategory.primary, 'Primary', 'category:primary', 1),
  ('CATEGORY_SOCIAL', MailCategory.social, 'Social', 'category:social', 2),
  ('CATEGORY_PROMOTIONS', MailCategory.promotions, 'Promotions', 'category:promotions', 3),
  ('CATEGORY_UPDATES', MailCategory.updates, 'Updates', 'category:updates', 4),
  ('CATEGORY_FORUMS', MailCategory.forums, 'Forums', 'category:forums', 5),
];

/// Gmail-mode ids of system mailboxes. They do not depend on the
/// account's language (folder names such as `[Gmail]/Sent Mail` or
/// `[Google Mail]/Gesendet` do), and cannot clash with user labels, whose
/// names never start with a backslash.
abstract final class GmailBoxes {
  static const inbox = 'INBOX';
  static const sent = r'\Sent';
  static const drafts = r'\Drafts';
  static const important = r'\Important';
  static const starred = r'\Starred';
  static const trash = r'\Trash';
  static const junk = r'\Junk';
  static const all = r'\All';
}

/// The account's folders and mailboxes as of the last LIST.
final class FolderLayout {
  FolderLayout(this.folders, this.mailboxes, {required this.gmail, this.namespacePrefix = ''})
      : _byPath = {for (final f in folders) f.path: f},
        _byMailbox = {for (final f in folders) f.mailboxId: f};

  final List<ImapFolder> folders;
  final List<Mailbox> mailboxes;
  final bool gmail;

  /// Personal namespace prefix, e.g. `INBOX.` on Courier-style servers.
  final String namespacePrefix;
  final Map<String, ImapFolder> _byPath;
  final Map<String, ImapFolder> _byMailbox;

  ImapFolder? byPath(String path) => _byPath[path];
  ImapFolder? byMailboxId(String id) => _byMailbox[id];
  ImapFolder? byRole(MailboxRole role) => folders.where((f) => f.role == role).firstOrNull;

  ImapFolder? get gmailAllMail => folders.where((f) => f.gmailAll).firstOrNull;

  /// Folders synced each pass, most important first.
  List<ImapFolder> get synced {
    int rank(ImapFolder f) => switch (f.role) {
          MailboxRole.inbox => 0,
          _ when f.gmailAll => 1,
          MailboxRole.sent => 2,
          MailboxRole.drafts => 3,
          MailboxRole.archive => 4,
          null => 5,
          MailboxRole.junk => 7,
          MailboxRole.trash => 8,
          _ => 6,
        };
    return [for (final f in folders) if (f.sync == FolderSync.always) f]..sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.path.compareTo(b.path);
      });
  }

  /// Detects changes in the folder set (not counts), so mailboxes are only
  /// rewritten when something structural changed.
  String get signature {
    final parts = [
      for (final m in mailboxes) '${m.id}\u0001${m.name}\u0001${m.role?.name}\u0001${m.parentId}\u0001${m.hidden}',
      for (final f in folders) '${f.path}\u0001${f.mailboxId}\u0001${f.sync.name}',
    ]..sort();
    return sha256.convert(utf8.encode(parts.join('\u0002'))).toString().substring(0, 32);
  }

  /// Message counts by mailbox id from LIST-STATUS / STATUS data. IMAP
  /// counts messages, not conversations; the numbers are close enough for
  /// badges.
  Map<String, ({int unread, int total})> get counts => {
        for (final f in folders)
          if (f.status case final s? when s.messages != null) f.mailboxId: (unread: s.unseen ?? 0, total: s.messages!),
      };
}

/// Folder names that identify a role on servers without SPECIAL-USE,
/// lower-cased, in common languages.
const _roleNames = <MailboxRole, Set<String>>{
  MailboxRole.sent: {
    'sent', 'sent items', 'sent mail', 'sent messages', 'sent-mail', 'outbox sent', 'gesendet', 'gesendete objekte',
    'gesendete elemente', 'gesendete nachrichten', 'envoyés', 'envoyes', 'éléments envoyés', 'messages envoyés',
    'enviados', 'elementos enviados', 'enviadas', 'mensajes enviados', 'inviata', 'posta inviata', 'inviati',
    'verzonden', 'verzonden items', 'skickat', 'skickade objekt', 'sendt', 'sendte elementer', 'sendte',
    'lähetetyt', 'wysłane', 'elementy wysłane', 'odeslané', 'odoslané', 'elküldött', 'trimise', 'gönderilenler',
    'отправленные', 'надіслані', '送信済み', '送信済みアイテム', '已发送', '已傳送', '寄件備份', '보낸편지함',
  },
  MailboxRole.drafts: {
    'drafts', 'draft', 'entwürfe', 'entwurf', 'brouillons', 'brouillon', 'borradores', 'bozze', 'concepten',
    'concepts', 'utkast', 'kladder', 'luonnokset', 'szkice', 'koncepty', 'piszkozatok', 'ciorne', 'taslaklar',
    'черновики', 'чернетки', '下書き', '草稿', '草稿箱', '임시보관함',
  },
  MailboxRole.trash: {
    'trash', 'deleted', 'deleted items', 'deleted messages', 'bin', 'papierkorb', 'gelöschte objekte',
    'gelöschte elemente', 'corbeille', 'éléments supprimés', 'papelera', 'elementos eliminados', 'cestino',
    'prullenbak', 'verwijderde items', 'papperskorgen', 'borttagna objekt', 'papirkurv', 'slettede elementer',
    'roskakori', 'kosz', 'koš', 'kuka', 'lomtár', 'coș de gunoi', 'çöp kutusu', 'корзина', 'удаленные', 'кошик',
    'ゴミ箱', '已删除', '垃圾桶', '已刪除郵件', '휴지통',
  },
  MailboxRole.junk: {
    'junk', 'spam', 'junk e-mail', 'junk email', 'junk mail', 'bulk mail', 'spamverdacht', 'junk-e-mail',
    'courrier indésirable', 'pourriel', 'indésirables', 'correo no deseado', 'posta indesiderata',
    'ongewenste e-mail', 'skräppost', 'uønsket e-post', 'roskaposti', 'wiadomości-śmieci', 'nevyžádaná pošta',
    'levélszemét', 'спам', 'нежелательная почта', '迷惑メール', '垃圾邮件', '垃圾郵件', '스팸편지함',
  },
  MailboxRole.archive: {
    'archive', 'archives', 'archiv', 'archivo', 'archivio', 'archief', 'arkiv', 'arkisto', 'archiwum',
    'archivum', 'arhivă', 'arşiv', 'архив', 'архів', 'アーカイブ', '存档', '归档', '封存', '보관함',
  },
};

const _specialUse = <String, MailboxRole>{
  r'\sent': MailboxRole.sent,
  r'\drafts': MailboxRole.drafts,
  r'\trash': MailboxRole.trash,
  r'\junk': MailboxRole.junk,
  r'\archive': MailboxRole.archive,
  r'\important': MailboxRole.important,
};

const _roleNamesDisplay = <MailboxRole, String>{
  MailboxRole.inbox: 'Inbox',
  MailboxRole.sent: 'Sent',
  MailboxRole.drafts: 'Drafts',
  MailboxRole.trash: 'Trash',
  MailboxRole.junk: 'Junk',
  MailboxRole.archive: 'Archive',
  MailboxRole.important: 'Important',
};

const _roleOrder = <MailboxRole, int>{
  MailboxRole.inbox: 0,
  MailboxRole.important: 7,
  MailboxRole.archive: 8,
  MailboxRole.sent: 9,
  MailboxRole.drafts: 10,
  MailboxRole.junk: 11,
  MailboxRole.trash: 12,
};

String _leaf(String path, String? delimiter) {
  if (delimiter == null || delimiter.isEmpty) return path;
  final i = path.lastIndexOf(delimiter);
  return i < 0 ? path : path.substring(i + delimiter.length);
}

/// Maps a generic server's LIST onto folders and mailboxes. Roles come from
/// SPECIAL-USE attributes, else from well-known (localized) names; INBOX is
/// always the inbox. Each role goes to one folder.
FolderLayout mapGenericFolders(String accountId, List<ImapMailboxInfo> list, {String namespacePrefix = ''}) {
  final infos = [for (final i in list) if (!i.has(r'\nonexistent')) i];
  final roles = <String, MailboxRole>{};
  final taken = <MailboxRole>{MailboxRole.inbox};
  // SPECIAL-USE first.
  for (final i in infos) {
    if (i.name == 'INBOX') continue;
    for (final a in i.attributes) {
      final role = _specialUse[a];
      if (role != null && !taken.contains(role) && i.isSelectable) {
        roles[i.name] = role;
        taken.add(role);
        break;
      }
    }
  }
  // Then names: top-level folders (or direct children of the namespace or
  // INBOX) only, so that "Projects/Archive" is not mistaken for the archive.
  for (final i in infos) {
    if (i.name == 'INBOX' || roles.containsKey(i.name) || !i.isSelectable) continue;
    var relative = i.name;
    if (namespacePrefix.isNotEmpty && relative.startsWith(namespacePrefix)) {
      relative = relative.substring(namespacePrefix.length);
    } else if (i.delimiter != null && relative.toUpperCase().startsWith('INBOX${i.delimiter}')) {
      relative = relative.substring(5 + i.delimiter!.length);
    }
    if (i.delimiter != null && i.delimiter!.isNotEmpty && relative.contains(i.delimiter!)) continue;
    final lower = relative.toLowerCase().trim();
    for (final e in _roleNames.entries) {
      if (!taken.contains(e.key) && e.value.contains(lower)) {
        roles[i.name] = e.key;
        taken.add(e.key);
        break;
      }
    }
  }

  final folders = <ImapFolder>[];
  final mailboxes = <Mailbox>[];
  final paths = {for (final i in infos) i.name};
  final users = [for (final i in infos) if (i.name != 'INBOX' && !roles.containsKey(i.name)) i.name]..sort(_comparePaths);
  final userOrder = {for (var k = 0; k < users.length; k++) users[k]: 100 + k};
  for (final i in infos) {
    final virtual = i.has(r'\all') || i.has(r'\flagged');
    final role = i.name == 'INBOX' ? MailboxRole.inbox : roles[i.name];
    final selectable = i.isSelectable && !virtual;
    folders.add(ImapFolder(
      path: i.name,
      mailboxId: i.name,
      role: role,
      delimiter: i.delimiter,
      sync: selectable ? FolderSync.always : FolderSync.none,
      status: i.status,
    ));
    mailboxes.add(Mailbox(
      accountId: accountId,
      id: i.name,
      name: role == null ? _leaf(i.name, i.delimiter) : _roleNamesDisplay[role]!,
      role: role,
      kind: role == null ? MailboxKind.user : MailboxKind.system,
      parentId: role == null ? _parentOf(i.name, i.delimiter, paths, namespacePrefix) : null,
      unreadThreads: i.status?.unseen ?? 0,
      totalThreads: i.status?.messages ?? 0,
      sortOrder: role == null ? (userOrder[i.name] ?? 100) : _roleOrder[role]!,
      // Virtual folders duplicate other folders' mail.
      hidden: virtual,
    ));
  }
  return FolderLayout(folders, _sorted(mailboxes), gmail: false, namespacePrefix: namespacePrefix);
}

/// Nearest listed ancestor. Folders right below a namespace prefix such as
/// `INBOX.` are top-level for the user.
String? _parentOf(String path, String? delimiter, Set<String> paths, String namespacePrefix) {
  if (delimiter == null || delimiter.isEmpty) return null;
  var cut = path.lastIndexOf(delimiter);
  while (cut > 0) {
    final parent = path.substring(0, cut);
    if (namespacePrefix.isNotEmpty && '$parent$delimiter' == namespacePrefix) return null;
    if (paths.contains(parent)) return parent;
    cut = path.lastIndexOf(delimiter, cut - 1);
  }
  return null;
}

int _comparePaths(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

List<Mailbox> _sorted(List<Mailbox> list) => list
  ..sort((a, b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

/// Maps Gmail's LIST: system folders are found by SPECIAL-USE flags (their
/// names are localized), user labels become mailboxes named by their
/// label, and the inbox categories are added. Only All Mail, Trash and
/// Spam are synced; everything else is a view of All Mail.
FolderLayout mapGmailFolders(String accountId, List<ImapMailboxInfo> list) {
  final folders = <ImapFolder>[];
  final mailboxes = <Mailbox>[];
  const system = <String, (String id, MailboxRole? role, bool hidden)>{
    r'\all': (GmailBoxes.all, null, true),
    r'\sent': (GmailBoxes.sent, MailboxRole.sent, false),
    r'\drafts': (GmailBoxes.drafts, MailboxRole.drafts, false),
    r'\important': (GmailBoxes.important, MailboxRole.important, false),
    r'\flagged': (GmailBoxes.starred, null, true),
    r'\trash': (GmailBoxes.trash, MailboxRole.trash, false),
    r'\junk': (GmailBoxes.junk, MailboxRole.junk, false),
  };
  const order = <String, int>{
    GmailBoxes.starred: 6,
    GmailBoxes.important: 7,
    GmailBoxes.sent: 8,
    GmailBoxes.drafts: 9,
    GmailBoxes.junk: 10,
    GmailBoxes.trash: 11,
    GmailBoxes.all: 12,
  };
  const names = <String, String>{
    GmailBoxes.all: 'All Mail',
    GmailBoxes.sent: 'Sent',
    GmailBoxes.drafts: 'Drafts',
    GmailBoxes.important: 'Important',
    GmailBoxes.starred: 'Starred',
    GmailBoxes.trash: 'Trash',
    GmailBoxes.junk: 'Spam',
  };
  final labels = <ImapMailboxInfo>[];
  final seenSystem = <String>{};
  for (final i in list) {
    if (i.name == 'INBOX') {
      folders.add(ImapFolder(
        path: 'INBOX',
        mailboxId: GmailBoxes.inbox,
        role: MailboxRole.inbox,
        delimiter: i.delimiter,
        sync: FolderSync.none,
        status: i.status,
      ));
      mailboxes.add(Mailbox(
        accountId: accountId,
        id: GmailBoxes.inbox,
        name: 'Inbox',
        role: MailboxRole.inbox,
        kind: MailboxKind.system,
        unreadThreads: i.status?.unseen ?? 0,
        totalThreads: i.status?.messages ?? 0,
      ));
      continue;
    }
    final match = system.entries.where((e) => i.has(e.key)).firstOrNull;
    if (match != null && seenSystem.add(match.value.$1)) {
      final (id, role, hidden) = match.value;
      final synced = id == GmailBoxes.all || id == GmailBoxes.trash || id == GmailBoxes.junk;
      folders.add(ImapFolder(
        path: i.name,
        mailboxId: id,
        role: role,
        delimiter: i.delimiter,
        sync: synced ? FolderSync.always : FolderSync.none,
        status: i.status,
        gmailAll: id == GmailBoxes.all,
      ));
      mailboxes.add(Mailbox(
        accountId: accountId,
        id: id,
        name: names[id]!,
        role: role,
        kind: MailboxKind.system,
        unreadThreads: i.status?.unseen ?? 0,
        totalThreads: i.status?.messages ?? 0,
        sortOrder: order[id]!,
        hidden: hidden,
      ));
      continue;
    }
    if (!i.isSelectable || match != null) continue; // [Gmail] container
    labels.add(i);
  }
  for (final (id, category, name, _, sortOrder) in gmailCategories) {
    mailboxes.add(Mailbox(
      accountId: accountId,
      id: id,
      name: name,
      role: MailboxRole.category,
      category: category,
      kind: MailboxKind.system,
      sortOrder: sortOrder,
    ));
  }
  final labelNames = {for (final l in labels) l.name};
  final sortedLabels = [for (final l in labels) l.name]..sort(_compareLabelPaths);
  final labelOrder = {for (var k = 0; k < sortedLabels.length; k++) sortedLabels[k]: 100 + k};
  for (final l in labels) {
    folders.add(ImapFolder(path: l.name, mailboxId: l.name, role: null, delimiter: l.delimiter, sync: FolderSync.none, status: l.status));
    mailboxes.add(Mailbox(
      accountId: accountId,
      id: l.name,
      name: _leaf(l.name, l.delimiter ?? '/'),
      kind: MailboxKind.user,
      parentId: _parentOf(l.name, l.delimiter ?? '/', labelNames, ''),
      unreadThreads: l.status?.unseen ?? 0,
      totalThreads: l.status?.messages ?? 0,
      sortOrder: labelOrder[l.name]!,
    ));
  }
  return FolderLayout(folders, _sorted(mailboxes), gmail: true);
}

/// Orders label paths segment by segment so children follow their parent.
int _compareLabelPaths(String a, String b) {
  final sa = a.toLowerCase().split('/');
  final sb = b.toLowerCase().split('/');
  for (var i = 0; i < sa.length && i < sb.length; i++) {
    final c = sa[i].compareTo(sb[i]);
    if (c != 0) return c;
  }
  final c = sa.length.compareTo(sb.length);
  return c != 0 ? c : a.compareTo(b);
}

/// Gmail X-GM-LABELS → mailbox ids (and whether `\Starred` was present).
({Set<String> mailboxes, bool starred, bool draft}) mapGmailLabels(Iterable<String> labels, FolderLayout layout) {
  final out = <String>{};
  var starred = false;
  var draft = false;
  for (final raw in labels) {
    final l = raw.toLowerCase();
    switch (l) {
      case r'\inbox':
        out.add(GmailBoxes.inbox);
      case r'\sent':
        out.add(GmailBoxes.sent);
      case r'\draft' || r'\drafts':
        out.add(GmailBoxes.drafts);
        draft = true;
      case r'\important':
        out.add(GmailBoxes.important);
      case r'\starred':
        starred = true;
      case r'\trash' || r'\spam' || r'\junk' || r'\all' || r'\allmail' || r'\chats' || r'\muted':
        break; // Folder membership comes from the folder synced.
      default:
        if (raw.startsWith(r'\')) break;
        // Older servers report "Important" without the backslash.
        if (l == 'important' && layout.byMailboxId(raw) == null) {
          out.add(GmailBoxes.important);
        } else {
          out.add(raw);
        }
    }
  }
  return (mailboxes: out, starred: starred, draft: draft);
}

/// Mailbox ids → X-GM-LABELS values for STORE. Trash, Spam, categories and
/// unknown system ids have no label form (they are moves or read-only).
String? gmailLabelFor(String mailboxId) => switch (mailboxId) {
      GmailBoxes.inbox => r'\Inbox',
      GmailBoxes.sent => r'\Sent',
      GmailBoxes.drafts => r'\Draft',
      GmailBoxes.important => r'\Important',
      GmailBoxes.starred => r'\Starred',
      GmailBoxes.trash || GmailBoxes.junk || GmailBoxes.all => null,
      _ when mailboxId.startsWith('CATEGORY_') => null,
      _ => mailboxId,
    };
