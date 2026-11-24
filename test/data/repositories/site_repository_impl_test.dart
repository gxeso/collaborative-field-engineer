import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:offline_survey_and_sync_app/data/models/survey_site.dart';
import 'package:offline_survey_and_sync_app/data/models/sync_operation.dart';
import 'package:offline_survey_and_sync_app/data/repositories/site_repository_impl.dart';
import 'package:offline_survey_and_sync_app/data/services/replica_identity_service.dart';
import 'package:offline_survey_and_sync_app/data/sync/sync_queue.dart';
import 'package:offline_survey_and_sync_app/domain/entities/sync_status.dart';
import 'package:offline_survey_and_sync_app/domain/entities/version_vector.dart';

class MockUuid extends Mock implements Uuid {}

void main() {
  const actorId = 'test-replica-001';

  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late SyncQueue syncQueue;
  late ReplicaIdentityService identityService;
  late MockUuid operationUuid;
  late SiteRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'site_repository_test_',
    );

    final testDatabasePath = path.join(
      temporaryDirectory.path,
      'site_repository_test.db',
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

    repository = SiteRepositoryImpl(
      appDatabase: appDatabase,
      syncQueue: syncQueue,
      identityService: identityService,
      uuid: operationUuid,
    );
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('addSite saves the site and queues one CREATE operation', () async {
    when(() => operationUuid.v4()).thenReturn('operation-create-site-001');

    final site = createSite(id: 'site-001', name: 'Dubai Survey Site');

    await repository.addSite(site);

    final savedSite = await repository.getSiteById(site.id);

    final readyOperations = await syncQueue.getReadyOperations();

    expect(savedSite, isNotNull);
    expect(savedSite!.id, site.id);
    expect(savedSite.name, 'Dubai Survey Site');
    expect(savedSite.syncStatus, SyncStatus.pending);

    expect(savedSite.versionVector.versionFor(actorId), 1);

    expect(savedSite.changeCount, 1);

    expect(readyOperations, hasLength(1));

    final operation = readyOperations.single;

    expect(operation.operationId, 'operation-create-site-001');

    expect(operation.entityType, SyncEntityType.site);

    expect(operation.entityId, site.id);

    expect(operation.operationType, SyncOperationType.create);

    expect(operation.status, SyncQueueStatus.pending);

    expect(operation.payload['versionVector'], {actorId: 1});

    expect(operation.payload.containsKey('version'), isFalse);
  });

  test('rolls back the site insert when queue insertion fails', () async {
    when(() => operationUuid.v4()).thenReturn('duplicate-operation-id');

    final firstSite = createSite(id: 'site-001', name: 'First Site');

    final secondSite = createSite(id: 'site-002', name: 'Second Site');

    await repository.addSite(firstSite);

    await expectLater(
      repository.addSite(secondSite),
      throwsA(isA<DatabaseException>()),
    );

    final savedFirstSite = await repository.getSiteById('site-001');

    final savedSecondSite = await repository.getSiteById('site-002');

    final readyOperations = await syncQueue.getReadyOperations();

    expect(savedFirstSite, isNotNull);

    // The second insert must be rolled back because its
    // queue operation failed inside the same transaction.
    expect(savedSecondSite, isNull);

    expect(readyOperations, hasLength(1));
    expect(readyOperations.single.entityId, 'site-001');
  });
}

SurveySite createSite({required String id, required String name}) {
  final createdAt = DateTime.utc(2026, 9, 28, 8);

  return SurveySite(
    id: id,
    name: name,
    latitude: 25.2048,
    longitude: 55.2708,
    createdAt: createdAt,
    updatedAt: createdAt,
    versionVector: VersionVector(),
  );
}
