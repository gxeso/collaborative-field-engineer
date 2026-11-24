class ExponentialBackoffPolicy {
  ExponentialBackoffPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maximumDelay = const Duration(minutes: 2),
    this.maximumRetryCount = 5,
  }) : assert(baseDelay > Duration.zero, 'Base delay must be positive.'),
       assert(
         maximumDelay >= baseDelay,
         'Maximum delay cannot be shorter '
         'than the base delay.',
       ),
       assert(maximumRetryCount > 0, 'Maximum retry count must be positive.');

  final Duration baseDelay;
  final Duration maximumDelay;
  final int maximumRetryCount;

  bool canRetry(int nextRetryCount) {
    return nextRetryCount >= 1 && nextRetryCount <= maximumRetryCount;
  }

  Duration delayForRetry(int retryCount, {Duration? serverRetryAfter}) {
    if (retryCount < 1) {
      throw ArgumentError.value(
        retryCount,
        'retryCount',
        'Retry count must be at least one.',
      );
    }

    var delayMilliseconds = baseDelay.inMilliseconds;

    final maximumMilliseconds = maximumDelay.inMilliseconds;

    for (var currentRetry = 1; currentRetry < retryCount; currentRetry++) {
      if (delayMilliseconds >= maximumMilliseconds) {
        delayMilliseconds = maximumMilliseconds;
        break;
      }

      if (delayMilliseconds > maximumMilliseconds ~/ 2) {
        delayMilliseconds = maximumMilliseconds;
      } else {
        delayMilliseconds *= 2;
      }
    }

    final exponentialDelay = Duration(milliseconds: delayMilliseconds);

    if (serverRetryAfter == null || serverRetryAfter <= Duration.zero) {
      return exponentialDelay;
    }

    if (serverRetryAfter > exponentialDelay) {
      return serverRetryAfter;
    }

    return exponentialDelay;
  }

  DateTime nextRetryAt({
    required DateTime currentTime,
    required int retryCount,
    Duration? serverRetryAfter,
  }) {
    final delay = delayForRetry(retryCount, serverRetryAfter: serverRetryAfter);

    return currentTime.toUtc().add(delay);
  }
}
