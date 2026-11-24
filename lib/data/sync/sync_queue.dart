import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/sync_operation.dart';

class SyncQueue {
  SyncQueue(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) {
    return _appDatabase.runTransaction(action);
  }

  Future<void> enqueue(
    SyncOperation operation, {
    DatabaseExecutor? executor,
  }) async {
    final databaseExecutor = executor ?? await _appDatabase.database;

    await databaseExecutor.insert(
      'sync_queue',
      operation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    developer.log(
      'Queued ${operation.operationType.name} operation '
      '${operation.operationId} for '
      '${operation.entityType.name}:${operation.entityId}',
      name: 'SyncQueue',
    );
  }

  Future<List<SyncOperation>> getReadyOperations({
    int limit = 100,
    DateTime? currentTime,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Limit must be greater than zero.',
      );
    }

    final database = await _appDatabase.database;
    final now = (currentTime ?? DateTime.now()).toUtc().toIso8601String();

    final rows = await database.query(
      'sync_queue',
      where: '''
        status = ?
        AND (
          next_retry_at IS NULL
          OR next_retry_at <= ?
        )
      ''',
      whereArgs: [SyncQueueStatus.pending.name, now],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );

    return rows.map(SyncOperation.fromMap).toList(growable: false);
  }

  Future<SyncOperation?> getByOperationId(
    String operationId, {
    DatabaseExecutor? executor,
  }) async {
    final databaseExecutor = executor ?? await _appDatabase.database;

    final rows = await databaseExecutor.query(
      'sync_queue',
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return SyncOperation.fromMap(rows.first);
  }

  Future<void> markProcessing(
    String operationId, {
    DateTime? attemptedAt,
    DatabaseExecutor? executor,
  }) async {
    final attemptTime = (attemptedAt ?? DateTime.now()).toUtc();

    await _updateOperation(operationId, {
      'status': SyncQueueStatus.processing.name,
      'last_attempt': attemptTime.toIso8601String(),
      'error_message': null,
    }, executor: executor);
  }

  Future<void> markSynced(
    String operationId, {
    DatabaseExecutor? executor,
  }) async {
    await _updateOperation(operationId, {
      'status': SyncQueueStatus.synced.name,
      'next_retry_at': null,
      'error_message': null,
    }, executor: executor);
  }

  Future<void> markForRetry({
    required String operationId,
    required int retryCount,
    required DateTime nextRetryAt,
    required String errorMessage,
    DatabaseExecutor? executor,
  }) async {
    await _updateOperation(operationId, {
      'status': SyncQueueStatus.pending.name,
      'retry_count': retryCount,
      'next_retry_at': nextRetryAt.toUtc().toIso8601String(),
      'error_message': errorMessage,
    }, executor: executor);

    developer.log(
      'Operation $operationId scheduled for retry '
      'at ${nextRetryAt.toUtc().toIso8601String()}',
      name: 'SyncQueue',
    );
  }

  Future<void> markFailed({
    required String operationId,
    required String errorMessage,
    DatabaseExecutor? executor,
  }) async {
    await _updateOperation(operationId, {
      'status': SyncQueueStatus.failed.name,
      'next_retry_at': null,
      'error_message': errorMessage,
    }, executor: executor);
  }

  Future<void> markConflict({
    required String operationId,
    required String errorMessage,
    DatabaseExecutor? executor,
  }) async {
    await _updateOperation(operationId, {
      'status': SyncQueueStatus.conflict.name,
      'next_retry_at': null,
      'error_message': errorMessage,
    }, executor: executor);
  }

  Future<void> retryFailedOperation(
    String operationId, {
    DatabaseExecutor? executor,
  }) async {
    await _updateOperation(operationId, {
      'status': SyncQueueStatus.pending.name,
      'next_retry_at': null,
      'error_message': null,
    }, executor: executor);
  }

  Future<void> recoverInterruptedOperations() async {
    final database = await _appDatabase.database;

    final recoveredCount = await database.update(
      'sync_queue',
      {
        'status': SyncQueueStatus.pending.name,
        'next_retry_at': null,
        'error_message': 'Previous synchronization was interrupted.',
      },
      where: 'status = ?',
      whereArgs: [SyncQueueStatus.processing.name],
    );

    if (recoveredCount > 0) {
      developer.log(
        'Recovered $recoveredCount interrupted operations',
        name: 'SyncQueue',
      );
    }
  }

  Future<Map<SyncQueueStatus, int>> getStatusCounts() async {
    final database = await _appDatabase.database;

    final rows = await database.rawQuery('''
      SELECT status, COUNT(*) AS count
      FROM sync_queue
      GROUP BY status
    ''');

    final counts = {for (final status in SyncQueueStatus.values) status: 0};

    for (final row in rows) {
      final statusName = row['status'] as String;
      final count = row['count'] as int? ?? 0;

      counts[SyncQueueStatus.values.byName(statusName)] = count;
    }

    return counts;
  }

  Future<DateTime?> getLastSuccessfulSyncAt() async {
    final database = await _appDatabase.database;

    final rows = await database.rawQuery(
      '''
      SELECT MAX(last_attempt) AS last_successful_sync
      FROM sync_queue
      WHERE status = ?
    ''',
      [SyncQueueStatus.synced.name],
    );

    if (rows.isEmpty) {
      return null;
    }

    final value = rows.first['last_successful_sync'];

    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return DateTime.parse(value).toLocal();
  }

  Future<List<SyncOperation>> getOperationsByStatus(
    SyncQueueStatus status,
  ) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at ASC, id ASC',
    );

    return rows.map(SyncOperation.fromMap).toList(growable: false);
  }

  Future<bool> hasPendingOperationForEntity({
    required SyncEntityType entityType,
    required String entityId,
  }) async {
    final database = await _appDatabase.database;

    final result = await database.rawQuery(
      '''
        SELECT COUNT(*) AS count
        FROM sync_queue
        WHERE entity_type = ?
          AND entity_id = ?
          AND status IN (?, ?)
      ''',
      [
        entityType.name,
        entityId,
        SyncQueueStatus.pending.name,
        SyncQueueStatus.processing.name,
      ],
    );

    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  Future<void> _updateOperation(
    String operationId,
    Map<String, Object?> values, {
    DatabaseExecutor? executor,
  }) async {
    final databaseExecutor = executor ?? await _appDatabase.database;

    final updatedRows = await databaseExecutor.update(
      'sync_queue',
      values,
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );

    if (updatedRows == 0) {
      throw StateError('Sync operation $operationId was not found.');
    }
  }
}
