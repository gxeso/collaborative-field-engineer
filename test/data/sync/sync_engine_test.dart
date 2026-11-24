import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:offline_survey_and_sync_app/data/models/sync_operation.dart';
import 'package:offline_survey_and_sync_app/data/remote/sync_remote_data_source.dart';
import 'package:offline_survey_and_sync_app/data/remote/sync_remote_exception.dart';
import 'package:offline_survey_and_sync_app/data/sync/entity_sync_status_updater.dart';
import 'package:offline_survey_and_sync_app/data/sync/exponential_backoff_policy.dart';
import 'package:offline_survey_and_sync_app/data/sync/sync_engine.dart';
import 'package:offline_survey_and_sync_app/data/sync/sync_queue.dart';

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

void main() {
  final fixedTime = DateTime.utc(2026, 9, 29, 9);

  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late SyncQueue syncQueue;
  late EntitySyncStatusUpdater entityStatusUpdater;
  late MockSyncRemoteDataSource remoteDataSource;
  late SyncEngine syncEngine;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    registerFallbackValue(createOperation(operationId: 'fallback-operation'));
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sync_engine_test_',
    );

    final testDatabasePath = path.join(
      temporaryDirectory.path,
      'sync_engine_test.db',
    );

    appDatabase = AppDatabase(databasePath: testDatabasePath);

    syncQueue = SyncQueue(appDatabase);

    entityStatusUpdater = EntitySyncStatusUpdater(appDatabase);

    remoteDataSource = MockSyncRemoteDataSource();

    syncEngine = SyncEngine(
      syncQueue: syncQueue,
      remoteDataSource: remoteDataSource,
      entityStatusUpdater: entityStatusUpdater,
      retryPolicy: ExponentialBackoffPolicy(),
      clock: () => fixedTime,
    );
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('marks a successful upload as synced', () async {
    final operation = createOperation(operationId: 'successful-operation');

    await syncQueue.enqueue(operation);

    when(
      () => remoteDataSource.uploadOperation(any()),
    ).thenAnswer((_) async {});

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.processed, 1);
    expect(result.succeeded, 1);
    expect(result.retried, 0);
    expect(result.conflicted, 0);
    expect(result.failed, 0);

    expect(savedOperation!.status, SyncQueueStatus.synced);

    expect(savedOperation.lastAttemptAt, fixedTime);

    verify(() => remoteDataSource.uploadOperation(any())).called(1);
  });

  test('schedules a temporary failure for retry', () async {
    final operation = createOperation(operationId: 'temporary-failure');

    await syncQueue.enqueue(operation);

    when(
      () => remoteDataSource.uploadOperation(any()),
    ).thenThrow(const TemporarySyncException('No internet connection.'));

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.processed, 1);
    expect(result.retried, 1);

    expect(savedOperation!.status, SyncQueueStatus.pending);

    expect(savedOperation.retryCount, 1);

    expect(
      savedOperation.nextRetryAt,
      fixedTime.add(const Duration(seconds: 2)),
    );

    expect(savedOperation.errorMessage, 'No internet connection.');
  });

  test('marks a concurrent version as conflict', () async {
    final operation = createOperation(operationId: 'conflict-operation');

    await syncQueue.enqueue(operation);

    when(() => remoteDataSource.uploadOperation(any())).thenThrow(
      const SyncConflictException(
        'Concurrent remote version detected.',
        remotePayload: {
          'id': 'site-001',
          'versionVector': {'device-b': 2},
        },
      ),
    );

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.conflicted, 1);

    expect(savedOperation!.status, SyncQueueStatus.conflict);

    expect(savedOperation.errorMessage, 'Concurrent remote version detected.');
  });

  test('marks a permanent rejection as failed', () async {
    final operation = createOperation(operationId: 'permanent-failure');

    await syncQueue.enqueue(operation);

    when(
      () => remoteDataSource.uploadOperation(any()),
    ).thenThrow(const PermanentSyncException('Server rejected the payload.'));

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.failed, 1);

    expect(savedOperation!.status, SyncQueueStatus.failed);

    expect(savedOperation.errorMessage, 'Server rejected the payload.');
  });

  test('recovers and processes an interrupted operation', () async {
    final operation = createOperation(operationId: 'interrupted-operation');

    await syncQueue.enqueue(operation);

    await syncQueue.markProcessing(
      operation.operationId,
      attemptedAt: fixedTime.subtract(const Duration(minutes: 5)),
    );

    when(
      () => remoteDataSource.uploadOperation(any()),
    ).thenAnswer((_) async {});

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.processed, 1);
    expect(result.succeeded, 1);

    expect(savedOperation!.status, SyncQueueStatus.synced);
  });

  test('marks a temporary failure as failed '
      'after retry limit', () async {
    final operation = createOperation(
      operationId: 'retry-limit-operation',
      retryCount: 5,
    );

    await syncQueue.enqueue(operation);

    when(
      () => remoteDataSource.uploadOperation(any()),
    ).thenThrow(const TemporarySyncException('Server remains unavailable.'));

    final result = await syncEngine.processPendingOperations();

    final savedOperation = await syncQueue.getByOperationId(
      operation.operationId,
    );

    expect(result.failed, 1);
    expect(result.retried, 0);

    expect(savedOperation!.status, SyncQueueStatus.failed);

    expect(savedOperation.errorMessage, contains('Retry limit reached'));
  });
}

SyncOperation createOperation({
  required String operationId,
  int retryCount = 0,
}) {
  return SyncOperation(
    operationId: operationId,
    entityType: SyncEntityType.site,
    entityId: 'site-001',
    operationType: SyncOperationType.create,
    payload: {
      'id': 'site-001',
      'name': 'Test Site',
      'versionVector': {'test-replica': 1},
    },
    retryCount: retryCount,
    createdAt: DateTime.utc(2026, 9, 29, 8),
  );
}
