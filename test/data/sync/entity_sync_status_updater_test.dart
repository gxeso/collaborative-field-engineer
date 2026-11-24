import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:offline_survey_and_sync_app/data/models/sync_operation.dart';
import 'package:offline_survey_and_sync_app/data/sync/entity_sync_status_updater.dart';
import 'package:offline_survey_and_sync_app/data/sync/sync_queue.dart';
import 'package:offline_survey_and_sync_app/domain/entities/sync_status.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late SyncQueue syncQueue;
  late EntitySyncStatusUpdater statusUpdater;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'entity_status_test_',
    );

    final databasePath = path.join(
      temporaryDirectory.path,
      'entity_status_test.db',
    );

    appDatabase = AppDatabase(databasePath: databasePath);
    syncQueue = SyncQueue(appDatabase);
    statusUpdater = EntitySyncStatusUpdater(appDatabase);

    await insertSurveySite(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('entity becomes synced when all operations are synced', () async {
    final operation = createOperation('operation-1');

    await syncQueue.enqueue(operation);
    await syncQueue.markSynced(operation.operationId);

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.synced);
    expect(await readSiteStatus(appDatabase), SyncStatus.synced);
  });

  test('pending operation keeps entity pending', () async {
    final syncedOperation = createOperation('operation-1');
    final pendingOperation = createOperation('operation-2');

    await syncQueue.enqueue(syncedOperation);
    await syncQueue.enqueue(pendingOperation);

    await syncQueue.markSynced(syncedOperation.operationId);

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.pending);
    expect(await readSiteStatus(appDatabase), SyncStatus.pending);
  });

  test('conflict has priority over every other status', () async {
    final conflictOperation = createOperation('operation-1');
    final failedOperation = createOperation('operation-2');
    final pendingOperation = createOperation('operation-3');

    await syncQueue.enqueue(conflictOperation);
    await syncQueue.enqueue(failedOperation);
    await syncQueue.enqueue(pendingOperation);

    await syncQueue.markConflict(
      operationId: conflictOperation.operationId,
      errorMessage: 'Concurrent versions detected.',
    );

    await syncQueue.markFailed(
      operationId: failedOperation.operationId,
      errorMessage: 'Permanent server rejection.',
    );

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.conflict);
    expect(await readSiteStatus(appDatabase), SyncStatus.conflict);
  });

  test('failed operation makes entity failed', () async {
    final operation = createOperation('operation-1');

    await syncQueue.enqueue(operation);

    await syncQueue.markFailed(
      operationId: operation.operationId,
      errorMessage: 'Payload rejected.',
    );

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.failed);
    expect(await readSiteStatus(appDatabase), SyncStatus.failed);
  });

  test('processing operation keeps entity pending', () async {
    final operation = createOperation('operation-1');

    await syncQueue.enqueue(operation);
    await syncQueue.markProcessing(operation.operationId);

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.pending);
    expect(await readSiteStatus(appDatabase), SyncStatus.pending);
  });

  test('missing deleted entity is handled safely', () async {
    final operation = createOperation('operation-1');

    await syncQueue.enqueue(operation);
    await syncQueue.markSynced(operation.operationId);

    final database = await appDatabase.database;

    await database.delete(
      'survey_sites',
      where: 'id = ?',
      whereArgs: ['site-001'],
    );

    final status = await statusUpdater.refreshEntityStatus(
      entityType: SyncEntityType.site,
      entityId: 'site-001',
    );

    expect(status, SyncStatus.synced);

    final rows = await database.query(
      'survey_sites',
      where: 'id = ?',
      whereArgs: ['site-001'],
    );

    expect(rows, isEmpty);
  });

  test(
    'transaction rolls back queue update when entity update fails',
    () async {
      final operation = createOperation('operation-1');

      await syncQueue.enqueue(operation);

      expect(
        () => syncQueue.runTransaction((transaction) async {
          await syncQueue.markSynced(
            operation.operationId,
            executor: transaction,
          );

          await transaction.update('table_that_does_not_exist', {
            'sync_status': 'synced',
          });
        }),
        throwsA(anything),
      );

      final savedOperation = await syncQueue.getByOperationId(
        operation.operationId,
      );

      expect(savedOperation!.status, SyncQueueStatus.pending);
    },
  );
}

SyncOperation createOperation(String operationId) {
  return SyncOperation(
    operationId: operationId,
    entityType: SyncEntityType.site,
    entityId: 'site-001',
    operationType: SyncOperationType.update,
    payload: {
      'id': 'site-001',
      'name': 'Test Site',
      'versionVector': {'test-device': 1},
    },
    createdAt: DateTime.utc(2026, 10, 1, 10),
  );
}

Future<void> insertSurveySite(AppDatabase appDatabase) async {
  final database = await appDatabase.database;
  final now = DateTime.utc(2026, 10, 1, 9).toIso8601String();

  await database.insert('survey_sites', {
    'id': 'site-001',
    'name': 'Test Site',
    'latitude': 25.2048,
    'longitude': 55.2708,
    'region_geojson': null,
    'created_at': now,
    'updated_at': now,
    'version_vector': '{"test-device":1}',
    'sync_status': SyncStatus.pending.name,
  });
}

Future<SyncStatus> readSiteStatus(AppDatabase appDatabase) async {
  final database = await appDatabase.database;

  final rows = await database.query(
    'survey_sites',
    columns: ['sync_status'],
    where: 'id = ?',
    whereArgs: ['site-001'],
    limit: 1,
  );

  return SyncStatus.fromName(rows.first['sync_status'] as String?);
}
