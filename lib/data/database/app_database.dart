import 'dart:developer' as developer;

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

class AppDatabase {
  AppDatabase({String? databasePath}) : _customDatabasePath = databasePath;

  static const String databaseName = 'collaborative_field_engineer.db';

  final String? _customDatabasePath;

  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> get database async {
    final existingDatabase = _database;

    if (existingDatabase != null && existingDatabase.isOpen) {
      return existingDatabase;
    }

    final openingDatabase = _openingDatabase;

    if (openingDatabase != null) {
      return openingDatabase;
    }

    final future = _openDatabase();
    _openingDatabase = future;

    try {
      final openedDatabase = await future;
      _database = openedDatabase;

      return openedDatabase;
    } finally {
      _openingDatabase = null;
    }
  }

  Future<Database> _openDatabase() async {
    final resolvedDatabasePath =
        _customDatabasePath ?? await _defaultDatabasePath();

    developer.log(
      'Opening database at $resolvedDatabasePath',
      name: 'AppDatabase',
    );

    return openDatabase(
      resolvedDatabasePath,
      version: Migrations.currentVersion,
      onConfigure: _onConfigure,
      onCreate: Migrations.createDatabase,
      onUpgrade: Migrations.upgradeDatabase,
      onOpen: _onOpen,
    );
  }

  Future<String> _defaultDatabasePath() async {
    final databaseDirectory = await getDatabasesPath();

    return path.join(databaseDirectory, databaseName);
  }

  Future<void> _onConfigure(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onOpen(Database database) async {
    final result = await database.rawQuery('PRAGMA foreign_keys');

    final foreignKeysEnabled =
        result.isNotEmpty && result.first.values.first == 1;

    developer.log(
      'Database opened. Foreign keys enabled: '
      '$foreignKeysEnabled',
      name: 'AppDatabase',
    );
  }

  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) async {
    final currentDatabase = await database;

    return currentDatabase.transaction(action);
  }

  Future<void> close() async {
    final currentDatabase = _database;

    if (currentDatabase == null) {
      return;
    }

    if (currentDatabase.isOpen) {
      await currentDatabase.close();

      developer.log('Database closed', name: 'AppDatabase');
    }

    _database = null;
  }
}
