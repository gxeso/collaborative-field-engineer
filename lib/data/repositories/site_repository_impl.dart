import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/sync_status.dart';
import '../database/app_database.dart';
import '../models/survey_site.dart';
import '../models/sync_operation.dart';
import '../services/replica_identity_service.dart';
import '../sync/sync_queue.dart';
import 'site_repository.dart';

class SiteRepositoryImpl implements SiteRepository {
  SiteRepositoryImpl({
    required AppDatabase appDatabase,
    required SyncQueue syncQueue,
    required ReplicaIdentityService identityService,
    Uuid uuid = const Uuid(),
  }) : _appDatabase = appDatabase,
       _syncQueue = syncQueue,
       _identityService = identityService,
       _uuid = uuid;

  final AppDatabase _appDatabase;
  final SyncQueue _syncQueue;
  final ReplicaIdentityService _identityService;
  final Uuid _uuid;

  @override
  Future<List<SurveySite>> getSites() async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'survey_sites',
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(SurveySite.fromMap).toList(growable: false);
  }

  @override
  Future<SurveySite?> getSiteById(String id) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'survey_sites',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return SurveySite.fromMap(rows.first);
  }

  @override
  Future<void> addSite(SurveySite site) async {
    final actorId = await _identityService.getActorId();
    final now = DateTime.now().toUtc();

    final siteToSave = site.copyWith(
      updatedAt: now,
      versionVector: site.versionVector.increment(actorId),
      syncStatus: SyncStatus.pending,
    );

    await _appDatabase.runTransaction((transaction) async {
      await transaction.insert(
        'survey_sites',
        siteToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.site,
          entityId: siteToSave.id,
          operationType: SyncOperationType.create,
          payload: siteToSave.toRemoteJson(),
          createdAt: now,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Created site ${siteToSave.id}, incremented '
      'actor $actorId and queued CREATE',
      name: 'SiteRepository',
    );
  }

  @override
  Future<void> updateSite(SurveySite site) async {
    final actorId = await _identityService.getActorId();
    final now = DateTime.now().toUtc();

    await _appDatabase.runTransaction((transaction) async {
      final existingRows = await transaction.query(
        'survey_sites',
        where: 'id = ?',
        whereArgs: [site.id],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        throw StateError('Cannot update site ${site.id}: site not found.');
      }

      final existingSite = SurveySite.fromMap(existingRows.first);

      final siteToSave = site.copyWith(
        createdAt: existingSite.createdAt,
        updatedAt: now,
        versionVector: existingSite.versionVector.increment(actorId),
        syncStatus: SyncStatus.pending,
      );

      final updatedRows = await transaction.update(
        'survey_sites',
        siteToSave.toMap(),
        where: 'id = ?',
        whereArgs: [siteToSave.id],
      );

      if (updatedRows == 0) {
        throw StateError('Cannot update site ${site.id}: site not found.');
      }

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.site,
          entityId: siteToSave.id,
          operationType: SyncOperationType.update,
          payload: siteToSave.toRemoteJson(),
          createdAt: now,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Updated site ${site.id}, incremented '
      'actor $actorId and queued UPDATE',
      name: 'SiteRepository',
    );
  }

  @override
  Future<void> deleteSite(String id) async {
    final actorId = await _identityService.getActorId();
    final deletionTime = DateTime.now().toUtc();

    await _appDatabase.runTransaction((transaction) async {
      final rows = await transaction.query(
        'survey_sites',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Cannot delete site $id: site not found.');
      }

      final existingSite = SurveySite.fromMap(rows.first);

      final deletionVersionVector = existingSite.versionVector.increment(
        actorId,
      );

      final deletedRows = await transaction.delete(
        'survey_sites',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (deletedRows == 0) {
        throw StateError('Failed to delete site $id.');
      }

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.site,
          entityId: id,
          operationType: SyncOperationType.delete,
          payload: {
            'id': id,
            'deletedAt': deletionTime.toIso8601String(),
            'versionVector': deletionVersionVector.toJson(),
          },
          createdAt: deletionTime,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Deleted site $id, incremented actor '
      '$actorId and queued DELETE',
      name: 'SiteRepository',
    );
  }
}
