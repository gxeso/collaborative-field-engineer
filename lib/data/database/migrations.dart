import 'package:sqflite/sqflite.dart';

class Migrations {
  const Migrations._();

  static const int currentVersion = 3;

  static Future<void> createDatabase(Database database, int version) async {
    await _createCoreTables(database);
    await _createMetadataTable(database);
    await _createWorkspaceAccessCacheTable(database);
  }

  static Future<void> upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _upgradeFromVersionOneToVersionTwo(database);
    }

    if (oldVersion < 3) {
      await _upgradeFromVersionTwoToVersionThree(database);
    }
  }

  static Future<void> _createCoreTables(Database database) async {
    final batch = database.batch();

    batch.execute('''
      CREATE TABLE survey_sites (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        region_geojson TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version_vector TEXT NOT NULL DEFAULT '{}',
        sync_status TEXT NOT NULL DEFAULT 'pending'
          CHECK (
            sync_status IN (
              'pending',
              'synced',
              'conflict',
              'failed'
            )
          )
      )
    ''');

    batch.execute('''
      CREATE TABLE observations (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        temperature REAL,
        humidity REAL,
        pm25 REAL,
        notes TEXT,
        photo_path TEXT,
        weather_data TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version_vector TEXT NOT NULL DEFAULT '{}',
        field_modified_at TEXT NOT NULL DEFAULT '{}',
        sync_status TEXT NOT NULL DEFAULT 'pending'
          CHECK (
            sync_status IN (
              'pending',
              'synced',
              'conflict',
              'failed'
            )
          ),
        FOREIGN KEY (site_id)
          REFERENCES survey_sites (id)
          ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL
          CHECK (
            entity_type IN (
              'site',
              'observation'
            )
          ),
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL
          CHECK (
            operation IN (
              'CREATE',
              'UPDATE',
              'DELETE'
            )
          ),
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK (
            status IN (
              'pending',
              'processing',
              'synced',
              'failed',
              'conflict'
            )
          ),
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempt TEXT,
        next_retry_at TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_observations_site
      ON observations (site_id)
    ''');

    batch.execute('''
      CREATE INDEX idx_sites_sync_status
      ON survey_sites (sync_status)
    ''');

    batch.execute('''
      CREATE INDEX idx_observations_sync_status
      ON observations (sync_status)
    ''');

    batch.execute('''
      CREATE INDEX idx_sync_queue_processing
      ON sync_queue (
        status,
        next_retry_at,
        created_at
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_sync_queue_entity
      ON sync_queue (
        entity_type,
        entity_id
      )
    ''');

    await batch.commit(noResult: true);
  }

  static Future<void> _createMetadataTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgradeFromVersionOneToVersionTwo(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE survey_sites_v2 (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        region_geojson TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version_vector TEXT NOT NULL DEFAULT '{}',
        sync_status TEXT NOT NULL DEFAULT 'pending'
          CHECK (
            sync_status IN (
              'pending',
              'synced',
              'conflict',
              'failed'
            )
          )
      )
    ''');

    await database.execute('''
      CREATE TABLE observations_v2 (
        id TEXT PRIMARY KEY,
        site_id TEXT NOT NULL,
        temperature REAL,
        humidity REAL,
        pm25 REAL,
        notes TEXT,
        photo_path TEXT,
        weather_data TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version_vector TEXT NOT NULL DEFAULT '{}',
        field_modified_at TEXT NOT NULL DEFAULT '{}',
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (site_id)
          REFERENCES survey_sites_v2 (id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      INSERT INTO survey_sites_v2 (
        id,
        name,
        latitude,
        longitude,
        region_geojson,
        created_at,
        updated_at,
        version_vector,
        sync_status
      )
      SELECT
        id,
        name,
        latitude,
        longitude,
        region_geojson,
        created_at,
        updated_at,
        version_vector,
        sync_status
      FROM survey_sites
    ''');

    await database.execute('''
      INSERT INTO observations_v2 (
        id,
        site_id,
        temperature,
        humidity,
        pm25,
        notes,
        photo_path,
        weather_data,
        created_at,
        updated_at,
        version_vector,
        field_modified_at,
        sync_status
      )
      SELECT
        id,
        site_id,
        temperature,
        humidity,
        pm25,
        notes,
        photo_path,
        weather_data,
        created_at,
        updated_at,
        version_vector,
        field_modified_at,
        sync_status
      FROM observations
    ''');

    await database.execute('DROP TABLE observations');

    await database.execute('DROP TABLE survey_sites');

    await database.execute(
      'ALTER TABLE survey_sites_v2 RENAME TO survey_sites',
    );

    await database.execute(
      'ALTER TABLE observations_v2 RENAME TO observations',
    );

    await database.execute('''
      CREATE INDEX idx_observations_site
      ON observations (site_id)
    ''');

    await database.execute('''
      CREATE INDEX idx_sites_sync_status
      ON survey_sites (sync_status)
    ''');

    await database.execute('''
      CREATE INDEX idx_observations_sync_status
      ON observations (sync_status)
    ''');

    await _createMetadataTable(database);
  }

  static Future<void> _createWorkspaceAccessCacheTable(
    Database database,
  ) async {
    await database.execute('''
    CREATE TABLE IF NOT EXISTS cached_workspace_access (
      uid TEXT NOT NULL,
      workspace_id TEXT NOT NULL,
      role TEXT NOT NULL
        CHECK (
          role IN (
            'viewer',
            'editor',
            'admin'
          )
        ),
      verified_at TEXT NOT NULL,
      PRIMARY KEY (
        uid,
        workspace_id
      )
    )
  ''');
  }

  static Future<void> _upgradeFromVersionTwoToVersionThree(
    Database database,
  ) async {
    await _createWorkspaceAccessCacheTable(database);
  }
}
