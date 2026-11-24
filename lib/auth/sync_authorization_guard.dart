import 'workspace_access_resolution.dart';
import 'workspace_access_service.dart';

typedef WorkspaceAccessResolverCallback =
    Future<WorkspaceAccessResolution> Function(String uid);

enum SyncAuthorizationFailure {
  unauthenticated,
  unauthorized,
  unavailable,
  onlineRevalidationRequired,
  insufficientRole,
}

class SyncAuthorizationException implements Exception {
  const SyncAuthorizationException(this.failure, this.message);

  final SyncAuthorizationFailure failure;
  final String message;

  @override
  String toString() => message;
}

class SyncAuthorizationGuard {
  SyncAuthorizationGuard({
    required String? Function() currentUid,
    required WorkspaceAccessResolverCallback resolveAccess,
  }) : _currentUid = currentUid,
       _resolveAccess = resolveAccess;

  final String? Function() _currentUid;
  final WorkspaceAccessResolverCallback _resolveAccess;

  Future<WorkspaceAccess> requireAuthorizedAdmin() async {
    final uid = _currentUid()?.trim();

    if (uid == null || uid.isEmpty) {
      throw const SyncAuthorizationException(
        SyncAuthorizationFailure.unauthenticated,
        'Synchronization requires an authenticated user.',
      );
    }

    final resolution = await _resolveAccess(uid);

    if (!resolution.isGranted) {
      switch (resolution.status) {
        case WorkspaceAccessResolutionStatus.unauthorized:
          throw const SyncAuthorizationException(
            SyncAuthorizationFailure.unauthorized,
            'The current user is no longer authorized for this workspace.',
          );

        case WorkspaceAccessResolutionStatus.unavailable:
          throw const SyncAuthorizationException(
            SyncAuthorizationFailure.unavailable,
            'Workspace membership could not be verified online. '
            'Pending operations remain stored locally.',
          );

        case WorkspaceAccessResolutionStatus.granted:
          break;
      }
    }

    final access = resolution.access;

    if (access == null) {
      throw const SyncAuthorizationException(
        SyncAuthorizationFailure.unauthorized,
        'Workspace authorization details are unavailable.',
      );
    }

    if (!resolution.isOnlineVerified) {
      throw const SyncAuthorizationException(
        SyncAuthorizationFailure.onlineRevalidationRequired,
        'Synchronization is locked until workspace membership '
        'is revalidated online.',
      );
    }

    if (!access.canSynchronize) {
      throw SyncAuthorizationException(
        SyncAuthorizationFailure.insufficientRole,
        'The ${access.role.name} role cannot synchronize workspace data.',
      );
    }

    return access;
  }
}
