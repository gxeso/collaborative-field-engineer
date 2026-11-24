import 'dart:developer' as developer;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class ReplicaIdentityService {
  ReplicaIdentityService({
    required AppDatabase appDatabase,
    Uuid uuid = const Uuid(),
  }) : _appDatabase = appDatabase,
       _uuid = uuid;

  static const String _actorIdKey = 'actor_id';

  final AppDatabase _appDatabase;
  final Uuid _uuid;

  Future<String> getActorId() async {
    return _appDatabase.runTransaction((transaction) async {
      final rows = await transaction.query(
        'app_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [_actorIdKey],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final existingActorId = rows.first['value'] as String;

        if (existingActorId.trim().isNotEmpty) {
          developer.log(
            'Reusing actor ID $existingActorId',
            name: 'ReplicaIdentityService',
          );

          return existingActorId;
        }
      }

      final newActorId = _uuid.v4();

      await transaction.insert('app_metadata', {
        'key': _actorIdKey,
        'value': newActorId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      developer.log(
        'Created actor ID $newActorId',
        name: 'ReplicaIdentityService',
      );

      return newActorId;
    });
  }
}
