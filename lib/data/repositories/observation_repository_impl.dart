import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/sync_status.dart';
import '../database/app_database.dart';
import '../models/observation.dart';
import '../models/sync_operation.dart';
import '../services/replica_identity_service.dart';
import '../sync/sync_queue.dart';
import 'observation_repository.dart';

class ObservationRepositoryImpl implements ObservationRepository {
  ObservationRepositoryImpl({
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
  Future<List<Observation>> getObservations(String siteId) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'observations',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'created_at DESC',
    );

    return rows.map(Observation.fromMap).toList(growable: false);
  }

  @override
  Future<Observation?> getObservationById(String id) async {
    final database = await _appDatabase.database;

    final rows = await database.query(
      'observations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Observation.fromMap(rows.first);
  }

  @override
  Future<void> addObservation(Observation observation) async {
    final actorId = await _identityService.getActorId();

    final now = DateTime.now().toUtc();

    final observationToSave = observation.copyWith(
      updatedAt: now,
      versionVector: observation.versionVector.increment(actorId),
      fieldModifiedAt: _creationFieldTimestamps(now),
      syncStatus: SyncStatus.pending,
    );

    await _appDatabase.runTransaction((transaction) async {
      await transaction.insert(
        'observations',
        observationToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.observation,
          entityId: observationToSave.id,
          operationType: SyncOperationType.create,
          payload: observationToSave.toRemoteJson(),
          createdAt: now,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Created observation '
      '${observationToSave.id}, incremented actor '
      '$actorId and queued CREATE',
      name: 'ObservationRepository',
    );
  }

  @override
  Future<void> updateObservation(Observation observation) async {
    final actorId = await _identityService.getActorId();

    final now = DateTime.now().toUtc();

    await _appDatabase.runTransaction((transaction) async {
      final existingRows = await transaction.query(
        'observations',
        where: 'id = ?',
        whereArgs: [observation.id],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        throw StateError(
          'Cannot update observation '
          '${observation.id}: observation not found.',
        );
      }

      final existingObservation = Observation.fromMap(existingRows.first);

      final updatedFieldTimestamps = _updatedFieldTimestamps(
        existing: existingObservation,
        incoming: observation,
        modifiedAt: now,
      );

      final observationToSave = observation.copyWith(
        siteId: existingObservation.siteId,
        createdAt: existingObservation.createdAt,
        updatedAt: now,
        versionVector: existingObservation.versionVector.increment(actorId),
        fieldModifiedAt: updatedFieldTimestamps,
        syncStatus: SyncStatus.pending,
      );

      final updatedRows = await transaction.update(
        'observations',
        observationToSave.toMap(),
        where: 'id = ?',
        whereArgs: [observationToSave.id],
      );

      if (updatedRows == 0) {
        throw StateError(
          'Cannot update observation '
          '${observation.id}: observation not found.',
        );
      }

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.observation,
          entityId: observationToSave.id,
          operationType: SyncOperationType.update,
          payload: observationToSave.toRemoteJson(),
          createdAt: now,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Updated observation ${observation.id}, '
      'incremented actor $actorId and queued UPDATE',
      name: 'ObservationRepository',
    );
  }

  @override
  Future<void> deleteObservation(String id) async {
    final actorId = await _identityService.getActorId();

    final deletionTime = DateTime.now().toUtc();

    await _appDatabase.runTransaction((transaction) async {
      final rows = await transaction.query(
        'observations',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError(
          'Cannot delete observation $id: '
          'observation not found.',
        );
      }

      final existingObservation = Observation.fromMap(rows.first);

      final deletionVersionVector = existingObservation.versionVector.increment(
        actorId,
      );

      final deletedRows = await transaction.delete(
        'observations',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (deletedRows == 0) {
        throw StateError('Failed to delete observation $id.');
      }

      await _syncQueue.enqueue(
        SyncOperation(
          operationId: _uuid.v4(),
          entityType: SyncEntityType.observation,
          entityId: id,
          operationType: SyncOperationType.delete,
          payload: {
            'id': id,
            'siteId': existingObservation.siteId,
            'deletedAt': deletionTime.toIso8601String(),
            'versionVector': deletionVersionVector.toJson(),
          },
          createdAt: deletionTime,
        ),
        executor: transaction,
      );
    });

    developer.log(
      'Deleted observation $id, incremented actor '
      '$actorId and queued DELETE',
      name: 'ObservationRepository',
    );
  }

  Map<String, DateTime> _creationFieldTimestamps(DateTime createdAt) {
    return {
      'temperature': createdAt,
      'humidity': createdAt,
      'pm25': createdAt,
      'notes': createdAt,
      'photoPath': createdAt,
      'weatherData': createdAt,
    };
  }

  Map<String, DateTime> _updatedFieldTimestamps({
    required Observation existing,
    required Observation incoming,
    required DateTime modifiedAt,
  }) {
    final timestamps = Map<String, DateTime>.from(existing.fieldModifiedAt);

    if (existing.temperature != incoming.temperature) {
      timestamps['temperature'] = modifiedAt;
    }

    if (existing.humidity != incoming.humidity) {
      timestamps['humidity'] = modifiedAt;
    }

    if (existing.pm25 != incoming.pm25) {
      timestamps['pm25'] = modifiedAt;
    }

    if (existing.notes != incoming.notes) {
      timestamps['notes'] = modifiedAt;
    }

    if (existing.photoPath != incoming.photoPath) {
      timestamps['photoPath'] = modifiedAt;
    }

    if (!_jsonValuesEqual(existing.weatherData, incoming.weatherData)) {
      timestamps['weatherData'] = modifiedAt;
    }

    return timestamps;
  }

  bool _jsonValuesEqual(Object? first, Object? second) {
    if (identical(first, second)) {
      return true;
    }

    if (first is Map && second is Map) {
      if (first.length != second.length) {
        return false;
      }

      for (final entry in first.entries) {
        if (!second.containsKey(entry.key)) {
          return false;
        }

        if (!_jsonValuesEqual(entry.value, second[entry.key])) {
          return false;
        }
      }

      return true;
    }

    if (first is List && second is List) {
      if (first.length != second.length) {
        return false;
      }

      for (var index = 0; index < first.length; index++) {
        if (!_jsonValuesEqual(first[index], second[index])) {
          return false;
        }
      }

      return true;
    }

    return first == second;
  }
}
