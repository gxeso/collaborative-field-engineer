import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/sync_status.dart';
import '../database/app_database.dart';
import '../models/sync_operation.dart';

class EntitySyncStatusUpdater {
  EntitySyncStatusUpdater(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<SyncStatus> refreshEntityStatus({
    required SyncEntityType entityType,
    required String entityId,
    DatabaseExecutor? executor,
  }) async {
    final databaseExecutor = executor ?? await _appDatabase.database;

    final rows = await databaseExecutor.query(
      'sync_queue',
      columns: ['status'],
      where: '''
        entity_type = ?
        AND entity_id = ?
      ''',
      whereArgs: [entityType.name, entityId],
    );

    final queueStatuses = rows
        .map((row) => SyncQueueStatus.values.byName(row['status'] as String))
        .toSet();

    final entityStatus = _resolveStatus(queueStatuses);

    final tableName = switch (entityType) {
      SyncEntityType.site => 'survey_sites',
      SyncEntityType.observation => 'observations',
    };

    final updatedRows = await databaseExecutor.update(
      tableName,
      {'sync_status': entityStatus.name},
      where: 'id = ?',
      whereArgs: [entityId],
    );

    if (updatedRows == 0) {
      developer.log(
        'Entity ${entityType.name}:$entityId does not exist locally. '
        'It may have been deleted.',
        name: 'EntitySyncStatusUpdater',
      );
    } else {
      developer.log(
        'Updated ${entityType.name}:$entityId '
        'to ${entityStatus.name}',
        name: 'EntitySyncStatusUpdater',
      );
    }

    return entityStatus;
  }

  SyncStatus _resolveStatus(Set<SyncQueueStatus> statuses) {
    if (statuses.contains(SyncQueueStatus.conflict)) {
      return SyncStatus.conflict;
    }

    if (statuses.contains(SyncQueueStatus.failed)) {
      return SyncStatus.failed;
    }

    if (statuses.contains(SyncQueueStatus.pending) ||
        statuses.contains(SyncQueueStatus.processing)) {
      return SyncStatus.pending;
    }

    return SyncStatus.synced;
  }
}
