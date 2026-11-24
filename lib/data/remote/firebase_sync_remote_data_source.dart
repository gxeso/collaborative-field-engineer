import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/sync_operation.dart';
import 'sync_remote_data_source.dart';
import 'sync_remote_exception.dart';

class FirebaseSyncRemoteDataSource implements SyncRemoteDataSource {
  FirebaseSyncRemoteDataSource({
    required String workspaceId,
    FirebaseDatabase? database,
    DateTime Function()? clock,
  }) : _workspaceId = _validateWorkspaceId(workspaceId),
       _database = database ?? FirebaseDatabase.instance,
       _clock = clock ?? DateTime.now;

  final String _workspaceId;
  final FirebaseDatabase _database;
  final DateTime Function() _clock;

  DatabaseReference get _workspaceReference =>
      _database.ref('workspaces/$_workspaceId');

  @override
  Future<void> uploadOperation(SyncOperation operation) async {
    Map<String, dynamic>? conflictingPayload;

    try {
      final result = await _workspaceReference.runTransaction((currentValue) {
        final workspace = _asStringMap(currentValue);
        final processedOperations = _asStringMap(
          workspace['processedOperations'],
        );

        // The operation already reached Firebase during a previous attempt.
        // Treat the retry as successful without applying it twice.
        if (processedOperations.containsKey(operation.operationId)) {
          return Transaction.success(workspace);
        }

        final collectionName = _collectionFor(operation.entityType);
        final collection = _asStringMap(workspace[collectionName]);
        final existingEntity = _nullableStringMap(
          collection[operation.entityId],
        );

        if (operation.operationType == SyncOperationType.create &&
            existingEntity != null) {
          conflictingPayload = existingEntity;
          return Transaction.abort();
        }

        switch (operation.operationType) {
          case SyncOperationType.create:
          case SyncOperationType.update:
            collection[operation.entityId] = _preparePayload(operation);

          case SyncOperationType.delete:
            collection.remove(operation.entityId);
        }

        processedOperations[operation.operationId] = {
          'operationId': operation.operationId,
          'entityType': operation.entityType.name,
          'entityId': operation.entityId,
          'operationType': operation.operationType.name,
          'processedAt': _clock().toUtc().toIso8601String(),
        };

        workspace[collectionName] = collection;
        workspace['processedOperations'] = processedOperations;

        return Transaction.success(workspace);
      }, applyLocally: false);

      if (!result.committed) {
        if (conflictingPayload != null) {
          throw SyncConflictException(
            '${operation.entityType.name} ${operation.entityId} '
            'already exists remotely.',
            remotePayload: conflictingPayload,
          );
        }

        throw const TemporarySyncException(
          'Firebase transaction was not committed.',
        );
      }
    } on SyncRemoteException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseException(error);
    } catch (error) {
      throw PermanentSyncException(
        'Failed to prepare Firebase operation: $error',
      );
    }
  }

  String _collectionFor(SyncEntityType entityType) {
    return switch (entityType) {
      SyncEntityType.site => 'surveySites',
      SyncEntityType.observation => 'observations',
    };
  }

  Map<String, dynamic> _preparePayload(SyncOperation operation) {
    final payload = _sanitizeMap(operation.payload);

    payload['id'] = operation.entityId;
    payload['lastOperationId'] = operation.operationId;
    payload['remoteUpdatedAt'] = _clock().toUtc().toIso8601String();

    return payload;
  }

  SyncRemoteException _mapFirebaseException(FirebaseException error) {
    final message = error.message ?? error.code;

    switch (error.code.toLowerCase()) {
      case 'disconnected':
      case 'network-error':
      case 'unavailable':
      case 'timeout':
      case 'too-many-requests':
        return TemporarySyncException('Temporary Firebase error: $message');

      case 'permission-denied':
      case 'unauthorized':
        return PermanentSyncException(
          'Firebase rejected the operation: $message',
        );

      default:
        return PermanentSyncException(
          'Firebase operation failed (${error.code}): $message',
        );
    }
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> source) {
    return source.map((key, value) => MapEntry(key, _sanitizeValue(value)));
  }

  Object? _sanitizeValue(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _sanitizeValue(nestedValue)),
      );
    }

    if (value is Iterable) {
      return value.map(_sanitizeValue).toList(growable: false);
    }

    throw FormatException(
      'Unsupported Firebase value type: ${value.runtimeType}',
    );
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }

    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }

  Map<String, dynamic>? _nullableStringMap(Object? value) {
    if (value is! Map) {
      return null;
    }

    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }

  static String _validateWorkspaceId(String workspaceId) {
    final trimmedWorkspaceId = workspaceId.trim();

    if (trimmedWorkspaceId.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'Workspace ID cannot be empty.',
      );
    }

    final containsForbiddenCharacter = RegExp(
      r'[.#$\[\]/]',
    ).hasMatch(trimmedWorkspaceId);

    if (containsForbiddenCharacter) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'Workspace ID contains a forbidden Firebase key character.',
      );
    }

    return trimmedWorkspaceId;
  }
}
