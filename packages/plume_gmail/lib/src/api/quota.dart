import '../util/backoff.dart';

/// Gmail per-user quota settings.
///
/// Gmail allows 6,000 quota units per user per minute (the limit for
/// projects created since May 2026; older projects may have more) and
/// rejects the excess with 429. Pacing lets at most burst + 60 s × rate =
/// 5,600 units through in any minute, leaving headroom for other clients
/// of the same project (another Plume window).
final class GmailQuota {
  const GmailQuota({
    this.unitsPerSecond = 80,
    this.burstUnits = 800,
    this.maxBatchUnits = 800,
    this.maxBatchSize = 50,
  });

  /// Sustained rate.
  final double unitsPerSecond;

  /// Units that may be spent at once before pacing kicks in.
  final double burstUnits;

  /// Upper bound of units in one batch request. With threads.get at 40
  /// units, this yields batches of 20 threads; messages.get (20) gives 40.
  final int maxBatchUnits;

  /// Gmail rejects batches above 100 and recommends at most 50.
  final int maxBatchSize;

  /// Disables pacing, for tests.
  static const unlimited = GmailQuota(unitsPerSecond: 1e9, burstUnits: 1e9, maxBatchUnits: 1 << 30);
}

/// Paces quota spending with the generic cell rate algorithm: each call
/// pushes a "theoretical arrival time" forward by its cost; a call waits
/// when that time runs more than the burst window ahead of now.
final class QuotaLimiter {
  QuotaLimiter(this.quota, {DateTime Function()? clock, Sleep? sleep})
      : _clock = clock ?? DateTime.now,
        _sleep = sleep ?? defaultSleep;

  final GmailQuota quota;
  final DateTime Function() _clock;
  final Sleep _sleep;
  DateTime? _tat;

  Future<void> acquire(int units) async {
    if (units <= 0) return;
    final now = _clock();
    final tat = (_tat == null || _tat!.isBefore(now)) ? now : _tat!;
    final cost = Duration(microseconds: (units * 1e6 / quota.unitsPerSecond).round());
    final window = Duration(microseconds: (quota.burstUnits * 1e6 / quota.unitsPerSecond).round());
    final startAt = tat.add(cost).subtract(window);
    _tat = tat.add(cost);
    if (startAt.isAfter(now)) await _sleep(startAt.difference(now));
  }
}
