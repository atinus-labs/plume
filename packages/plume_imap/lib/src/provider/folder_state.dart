import 'dart:convert';

import '../imap/uid_set.dart';

/// What the provider knows about one synced folder, persisted through
/// `SyncStore.writeState` under [keyFor].
///
/// [known] is every UID stored locally for the folder: the initial window,
/// pages loaded later and search hits. New mail is detected by UID ≥
/// [uidNext]; deletions by comparing [known] with the server, but only
/// when the message count says something was removed; flag changes by
/// CONDSTORE or by comparing [unseen]/[flagged] with a fresh FETCH FLAGS.
final class FolderState {
  FolderState({
    required this.uidValidity,
    required this.uidNext,
    this.highestModSeq,
    this.messages = 0,
    this.unseenCount,
    this.known = UidSet.empty,
    this.unseen = UidSet.empty,
    this.flagged = UidSet.empty,
    this.floor = 0,
    this.flagsCheckedAt,
    Map<int, String>? gmailIds,
  }) : gmailIds = gmailIds ?? {};

  static const _prefix = 'imap.folder:';

  /// State key for the folder at [path].
  static String keyFor(String path) => '$_prefix$path';

  int uidValidity;
  int uidNext;

  /// CONDSTORE HIGHESTMODSEQ at the last sync, if the folder has one.
  int? highestModSeq;

  /// The server's message count (EXISTS) at the last sync.
  int messages;
  int? unseenCount;
  UidSet known;

  /// Known UIDs without `\Seen` / with `\Flagged`.
  UidSet unseen;
  UidSet flagged;

  /// Lowest UID of the contiguous synced window; [loadMore] pages below it.
  int floor;
  DateTime? flagsCheckedAt;

  /// Gmail only: UID → X-GM-MSGID (hex) of the known messages, needed to
  /// name messages that vanished.
  final Map<int, String> gmailIds;

  /// Forgets [uids] (deleted or moved away).
  void forget(UidSet uids) {
    if (uids.isEmpty) return;
    known = known.difference(uids);
    unseen = unseen.difference(uids);
    flagged = flagged.difference(uids);
    for (final uid in uids.values) {
      gmailIds.remove(uid);
    }
  }

  /// Records the flags of a stored message.
  void note(int uid, {required bool seen, required bool isFlagged, String? gmailId}) {
    known = known.adding([uid]);
    unseen = seen ? unseen.removing([uid]) : unseen.adding([uid]);
    flagged = isFlagged ? flagged.adding([uid]) : flagged.removing([uid]);
    if (gmailId != null) gmailIds[uid] = gmailId;
  }

  /// Records many messages at once (cheaper than repeated [note]s).
  void noteAll(Iterable<({int uid, bool seen, bool flagged, String? gmailId})> messages) {
    final uids = <int>[];
    final seen = <int>[];
    final notSeen = <int>[];
    final flaggedNow = <int>[];
    final notFlagged = <int>[];
    for (final m in messages) {
      uids.add(m.uid);
      (m.seen ? seen : notSeen).add(m.uid);
      (m.flagged ? flaggedNow : notFlagged).add(m.uid);
      if (m.gmailId != null) gmailIds[m.uid] = m.gmailId!;
    }
    if (uids.isEmpty) return;
    known = known.union(UidSet.of(uids));
    unseen = unseen.difference(UidSet.of(seen)).union(UidSet.of(notSeen));
    flagged = flagged.difference(UidSet.of(notFlagged)).union(UidSet.of(flaggedNow));
  }

  String encode() => jsonEncode({
        'uv': uidValidity,
        'next': uidNext,
        'ms': ?highestModSeq,
        'n': messages,
        'unseenCount': ?unseenCount,
        'known': known.toString(),
        'unseen': unseen.toString(),
        'flagged': flagged.toString(),
        'floor': floor,
        if (flagsCheckedAt != null) 'checked': flagsCheckedAt!.millisecondsSinceEpoch,
        if (gmailIds.isNotEmpty) 'gm': [for (final e in gmailIds.entries) '${e.key}:${e.value}'].join(','),
      });

  /// Null for missing or unreadable state (the folder is then resynced).
  static FolderState? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      final gm = <int, String>{};
      final rawGm = j['gm'];
      if (rawGm is String && rawGm.isNotEmpty) {
        for (final pair in rawGm.split(',')) {
          final colon = pair.indexOf(':');
          final uid = colon < 0 ? null : int.tryParse(pair.substring(0, colon));
          if (uid != null) gm[uid] = pair.substring(colon + 1);
        }
      }
      final checked = j['checked'];
      return FolderState(
        uidValidity: (j['uv']! as num).toInt(),
        uidNext: (j['next']! as num).toInt(),
        highestModSeq: (j['ms'] as num?)?.toInt(),
        messages: (j['n'] as num?)?.toInt() ?? 0,
        unseenCount: (j['unseenCount'] as num?)?.toInt(),
        known: UidSet.parse(j['known'] as String? ?? ''),
        unseen: UidSet.parse(j['unseen'] as String? ?? ''),
        flagged: UidSet.parse(j['flagged'] as String? ?? ''),
        floor: (j['floor'] as num?)?.toInt() ?? 0,
        flagsCheckedAt: checked is num ? DateTime.fromMillisecondsSinceEpoch(checked.toInt()) : null,
        gmailIds: gm,
      );
    } on Object {
      return null;
    }
  }
}
