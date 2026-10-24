import '../util/backoff.dart';

/// Gmail per-user quota settings.
///
/// Gmail allows 250 quota units per user per second (moving average) and
/// rejects bursts with 429. Defaults stay a little below that so that other
/// clients of the same project (another Plume window) have headroom.
final class GmailQuota {
  const GmailQuota({
    this.unitsPerSecond = 220,
    this.burstUnits = 250,
    this.maxBatchUnits = 250,
    this.maxBatchSize = 50,
  });

  /// Sustained rate.
  final double unitsPerSecond;

  /// Units that may be spent at once before pacing kicks in.
  final double burstUnits;

  /// Upper bound of units in one batch request. With threads.get at 10
  /// units, this yields batches of 25 threads; messages.get (5) gives 50.
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
