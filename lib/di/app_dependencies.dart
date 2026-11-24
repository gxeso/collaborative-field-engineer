import '../auth/auth_service.dart';
import '../auth/sync_authorization_guard.dart';
import '../auth/workspace_access_cache.dart';
import '../auth/workspace_access_resolver.dart';
import '../auth/workspace_access_service.dart';
import '../data/database/app_database.dart';
import '../data/remote/firebase_sync_remote_data_source.dart';
import '../data/remote/sync_remote_data_source.dart';
import '../data/repositories/observation_repository.dart';
import '../data/repositories/observation_repository_impl.dart';
import '../data/repositories/site_repository.dart';
import '../data/repositories/site_repository_impl.dart';
import '../data/services/replica_identity_service.dart';
import '../data/sync/automatic_sync_coordinator.dart';
import '../data/sync/entity_sync_status_updater.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_queue.dart';

class AppDependencies {
  AppDependencies._({
    required this.authService,
    required this.workspaceAccessService,
    required this.workspaceAccessCache,
    required this.workspaceAccessResolver,
    required this.syncAuthorizationGuard,
    required this.appDatabase,
    required this.replicaIdentityService,
    required this.syncQueue,
    required this.siteRepository,
    required this.observationRepository,
    required this.entitySyncStatusUpdater,
    required this.syncRemoteDataSource,
    required this.syncEngine,
    required this.automaticSyncCoordinator,
  });

  static const String workspaceId = 'juma-field-engineering';

  final AuthService authService;
  final WorkspaceAccessService workspaceAccessService;
  final WorkspaceAccessCache workspaceAccessCache;
  final WorkspaceAccessResolver workspaceAccessResolver;
  final SyncAuthorizationGuard syncAuthorizationGuard;

  final AppDatabase appDatabase;
  final ReplicaIdentityService replicaIdentityService;
  final SyncQueue syncQueue;

  final SiteRepository siteRepository;
  final ObservationRepository observationRepository;

  final EntitySyncStatusUpdater entitySyncStatusUpdater;
  final SyncRemoteDataSource syncRemoteDataSource;
  final SyncEngine syncEngine;
  final AutomaticSyncCoordinator automaticSyncCoordinator;

  factory AppDependencies.create() {
    final authService = AuthService();
    final appDatabase = AppDatabase();

    final workspaceAccessService = WorkspaceAccessService(
      workspaceId: workspaceId,
    );

    final workspaceAccessCache = WorkspaceAccessCache(appDatabase);

    final workspaceAccessResolver = WorkspaceAccessResolver(
      remoteService: workspaceAccessService,
      cache: workspaceAccessCache,
    );

    final syncAuthorizationGuard = SyncAuthorizationGuard(
      currentUid: () => authService.currentUser?.uid,
      resolveAccess: workspaceAccessResolver.resolve,
    );

    final replicaIdentityService = ReplicaIdentityService(
      appDatabase: appDatabase,
    );

    final syncQueue = SyncQueue(appDatabase);

    final siteRepository = SiteRepositoryImpl(
      appDatabase: appDatabase,
      syncQueue: syncQueue,
      identityService: replicaIdentityService,
    );

    final observationRepository = ObservationRepositoryImpl(
      appDatabase: appDatabase,
      syncQueue: syncQueue,
      identityService: replicaIdentityService,
    );

    final entitySyncStatusUpdater = EntitySyncStatusUpdater(appDatabase);

    final SyncRemoteDataSource syncRemoteDataSource =
        FirebaseSyncRemoteDataSource(workspaceId: workspaceId);

    final syncEngine = SyncEngine(
      syncQueue: syncQueue,
      remoteDataSource: syncRemoteDataSource,
      entityStatusUpdater: entitySyncStatusUpdater,
    );

    final automaticSyncCoordinator = AutomaticSyncCoordinator(
      syncEngine: syncEngine,
      authorizationGuard: syncAuthorizationGuard,
    );

    return AppDependencies._(
      authService: authService,
      workspaceAccessService: workspaceAccessService,
      workspaceAccessCache: workspaceAccessCache,
      workspaceAccessResolver: workspaceAccessResolver,
      syncAuthorizationGuard: syncAuthorizationGuard,
      appDatabase: appDatabase,
      replicaIdentityService: replicaIdentityService,
      syncQueue: syncQueue,
      siteRepository: siteRepository,
      observationRepository: observationRepository,
      entitySyncStatusUpdater: entitySyncStatusUpdater,
      syncRemoteDataSource: syncRemoteDataSource,
      syncEngine: syncEngine,
      automaticSyncCoordinator: automaticSyncCoordinator,
    );
  }
}
