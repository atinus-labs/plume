import 'dart:async';
import 'dart:math';

/// Waits for a duration. Injected so tests can run retry loops instantly.
typedef Sleep = Future<void> Function(Duration duration);

Future<void> defaultSleep(Duration d) => Future<void>.delayed(d);

/// Exponential backoff with "equal jitter": half of each delay is fixed and
/// half is random, which spreads retries without ever retrying instantly.
final class RetryBackoff {
  const RetryBackoff({
    this.initial = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 32),
    this.multiplier = 2.0,
  });

  final Duration initial;
  final Duration max;
  final double multiplier;

  /// Delay before retry number [attempt] (0-based).
  Duration delay(int attempt, Random random) {
    final base = initial.inMicroseconds * pow(multiplier, attempt.clamp(0, 30));
    final capped = min(base.toDouble(), max.inMicroseconds.toDouble());
    final half = capped / 2;
    return Duration(microseconds: (half + random.nextDouble() * half).round());
  }
}
