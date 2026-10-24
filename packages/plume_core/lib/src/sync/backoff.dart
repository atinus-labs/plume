import 'dart:math';

/// Exponential backoff with full jitter, capped.
final class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 2),
    this.max = const Duration(minutes: 5),
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final Random _random;
  int _attempt = 0;

  int get attempt => _attempt;

  /// The delay before the next attempt; grows with each call.
  Duration next() {
    final cap = min(max.inMilliseconds, initial.inMilliseconds * pow(2, _attempt).toInt());
    _attempt = min(_attempt + 1, 30);
    // Never below half the step so retries are not hammered after a jitter of 0.
    final ms = cap ~/ 2 + _random.nextInt(max0(cap ~/ 2) + 1);
    return Duration(milliseconds: ms);
  }

  void reset() => _attempt = 0;

  /// The delay for a given attempt number without mutating state.
  static Duration forAttempt(int attempt, {Duration initial = const Duration(seconds: 5), Duration max = const Duration(minutes: 30)}) {
    final ms = min(max.inMilliseconds, initial.inMilliseconds * pow(2, min(attempt, 20)).toInt());
    return Duration(milliseconds: ms);
  }
}

int max0(int v) => v < 0 ? 0 : v;
