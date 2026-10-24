import 'package:intl/intl.dart';
import 'package:plume_core/plume_core.dart';

/// Compact list timestamp: time today, weekday this week, date otherwise.
String listDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = date.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateFormat.jm().format(local);
  if (diff < 7) return DateFormat.E().format(local);
  if (local.year == n.year) return DateFormat.MMMd().format(local);
  return DateFormat.yMMMd().format(local);
}

/// Full timestamp for message headers: "Tue, 14 Oct, 10:42 (3 hours ago)".
String fullDate(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = date.toLocal();
  final base = local.year == n.year
      ? DateFormat('EEE, d MMM, ').add_jm().format(local)
      : DateFormat('EEE, d MMM y, ').add_jm().format(local);
  final ago = relative(local, now: n);
  return ago == null ? base : '$base ($ago)';
}

String? relative(DateTime date, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(date);
  if (d.isNegative) return null;
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
  if (d.inDays < 7) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  return null;
}

/// Section label for grouping a list by recency.
String dateGroup(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = date.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(weekStart)) return 'This week';
  if (!day.isBefore(weekStart.subtract(const Duration(days: 7)))) return 'Last week';
  if (local.year == n.year && local.month == n.month) return 'Earlier this month';
  if (local.year == n.year) return DateFormat.MMMM().format(local);
  return DateFormat.yMMMM().format(local);
}

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// "Maya, me, Arjun (3)" style participant label.
String participantsLabel(List<Address> participants, String myEmail, {int messageCount = 1}) {
  final names = <String>[];
  for (final p in participants) {
    final isMe = p.email.toLowerCase() == myEmail.toLowerCase();
    final name = isMe ? 'me' : (participants.length > 1 ? p.shortName : p.displayName);
    if (!names.contains(name)) names.add(name);
  }
  if (names.isEmpty) return '(no sender)';
  var label = names.length > 3 ? '${names.first} .. ${names.sublist(names.length - 2).join(', ')}' : names.join(', ');
  if (messageCount > 1) label = '$label  $messageCount';
  return label;
}
