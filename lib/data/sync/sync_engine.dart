import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../models/sync_operation.dart';
import '../remote/sync_remote_data_source.dart';
import '../remote/sync_remote_exception.dart';
import 'entity_sync_status_updater.dart';
import 'exponential_backoff_policy.dart';
import 'sync_queue.dart';

class SyncBatchResult {
  const SyncBatchResult({
    required this.processed,
    required this.succeeded,
    required this.retried,
    required this.conflicted,
    required this.failed,
  });

  final int processed;
  final int succeeded;
  final int retried;
  final int conflicted;
  final int failed;

  @override
  String toString() {
    return 'SyncBatchResult('
        'processed: $processed, '
        'succeeded: $succeeded, '
        'retried: $retried, '
        'conflicted: $conflicted, '
        'failed: $failed'
        ')';
  }
}

class SyncEngine {
  SyncEngine({
    required SyncQueue syncQueue,
    required SyncRemoteDataSource remoteDataSource,
    required EntitySyncStatusUpdater entityStatusUpdater,
    ExponentialBackoffPolicy? retryPolicy,
    DateTime Function()? clock,
  }) : _syncQueue = syncQueue,
       _remoteDataSource = remoteDataSource,
       _entityStatusUpdater = entityStatusUpdater,
       _retryPolicy = retryPolicy ?? ExponentialBackoffPolicy(),
       _clock = clock ?? DateTime.now;

  final SyncQueue _syncQueue;
  final SyncRemoteDataSource _remoteDataSource;
  final EntitySyncStatusUpdater _entityStatusUpdater;
  final ExponentialBackoffPolicy _retryPolicy;
  final DateTime Function() _clock;

  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<SyncBatchResult> processPendingOperations({int limit = 100}) async {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Limit must be greater than zero.',
      );
    }

    if (_isRunning) {
      throw StateError('A synchronization batch is already running.');
    }

    _isRunning = true;

    try {
      await _syncQueue.recoverInterruptedOperations();

      final currentTime = _clock().toUtc();

      final operations = await _syncQueue.getReadyOperations(
        limit: limit,
        currentTime: currentTime,
      );

      var succeeded = 0;
      var retried = 0;
      var conflicted = 0;
      var failed = 0;

      developer.log(
        'Starting sync batch with '
        '${operations.length} operations',
        name: 'SyncEngine',
      );

      for (final operation in operations) {
        final outcome = await _processOperation(
          operation,
          attemptedAt: currentTime,
        );

        switch (outcome) {
          case _SyncOutcome.succeeded:
            succeeded++;
          case _SyncOutcome.retried:
            retried++;
          case _SyncOutcome.conflicted:
            conflicted++;
          case _SyncOutcome.failed:
            failed++;
        }
      }

      final result = SyncBatchResult(
        processed: operations.length,
        succeeded: succeeded,
        retried: retried,
        conflicted: conflicted,
        failed: failed,
      );

      developer.log('Completed $result', name: 'SyncEngine');

      return result;
    } finally {
      _isRunning = false;
    }
  }

  Future<_SyncOutcome> _processOperation(
    SyncOperation operation, {
    required DateTime attemptedAt,
  }) async {
    await _runAtomicStatusUpdate(operation, (transaction) {
      return _syncQueue.markProcessing(
        operation.operationId,
        attemptedAt: attemptedAt,
        executor: transaction,
      );
    });

    try {
      await _remoteDataSource.uploadOperation(operation);
    } on TemporarySyncException catch (error) {
      return _handleTemporaryFailure(
        operation,
        error,
        attemptedAt: attemptedAt,
      );
    } on SyncConflictException catch (error) {
      await _runAtomicStatusUpdate(operation, (transaction) {
        return _syncQueue.markConflict(
          operationId: operation.operationId,
          errorMessage: error.message,
          executor: transaction,
        );
      });

      developer.log(
        'Conflict detected for operation '
        '${operation.operationId}',
        name: 'SyncEngine',
      );

      return _SyncOutcome.conflicted;
    } on PermanentSyncException catch (error) {
      await _runAtomicStatusUpdate(operation, (transaction) {
        return _syncQueue.markFailed(
          operationId: operation.operationId,
          errorMessage: error.message,
          executor: transaction,
        );
      });

      developer.log(
        'Permanent failure for operation '
        '${operation.operationId}: ${error.message}',
        name: 'SyncEngine',
      );

      return _SyncOutcome.failed;
    } catch (error, stackTrace) {
      await _runAtomicStatusUpdate(operation, (transaction) {
        return _syncQueue.markFailed(
          operationId: operation.operationId,
          errorMessage: 'Unexpected synchronization error: $error',
          executor: transaction,
        );
      });

      developer.log(
        'Unexpected failure for operation '
        '${operation.operationId}',
        name: 'SyncEngine',
        error: error,
        stackTrace: stackTrace,
      );

      return _SyncOutcome.failed;
    }

    await _runAtomicStatusUpdate(operation, (transaction) {
      return _syncQueue.markSynced(
        operation.operationId,
        executor: transaction,
      );
    });

    developer.log(
      'Synced operation ${operation.operationId}',
      name: 'SyncEngine',
    );

    return _SyncOutcome.succeeded;
  }

  Future<_SyncOutcome> _handleTemporaryFailure(
    SyncOperation operation,
    TemporarySyncException error, {
    required DateTime attemptedAt,
  }) async {
    final nextRetryCount = operation.retryCount + 1;

    if (!_retryPolicy.canRetry(nextRetryCount)) {
      await _runAtomicStatusUpdate(operation, (transaction) {
        return _syncQueue.markFailed(
          operationId: operation.operationId,
          errorMessage: 'Retry limit reached: ${error.message}',
          executor: transaction,
        );
      });

      developer.log(
        'Retry limit reached for operation '
        '${operation.operationId}',
        name: 'SyncEngine',
      );

      return _SyncOutcome.failed;
    }

    final nextRetryAt = _retryPolicy.nextRetryAt(
      currentTime: attemptedAt,
      retryCount: nextRetryCount,
      serverRetryAfter: error.retryAfter,
    );

    await _runAtomicStatusUpdate(operation, (transaction) {
      return _syncQueue.markForRetry(
        operationId: operation.operationId,
        retryCount: nextRetryCount,
        nextRetryAt: nextRetryAt,
        errorMessage: error.message,
        executor: transaction,
      );
    });

    developer.log(
      'Scheduled operation ${operation.operationId} '
      'for retry $nextRetryCount at '
      '${nextRetryAt.toIso8601String()}',
      name: 'SyncEngine',
    );

    return _SyncOutcome.retried;
  }

  Future<void> _runAtomicStatusUpdate(
    SyncOperation operation,
    Future<void> Function(Transaction transaction) updateQueue,
  ) async {
    await _syncQueue.runTransaction((transaction) async {
      await updateQueue(transaction);

      await _entityStatusUpdater.refreshEntityStatus(
        entityType: operation.entityType,
        entityId: operation.entityId,
        executor: transaction,
      );
    });
  }
}

enum _SyncOutcome { succeeded, retried, conflicted, failed }
