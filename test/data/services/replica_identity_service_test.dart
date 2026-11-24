import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:offline_survey_and_sync_app/data/services/replica_identity_service.dart';

class MockUuid extends Mock implements Uuid {}

void main() {
  late Directory temporaryDirectory;
  late String testDatabasePath;
  late AppDatabase appDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'replica_identity_test_',
    );

    testDatabasePath = path.join(temporaryDirectory.path, 'identity_test.db');

    appDatabase = AppDatabase(databasePath: testDatabasePath);
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('returns the same actor ID on repeated calls', () async {
    final uuid = MockUuid();

    when(() => uuid.v4()).thenReturn('actor-test-001');

    final service = ReplicaIdentityService(
      appDatabase: appDatabase,
      uuid: uuid,
    );

    final firstActorId = await service.getActorId();
    final secondActorId = await service.getActorId();

    expect(firstActorId, 'actor-test-001');
    expect(secondActorId, 'actor-test-001');

    verify(() => uuid.v4()).called(1);
  });

  test(
    'preserves the actor ID after closing and reopening the database',
    () async {
      final firstUuid = MockUuid();

      when(() => firstUuid.v4()).thenReturn('persistent-actor-001');

      final firstService = ReplicaIdentityService(
        appDatabase: appDatabase,
        uuid: firstUuid,
      );

      final originalActorId = await firstService.getActorId();

      await appDatabase.close();

      appDatabase = AppDatabase(databasePath: testDatabasePath);

      final secondUuid = MockUuid();

      final secondService = ReplicaIdentityService(
        appDatabase: appDatabase,
        uuid: secondUuid,
      );

      final reopenedActorId = await secondService.getActorId();

      expect(originalActorId, 'persistent-actor-001');
      expect(reopenedActorId, originalActorId);

      verify(() => firstUuid.v4()).called(1);
      verifyNever(() => secondUuid.v4());
    },
  );
}
