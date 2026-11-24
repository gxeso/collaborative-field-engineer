import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:offline_survey_and_sync_app/data/models/observation.dart';
import 'package:offline_survey_and_sync_app/data/models/survey_site.dart';
import 'package:offline_survey_and_sync_app/data/models/sync_operation.dart';
import 'package:offline_survey_and_sync_app/data/repositories/observation_repository_impl.dart';
import 'package:offline_survey_and_sync_app/data/services/replica_identity_service.dart';
import 'package:offline_survey_and_sync_app/data/sync/sync_queue.dart';
import 'package:offline_survey_and_sync_app/domain/entities/sync_status.dart';
import 'package:offline_survey_and_sync_app/domain/entities/version_vector.dart';

class MockUuid extends Mock implements Uuid {}

void main() {
  const actorId = 'observation-replica-001';

  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late SyncQueue syncQueue;
  late ReplicaIdentityService identityService;
  late MockUuid operationUuid;
  late ObservationRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'observation_repository_test_',
    );

    final testDatabasePath = path.join(
      temporaryDirectory.path,
      'observation_repository_test.db',
    );

    appDatabase = AppDatabase(databasePath: testDatabasePath);
    syncQueue = SyncQueue(appDatabase);

    final identityUuid = MockUuid();

    when(() => identityUuid.v4()).thenReturn(actorId);

    identityService = ReplicaIdentityService(
      appDatabase: appDatabase,
      uuid: identityUuid,
    );

    await identityService.getActorId();

    operationUuid = MockUuid();

    repository = ObservationRepositoryImpl(
      appDatabase: appDatabase,
      syncQueue: syncQueue,
      identityService: identityService,
      uuid: operationUuid,
    );

    await insertParentSite(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('addObservation saves locally as pending and queues CREATE', () async {
    when(
      () => operationUuid.v4(),
    ).thenReturn('operation-create-observation-001');

    final observation = createObservation();

    await repository.addObservation(observation);

    final savedObservation = await repository.getObservationById(
      observation.id,
    );

    final siteObservations = await repository.getObservations(
      observation.siteId,
    );

    final readyOperations = await syncQueue.getReadyOperations();

    expect(savedObservation, isNotNull);
    expect(savedObservation!.id, 'observation-001');
    expect(savedObservation.siteId, 'site-001');
    expect(savedObservation.temperature, 31.5);
    expect(savedObservation.humidity, 64.0);
    expect(savedObservation.pm25, 18.2);
    expect(savedObservation.notes, 'Initial field reading');
    expect(savedObservation.syncStatus, SyncStatus.pending);
    expect(savedObservation.versionVector.versionFor(actorId), 1);
    expect(savedObservation.changeCount, 1);

    expect(
      savedObservation.fieldModifiedAt.keys,
      containsAll([
        'temperature',
        'humidity',
        'pm25',
        'notes',
        'photoPath',
        'weatherData',
      ]),
    );

    expect(siteObservations, hasLength(1));
    expect(readyOperations, hasLength(1));

    final operation = readyOperations.single;

    expect(operation.operationId, 'operation-create-observation-001');
    expect(operation.entityType, SyncEntityType.observation);
    expect(operation.entityId, 'observation-001');
    expect(operation.operationType, SyncOperationType.create);
    expect(operation.status, SyncQueueStatus.pending);
    expect(operation.payload['siteId'], 'site-001');
    expect(operation.payload['versionVector'], {actorId: 1});
    expect(operation.payload.containsKey('version'), isFalse);
    expect(operation.payload['fieldModifiedAt'], isA<Map<String, dynamic>>());
  });

  test(
    'updateObservation saves changes as pending and queues UPDATE',
    () async {
      final operationIds = [
        'operation-create-observation-001',
        'operation-update-observation-001',
      ];

      when(
        () => operationUuid.v4(),
      ).thenAnswer((_) => operationIds.removeAt(0));

      final originalObservation = createObservation();

      await repository.addObservation(originalObservation);

      final savedBeforeUpdate = await repository.getObservationById(
        originalObservation.id,
      );

      expect(savedBeforeUpdate, isNotNull);

      final originalCreatedAt = savedBeforeUpdate!.createdAt;
      final originalTemperatureTimestamp =
          savedBeforeUpdate.fieldModifiedAt['temperature'];
      final originalHumidityTimestamp =
          savedBeforeUpdate.fieldModifiedAt['humidity'];

      final editedObservation = savedBeforeUpdate.copyWith(
        temperature: 29.7,
        notes: 'Updated after equipment calibration',
      );

      await repository.updateObservation(editedObservation);

      final savedAfterUpdate = await repository.getObservationById(
        originalObservation.id,
      );

      final readyOperations = await syncQueue.getReadyOperations();

      expect(savedAfterUpdate, isNotNull);
      expect(savedAfterUpdate!.temperature, 29.7);
      expect(savedAfterUpdate.humidity, 64.0);
      expect(savedAfterUpdate.notes, 'Updated after equipment calibration');

      expect(savedAfterUpdate.createdAt, originalCreatedAt);
      expect(savedAfterUpdate.syncStatus, SyncStatus.pending);
      expect(savedAfterUpdate.versionVector.versionFor(actorId), 2);
      expect(savedAfterUpdate.changeCount, 2);

      expect(
        savedAfterUpdate.fieldModifiedAt['temperature'],
        isNot(originalTemperatureTimestamp),
      );

      expect(
        savedAfterUpdate.fieldModifiedAt['humidity'],
        originalHumidityTimestamp,
      );

      expect(readyOperations, hasLength(2));

      final updateOperation = readyOperations.last;

      expect(updateOperation.operationId, 'operation-update-observation-001');

      expect(updateOperation.entityType, SyncEntityType.observation);
      expect(updateOperation.entityId, 'observation-001');
      expect(updateOperation.operationType, SyncOperationType.update);
      expect(updateOperation.status, SyncQueueStatus.pending);
      expect(updateOperation.payload['temperature'], 29.7);

      expect(
        updateOperation.payload['notes'],
        'Updated after equipment calibration',
      );

      expect(updateOperation.payload['versionVector'], {actorId: 2});
    },
  );

  test('deleteObservation removes local record and queues DELETE', () async {
    final operationIds = [
      'operation-create-observation-001',
      'operation-delete-observation-001',
    ];

    when(() => operationUuid.v4()).thenAnswer((_) => operationIds.removeAt(0));

    final observation = createObservation();

    await repository.addObservation(observation);

    expect(await repository.getObservationById(observation.id), isNotNull);

    await repository.deleteObservation(observation.id);

    final deletedObservation = await repository.getObservationById(
      observation.id,
    );

    final siteObservations = await repository.getObservations(
      observation.siteId,
    );

    final readyOperations = await syncQueue.getReadyOperations();

    expect(deletedObservation, isNull);
    expect(siteObservations, isEmpty);
    expect(readyOperations, hasLength(2));

    final deleteOperation = readyOperations.last;

    expect(deleteOperation.operationId, 'operation-delete-observation-001');

    expect(deleteOperation.entityType, SyncEntityType.observation);
    expect(deleteOperation.entityId, 'observation-001');
    expect(deleteOperation.operationType, SyncOperationType.delete);
    expect(deleteOperation.status, SyncQueueStatus.pending);
    expect(deleteOperation.payload['id'], 'observation-001');
    expect(deleteOperation.payload['siteId'], 'site-001');
    expect(deleteOperation.payload['deletedAt'], isA<String>());
    expect(deleteOperation.payload['versionVector'], {actorId: 2});
  });

  test('updateObservation rejects a missing observation', () async {
    when(() => operationUuid.v4()).thenReturn('unused-operation-id');

    final missingObservation = createObservation().copyWith(
      id: 'missing-observation',
    );

    await expectLater(
      repository.updateObservation(missingObservation),
      throwsA(isA<StateError>()),
    );

    expect(await syncQueue.getReadyOperations(), isEmpty);
  });

  test('deleteObservation rejects a missing observation', () async {
    when(() => operationUuid.v4()).thenReturn('unused-operation-id');

    await expectLater(
      repository.deleteObservation('missing-observation'),
      throwsA(isA<StateError>()),
    );

    expect(await syncQueue.getReadyOperations(), isEmpty);
  });
}

Future<void> insertParentSite(AppDatabase appDatabase) async {
  final database = await appDatabase.database;
  final createdAt = DateTime.utc(2026, 9, 28, 10);

  final site = SurveySite(
    id: 'site-001',
    name: 'Observation Test Site',
    latitude: 25.2048,
    longitude: 55.2708,
    createdAt: createdAt,
    updatedAt: createdAt,
    versionVector: VersionVector(),
    syncStatus: SyncStatus.synced,
  );

  await database.insert('survey_sites', site.toMap());
}

Observation createObservation() {
  final createdAt = DateTime.utc(2026, 9, 28, 10, 30);

  return Observation(
    id: 'observation-001',
    siteId: 'site-001',
    temperature: 31.5,
    humidity: 64.0,
    pm25: 18.2,
    notes: 'Initial field reading',
    weatherData: {'condition': 'clear', 'windSpeed': 8.5},
    createdAt: createdAt,
    updatedAt: createdAt,
    versionVector: VersionVector(),
  );
}
