import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plume_core/plume_core.dart';

import '../api/gmail_types.dart';

/// Well-known Gmail system label ids.
abstract final class GmailLabels {
  static const inbox = 'INBOX';
  static const sent = 'SENT';
  static const draft = 'DRAFT';
  static const trash = 'TRASH';
  static const spam = 'SPAM';
  static const important = 'IMPORTANT';
  static const starred = 'STARRED';
  static const unread = 'UNREAD';
  static const chat = 'CHAT';
  static const personal = 'CATEGORY_PERSONAL';
  static const social = 'CATEGORY_SOCIAL';
  static const promotions = 'CATEGORY_PROMOTIONS';
  static const updates = 'CATEGORY_UPDATES';
  static const forums = 'CATEGORY_FORUMS';

  /// Labels that are keywords in Plume's model rather than mailboxes.
  static const keywordLabels = {unread, starred};
}

typedef _SystemLabel = ({String name, MailboxRole? role, MailCategory? category, bool hidden, int order});

const Map<String, _SystemLabel> _systemLabels = {
  GmailLabels.inbox: (name: 'Inbox', role: MailboxRole.inbox, category: null, hidden: false, order: 0),
  GmailLabels.personal: (
    name: 'Primary',
    role: MailboxRole.category,
    category: MailCategory.primary,
    hidden: false,
    order: 1
  ),
  GmailLabels.social: (
    name: 'Social',
    role: MailboxRole.category,
    category: MailCategory.social,
    hidden: false,
    order: 2
  ),
  GmailLabels.promotions: (
    name: 'Promotions',
    role: MailboxRole.category,
    category: MailCategory.promotions,
    hidden: false,
    order: 3
  ),
  GmailLabels.updates: (
    name: 'Updates',
    role: MailboxRole.category,
    category: MailCategory.updates,
    hidden: false,
    order: 4
  ),
  GmailLabels.forums: (
    name: 'Forums',
    role: MailboxRole.category,
    category: MailCategory.forums,
    hidden: false,
    order: 5
  ),
  GmailLabels.starred: (name: 'Starred', role: null, category: null, hidden: true, order: 6),
  GmailLabels.important: (name: 'Important', role: MailboxRole.important, category: null, hidden: false, order: 7),
  GmailLabels.sent: (name: 'Sent', role: MailboxRole.sent, category: null, hidden: false, order: 8),
  GmailLabels.draft: (name: 'Drafts', role: MailboxRole.drafts, category: null, hidden: false, order: 9),
  GmailLabels.spam: (name: 'Spam', role: MailboxRole.junk, category: null, hidden: false, order: 10),
  GmailLabels.trash: (name: 'Trash', role: MailboxRole.trash, category: null, hidden: false, order: 11),
  GmailLabels.unread: (name: 'Unread', role: null, category: null, hidden: true, order: 12),
  GmailLabels.chat: (name: 'Chats', role: null, category: null, hidden: true, order: 13),
};

/// Sort orders: system labels 0-99, user labels from 100 in name order.
const int _unknownSystemOrder = 50;
const int _userOrderBase = 100;

/// Maps Gmail labels onto Plume [Mailbox]es.
abstract final class GmailLabelMapper {
  /// Maps the account's labels. Counts come from labels.get; labels lacking
  /// them get zero counts.
  static List<Mailbox> map(String accountId, List<GmailLabel> labels) {
    final byName = <String, GmailLabel>{
      for (final l in labels)
        if (!l.isSystem) l.name: l,
    };
    final users = labels.where((l) => !l.isSystem && !_systemLabels.containsKey(l.id)).toList()
      ..sort((a, b) => _compareLabelPaths(a.name, b.name));
    final userOrder = {for (var i = 0; i < users.length; i++) users[i].id: _userOrderBase + i};

    final result = <Mailbox>[];
    for (final label in labels) {
      final system = _systemLabels[label.id];
      if (system != null) {
        result.add(Mailbox(
          accountId: accountId,
          id: label.id,
          name: system.name,
          role: system.role,
          category: system.category,
          kind: MailboxKind.system,
          color: parseLabelColor(label.backgroundColor),
          unreadThreads: label.threadsUnread ?? 0,
          totalThreads: label.threadsTotal ?? 0,
          sortOrder: system.order,
          hidden: system.hidden,
        ));
      } else if (label.isSystem) {
        // Unknown system labels (e.g. coloured "superstars") are internal.
        result.add(Mailbox(
          accountId: accountId,
          id: label.id,
          name: label.name,
          kind: MailboxKind.system,
          unreadThreads: label.threadsUnread ?? 0,
          totalThreads: label.threadsTotal ?? 0,
          sortOrder: _unknownSystemOrder,
          hidden: true,
        ));
      } else {
        final nesting = _nesting(label.name, byName);
        result.add(Mailbox(
          accountId: accountId,
          id: label.id,
          name: nesting.leaf,
          kind: MailboxKind.user,
          parentId: nesting.parentId,
          color: parseLabelColor(label.backgroundColor),
          unreadThreads: label.threadsUnread ?? 0,
          totalThreads: label.threadsTotal ?? 0,
          sortOrder: userOrder[label.id] ?? _userOrderBase,
          hidden: label.labelListVisibility == 'labelHide',
        ));
      }
    }
    result.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return result;
  }

  /// `#16a766` → `0xFF16A766`.
  static int? parseLabelColor(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6) return null;
    final rgb = int.tryParse(h, radix: 16);
    return rgb == null ? null : 0xFF000000 | rgb;
  }

  /// For `a/b/c`, the parent is the nearest existing ancestor label (`a/b`,
  /// else `a`); the name is the remainder of the path after that parent.
  static ({String? parentId, String leaf}) _nesting(String name, Map<String, GmailLabel> byName) {
    if (!name.contains('/')) return (parentId: null, leaf: name);
    var cut = name.lastIndexOf('/');
    while (cut > 0) {
      final parent = byName[name.substring(0, cut)];
      if (parent != null) return (parentId: parent.id, leaf: name.substring(cut + 1));
      cut = name.lastIndexOf('/', cut - 1);
    }
    return (parentId: null, leaf: name);
  }

  /// Orders label paths segment by segment, case-insensitively, so that
  /// children sort directly after their parent.
  static int _compareLabelPaths(String a, String b) {
    final sa = a.toLowerCase().split('/');
    final sb = b.toLowerCase().split('/');
    for (var i = 0; i < sa.length && i < sb.length; i++) {
      final c = sa[i].compareTo(sb[i]);
      if (c != 0) return c;
    }
    final c = sa.length.compareTo(sb.length);
    return c != 0 ? c : a.compareTo(b);
  }

  /// A signature of the label set (ids, names, colours, visibility), used
  /// to detect label changes, which Gmail history does not report.
  static String signature(List<GmailLabel> labels) {
    final parts = [
      for (final l in labels) '${l.id}\u0001${l.name}\u0001${l.backgroundColor}\u0001${l.labelListVisibility}',
    ]..sort();
    return sha256.convert(utf8.encode(parts.join('\u0002'))).toString().substring(0, 32);
  }
}
