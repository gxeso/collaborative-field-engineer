import 'package:flutter_test/flutter_test.dart';

import 'package:offline_survey_and_sync_app/data/sync/exponential_backoff_policy.dart';

void main() {
  group('ExponentialBackoffPolicy', () {
    final policy = ExponentialBackoffPolicy();

    test('doubles the delay after each retry', () {
      expect(policy.delayForRetry(1), const Duration(seconds: 2));

      expect(policy.delayForRetry(2), const Duration(seconds: 4));

      expect(policy.delayForRetry(3), const Duration(seconds: 8));

      expect(policy.delayForRetry(4), const Duration(seconds: 16));

      expect(policy.delayForRetry(5), const Duration(seconds: 32));
    });

    test('does not exceed the configured maximum delay', () {
      final limitedPolicy = ExponentialBackoffPolicy(
        baseDelay: Duration(seconds: 2),
        maximumDelay: Duration(seconds: 10),
        maximumRetryCount: 10,
      );

      expect(limitedPolicy.delayForRetry(3), const Duration(seconds: 8));

      expect(limitedPolicy.delayForRetry(4), const Duration(seconds: 10));

      expect(limitedPolicy.delayForRetry(10), const Duration(seconds: 10));
    });

    test('respects a longer server Retry-After value', () {
      final delay = policy.delayForRetry(
        2,
        serverRetryAfter: const Duration(minutes: 1),
      );

      expect(delay, const Duration(minutes: 1));
    });

    test('keeps exponential delay when Retry-After is shorter', () {
      final delay = policy.delayForRetry(
        4,
        serverRetryAfter: const Duration(seconds: 5),
      );

      expect(delay, const Duration(seconds: 16));
    });

    test('calculates the next retry time in UTC', () {
      final currentTime = DateTime.utc(2026, 9, 29, 9);

      final nextRetryAt = policy.nextRetryAt(
        currentTime: currentTime,
        retryCount: 3,
      );

      expect(nextRetryAt, DateTime.utc(2026, 9, 29, 9, 0, 8));

      expect(nextRetryAt.isUtc, isTrue);
    });

    test('allows retries only within the configured limit', () {
      expect(policy.canRetry(0), isFalse);
      expect(policy.canRetry(1), isTrue);
      expect(policy.canRetry(5), isTrue);
      expect(policy.canRetry(6), isFalse);
    });

    test('rejects retry counts below one', () {
      expect(() => policy.delayForRetry(0), throwsArgumentError);
    });
  });
}
