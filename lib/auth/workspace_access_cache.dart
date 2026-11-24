import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'cached_workspace_access.dart';
import 'workspace_access_service.dart';

class WorkspaceAccessCache {
  WorkspaceAccessCache(this._appDatabase);

  static const String tableName = 'cached_workspace_access';

  final AppDatabase _appDatabase;

  Future<void> save(
    CachedWorkspaceAccess access, {
    DatabaseExecutor? executor,
  }) async {
    final databaseExecutor = executor ?? await _appDatabase.database;

    final normalizedAccess = CachedWorkspaceAccess(
      uid: _normalizeRequired(access.uid, fieldName: 'uid'),
      workspaceId: _normalizeRequired(
        access.workspaceId,
        fieldName: 'workspaceId',
      ),
      role: access.role,
      verifiedAt: access.verifiedAt.toUtc(),
    );

    await databaseExecutor.insert(
      tableName,
      normalizedAccess.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedWorkspaceAccess?> get({
    required String uid,
    required String workspaceId,
    DatabaseExecutor? executor,
  }) async {
    final normalizedUid = _normalizeRequired(uid, fieldName: 'uid');

    final normalizedWorkspaceId = _normalizeRequired(
      workspaceId,
      fieldName: 'workspaceId',
    );

    final databaseExecutor = executor ?? await _appDatabase.database;

    final rows = await databaseExecutor.query(
      tableName,
      where: 'uid = ? AND workspace_id = ?',
      whereArgs: [normalizedUid, normalizedWorkspaceId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CachedWorkspaceAccess.fromMap(rows.first);
  }

  Future<void> updateRole({
    required String uid,
    required String workspaceId,
    required WorkspaceRole role,
    DateTime? verifiedAt,
    DatabaseExecutor? executor,
  }) async {
    final normalizedUid = _normalizeRequired(uid, fieldName: 'uid');

    final normalizedWorkspaceId = _normalizeRequired(
      workspaceId,
      fieldName: 'workspaceId',
    );

    final databaseExecutor = executor ?? await _appDatabase.database;

    final updatedRows = await databaseExecutor.update(
      tableName,
      {
        'role': role.name,
        'verified_at': (verifiedAt ?? DateTime.now()).toUtc().toIso8601String(),
      },
      where: 'uid = ? AND workspace_id = ?',
      whereArgs: [normalizedUid, normalizedWorkspaceId],
    );

    if (updatedRows == 0) {
      throw StateError(
        'No cached workspace access exists for '
        '$normalizedUid in $normalizedWorkspaceId.',
      );
    }
  }

  Future<void> remove({
    required String uid,
    required String workspaceId,
    DatabaseExecutor? executor,
  }) async {
    final normalizedUid = _normalizeRequired(uid, fieldName: 'uid');

    final normalizedWorkspaceId = _normalizeRequired(
      workspaceId,
      fieldName: 'workspaceId',
    );

    final databaseExecutor = executor ?? await _appDatabase.database;

    await databaseExecutor.delete(
      tableName,
      where: 'uid = ? AND workspace_id = ?',
      whereArgs: [normalizedUid, normalizedWorkspaceId],
    );
  }

  Future<void> removeAllForUser(
    String uid, {
    DatabaseExecutor? executor,
  }) async {
    final normalizedUid = _normalizeRequired(uid, fieldName: 'uid');

    final databaseExecutor = executor ?? await _appDatabase.database;

    await databaseExecutor.delete(
      tableName,
      where: 'uid = ?',
      whereArgs: [normalizedUid],
    );
  }

  String _normalizeRequired(String value, {required String fieldName}) {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName cannot be empty.',
      );
    }

    return normalizedValue;
  }
}
