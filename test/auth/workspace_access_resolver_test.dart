import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_survey_and_sync_app/auth/cached_workspace_access.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_cache.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_resolution.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_resolver.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_service.dart';
import 'package:offline_survey_and_sync_app/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const workspaceId = 'juma-field-engineering';
  const userId = 'authorized-user';

  final verificationTime = DateTime.utc(2026, 10, 15, 10, 30);

  late AppDatabase appDatabase;
  late WorkspaceAccessCache cache;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    appDatabase = AppDatabase(databasePath: inMemoryDatabasePath);

    cache = WorkspaceAccessCache(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('online membership is returned and cached', () async {
    final remoteService = FakeWorkspaceAccessRemoteDataSource(
      workspaceId: workspaceId,
      response: const WorkspaceAccess(
        workspaceId: workspaceId,
        uid: userId,
        role: WorkspaceRole.admin,
      ),
    );

    final resolver = WorkspaceAccessResolver(
      remoteService: remoteService,
      cache: cache,
      clock: () => verificationTime,
    );

    final resolution = await resolver.resolve(userId);

    expect(resolution.status, WorkspaceAccessResolutionStatus.granted);

    expect(resolution.isOnlineVerified, isTrue);
    expect(resolution.isOfflineCached, isFalse);
    expect(resolution.access?.uid, userId);
    expect(resolution.access?.role, WorkspaceRole.admin);
    expect(resolution.verifiedAt, verificationTime);

    final cachedAccess = await cache.get(uid: userId, workspaceId: workspaceId);

    expect(cachedAccess, isNotNull);
    expect(cachedAccess?.uid, userId);
    expect(cachedAccess?.role, WorkspaceRole.admin);
    expect(cachedAccess?.verifiedAt, verificationTime);
  });

  test(
    'missing online membership removes cached access and denies entry',
    () async {
      await cache.save(
        CachedWorkspaceAccess(
          uid: userId,
          workspaceId: workspaceId,
          role: WorkspaceRole.admin,
          verifiedAt: verificationTime,
        ),
      );

      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        response: null,
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
      );

      final resolution = await resolver.resolve(userId);

      expect(resolution.status, WorkspaceAccessResolutionStatus.unauthorized);

      expect(resolution.isGranted, isFalse);
      expect(resolution.access, isNull);

      final cachedAccess = await cache.get(
        uid: userId,
        workspaceId: workspaceId,
      );

      expect(cachedAccess, isNull);
    },
  );

  test(
    'temporary Firebase failure uses matching cached authorization',
    () async {
      final cachedVerificationTime = DateTime.utc(2026, 10, 14, 8);

      await cache.save(
        CachedWorkspaceAccess(
          uid: userId,
          workspaceId: workspaceId,
          role: WorkspaceRole.editor,
          verifiedAt: cachedVerificationTime,
        ),
      );

      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        error: FirebaseException(
          plugin: 'firebase_database',
          code: 'unavailable',
          message: 'Firebase is temporarily unavailable.',
        ),
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
        clock: () => cachedVerificationTime.add(const Duration(hours: 1)),
      );

      final resolution = await resolver.resolve(userId);

      expect(resolution.status, WorkspaceAccessResolutionStatus.granted);

      expect(resolution.isOnlineVerified, isFalse);
      expect(resolution.isOfflineCached, isTrue);
      expect(resolution.access?.uid, userId);
      expect(resolution.access?.role, WorkspaceRole.editor);
      expect(resolution.verifiedAt, cachedVerificationTime);

      // Cached access permits local entry but must never be interpreted
      // as fresh online authorization.
      expect(resolution.isOnlineVerified, isFalse);
    },
  );

  test(
    'temporary Firebase failure without cache returns unavailable',
    () async {
      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        error: FirebaseException(
          plugin: 'firebase_database',
          code: 'network-error',
          message: 'No network connection.',
        ),
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
      );

      final resolution = await resolver.resolve(userId);

      expect(resolution.status, WorkspaceAccessResolutionStatus.unavailable);

      expect(resolution.isGranted, isFalse);
      expect(resolution.access, isNull);
      expect(resolution.error, isA<FirebaseException>());
    },
  );

  test('cached access belonging to another UID is not reused', () async {
    await cache.save(
      CachedWorkspaceAccess(
        uid: 'different-user',
        workspaceId: workspaceId,
        role: WorkspaceRole.admin,
        verifiedAt: verificationTime,
      ),
    );

    final remoteService = FakeWorkspaceAccessRemoteDataSource(
      workspaceId: workspaceId,
      error: FirebaseException(
        plugin: 'firebase_database',
        code: 'disconnected',
        message: 'The device is offline.',
      ),
    );

    final resolver = WorkspaceAccessResolver(
      remoteService: remoteService,
      cache: cache,
    );

    final resolution = await resolver.resolve(userId);

    expect(resolution.status, WorkspaceAccessResolutionStatus.unavailable);

    expect(resolution.isGranted, isFalse);
    expect(resolution.access, isNull);
  });

  test(
    'permission denied does not fall back to cached authorization',
    () async {
      await cache.save(
        CachedWorkspaceAccess(
          uid: userId,
          workspaceId: workspaceId,
          role: WorkspaceRole.admin,
          verifiedAt: verificationTime,
        ),
      );

      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        error: FirebaseException(
          plugin: 'firebase_database',
          code: 'permission-denied',
          message: 'Firebase rejected the request.',
        ),
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
      );

      expect(
        () => resolver.resolve(userId),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    },
  );

  test(
    'empty UID is rejected before remote or cached access is checked',
    () async {
      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        response: null,
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
      );

      expect(() => resolver.resolve('   '), throwsArgumentError);

      expect(remoteService.requestedUids, isEmpty);
    },
  );
  test('cached authorization younger than 24 hours is accepted', () async {
    final cachedAt = DateTime.utc(2026, 10, 20, 8);

    await cache.save(
      CachedWorkspaceAccess(
        uid: userId,
        workspaceId: workspaceId,
        role: WorkspaceRole.admin,
        verifiedAt: cachedAt,
      ),
    );

    final remoteService = FakeWorkspaceAccessRemoteDataSource(
      workspaceId: workspaceId,
      error: FirebaseException(
        plugin: 'firebase_database',
        code: 'unavailable',
        message: 'Firebase is unavailable.',
      ),
    );

    final resolver = WorkspaceAccessResolver(
      remoteService: remoteService,
      cache: cache,
      clock: () => cachedAt.add(const Duration(hours: 23, minutes: 59)),
    );

    final resolution = await resolver.resolve(userId);

    expect(resolution.status, WorkspaceAccessResolutionStatus.granted);
    expect(resolution.isOfflineCached, isTrue);
    expect(resolution.isOnlineVerified, isFalse);
    expect(resolution.access?.role, WorkspaceRole.admin);
  });

  test('cached authorization exactly 24 hours old is accepted', () async {
    final cachedAt = DateTime.utc(2026, 10, 20, 8);

    await cache.save(
      CachedWorkspaceAccess(
        uid: userId,
        workspaceId: workspaceId,
        role: WorkspaceRole.editor,
        verifiedAt: cachedAt,
      ),
    );

    final remoteService = FakeWorkspaceAccessRemoteDataSource(
      workspaceId: workspaceId,
      error: FirebaseException(
        plugin: 'firebase_database',
        code: 'network-error',
        message: 'No network connection.',
      ),
    );

    final resolver = WorkspaceAccessResolver(
      remoteService: remoteService,
      cache: cache,
      clock: () => cachedAt.add(const Duration(hours: 24)),
    );

    final resolution = await resolver.resolve(userId);

    expect(resolution.status, WorkspaceAccessResolutionStatus.granted);
    expect(resolution.isOfflineCached, isTrue);
    expect(resolution.access?.role, WorkspaceRole.editor);
    expect(resolution.verifiedAt, cachedAt);
  });

  test(
    'cached authorization older than 24 hours is denied and removed',
    () async {
      final cachedAt = DateTime.utc(2026, 10, 20, 8);

      await cache.save(
        CachedWorkspaceAccess(
          uid: userId,
          workspaceId: workspaceId,
          role: WorkspaceRole.admin,
          verifiedAt: cachedAt,
        ),
      );

      final remoteService = FakeWorkspaceAccessRemoteDataSource(
        workspaceId: workspaceId,
        error: FirebaseException(
          plugin: 'firebase_database',
          code: 'disconnected',
          message: 'The device is offline.',
        ),
      );

      final resolver = WorkspaceAccessResolver(
        remoteService: remoteService,
        cache: cache,
        clock: () => cachedAt.add(const Duration(hours: 24, milliseconds: 1)),
      );

      final resolution = await resolver.resolve(userId);

      expect(resolution.status, WorkspaceAccessResolutionStatus.unavailable);
      expect(resolution.isGranted, isFalse);
      expect(resolution.access, isNull);
      expect(
        resolution.error.toString(),
        contains('authorization has expired'),
      );

      final cachedAccess = await cache.get(
        uid: userId,
        workspaceId: workspaceId,
      );

      expect(cachedAccess, isNull);
    },
  );

  test('future cached verification timestamp is denied and removed', () async {
    final currentTime = DateTime.utc(2026, 10, 20, 8);
    final futureVerificationTime = currentTime.add(const Duration(minutes: 5));

    await cache.save(
      CachedWorkspaceAccess(
        uid: userId,
        workspaceId: workspaceId,
        role: WorkspaceRole.admin,
        verifiedAt: futureVerificationTime,
      ),
    );

    final remoteService = FakeWorkspaceAccessRemoteDataSource(
      workspaceId: workspaceId,
      error: FirebaseException(
        plugin: 'firebase_database',
        code: 'unavailable',
        message: 'Firebase is unavailable.',
      ),
    );

    final resolver = WorkspaceAccessResolver(
      remoteService: remoteService,
      cache: cache,
      clock: () => currentTime,
    );

    final resolution = await resolver.resolve(userId);

    expect(resolution.status, WorkspaceAccessResolutionStatus.unavailable);
    expect(resolution.isGranted, isFalse);
    expect(resolution.access, isNull);
    expect(
      resolution.error.toString(),
      contains('future verification timestamp'),
    );

    final cachedAccess = await cache.get(uid: userId, workspaceId: workspaceId);

    expect(cachedAccess, isNull);
  });
}

class FakeWorkspaceAccessRemoteDataSource
    implements WorkspaceAccessRemoteDataSource {
  FakeWorkspaceAccessRemoteDataSource({
    required this.workspaceId,
    this.response,
    this.error,
  });

  @override
  final String workspaceId;

  final WorkspaceAccess? response;
  final FirebaseException? error;

  final List<String> requestedUids = <String>[];

  @override
  Future<WorkspaceAccess?> getAccessForUser(String uid) async {
    requestedUids.add(uid);

    final remoteError = error;

    if (remoteError != null) {
      throw remoteError;
    }

    return response;
  }
}
