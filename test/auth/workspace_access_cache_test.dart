import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_survey_and_sync_app/auth/cached_workspace_access.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_cache.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_service.dart';
import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase appDatabase;
  late WorkspaceAccessCache cache;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'workspace_access_cache_test_',
    );

    appDatabase = AppDatabase(
      databasePath:
          '${temporaryDirectory.path}'
          '${Platform.pathSeparator}'
          'test.db',
    );

    cache = WorkspaceAccessCache(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('saves and retrieves verified workspace access', () async {
    final verifiedAt = DateTime.utc(2026, 10, 15, 8, 30);

    await cache.save(
      CachedWorkspaceAccess(
        uid: 'user-one',
        workspaceId: 'workspace-one',
        role: WorkspaceRole.admin,
        verifiedAt: verifiedAt,
      ),
    );

    final result = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-one',
    );

    expect(result, isNotNull);
    expect(result!.uid, 'user-one');
    expect(result.workspaceId, 'workspace-one');
    expect(result.role, WorkspaceRole.admin);
    expect(result.verifiedAt, verifiedAt);
    expect(result.access.canSynchronize, isTrue);
  });

  test('updates an existing cached role', () async {
    await cache.save(
      CachedWorkspaceAccess(
        uid: 'user-one',
        workspaceId: 'workspace-one',
        role: WorkspaceRole.admin,
        verifiedAt: DateTime.utc(2026, 10, 15),
      ),
    );

    final newVerificationTime = DateTime.utc(2026, 10, 16);

    await cache.updateRole(
      uid: 'user-one',
      workspaceId: 'workspace-one',
      role: WorkspaceRole.viewer,
      verifiedAt: newVerificationTime,
    );

    final result = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-one',
    );

    expect(result, isNotNull);
    expect(result!.role, WorkspaceRole.viewer);
    expect(result.verifiedAt, newVerificationTime);
    expect(result.access.canSynchronize, isFalse);
  });

  test('removes cached access', () async {
    await cache.save(
      CachedWorkspaceAccess(
        uid: 'user-one',
        workspaceId: 'workspace-one',
        role: WorkspaceRole.editor,
        verifiedAt: DateTime.utc(2026, 10, 15),
      ),
    );

    await cache.remove(uid: 'user-one', workspaceId: 'workspace-one');

    final result = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-one',
    );

    expect(result, isNull);
  });

  test('keeps cached access isolated by user UID', () async {
    await cache.save(
      CachedWorkspaceAccess(
        uid: 'user-one',
        workspaceId: 'workspace-one',
        role: WorkspaceRole.admin,
        verifiedAt: DateTime.utc(2026, 10, 15),
      ),
    );

    final otherUserResult = await cache.get(
      uid: 'user-two',
      workspaceId: 'workspace-one',
    );

    expect(otherUserResult, isNull);

    final correctUserResult = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-one',
    );

    expect(correctUserResult, isNotNull);
    expect(correctUserResult!.role, WorkspaceRole.admin);
  });

  test('keeps cached access isolated by workspace', () async {
    await cache.save(
      CachedWorkspaceAccess(
        uid: 'user-one',
        workspaceId: 'workspace-one',
        role: WorkspaceRole.admin,
        verifiedAt: DateTime.utc(2026, 10, 15),
      ),
    );

    final otherWorkspaceResult = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-two',
    );

    expect(otherWorkspaceResult, isNull);

    final correctWorkspaceResult = await cache.get(
      uid: 'user-one',
      workspaceId: 'workspace-one',
    );

    expect(correctWorkspaceResult, isNotNull);
  });

  test('SQLite rejects unsupported cached roles', () async {
    final database = await appDatabase.database;

    expect(
      () => database.insert(WorkspaceAccessCache.tableName, {
        'uid': 'user-one',
        'workspace_id': 'workspace-one',
        'role': 'owner',
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
