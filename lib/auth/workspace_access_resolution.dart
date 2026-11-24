import 'workspace_access_service.dart';

enum WorkspaceAccessSource { remote, cache }

enum WorkspaceAccessResolutionStatus { granted, unauthorized, unavailable }

class WorkspaceAccessResolution {
  const WorkspaceAccessResolution._({
    required this.status,
    this.access,
    this.source,
    this.verifiedAt,
    this.error,
  });

  final WorkspaceAccessResolutionStatus status;
  final WorkspaceAccess? access;
  final WorkspaceAccessSource? source;
  final DateTime? verifiedAt;
  final Object? error;

  bool get isGranted => status == WorkspaceAccessResolutionStatus.granted;

  bool get isOnlineVerified =>
      isGranted && source == WorkspaceAccessSource.remote;

  bool get isOfflineCached =>
      isGranted && source == WorkspaceAccessSource.cache;

  factory WorkspaceAccessResolution.online({
    required WorkspaceAccess access,
    required DateTime verifiedAt,
  }) {
    return WorkspaceAccessResolution._(
      status: WorkspaceAccessResolutionStatus.granted,
      access: access,
      source: WorkspaceAccessSource.remote,
      verifiedAt: verifiedAt.toUtc(),
    );
  }

  factory WorkspaceAccessResolution.offline({
    required WorkspaceAccess access,
    required DateTime verifiedAt,
    Object? error,
  }) {
    return WorkspaceAccessResolution._(
      status: WorkspaceAccessResolutionStatus.granted,
      access: access,
      source: WorkspaceAccessSource.cache,
      verifiedAt: verifiedAt.toUtc(),
      error: error,
    );
  }

  factory WorkspaceAccessResolution.unauthorized() {
    return const WorkspaceAccessResolution._(
      status: WorkspaceAccessResolutionStatus.unauthorized,
    );
  }

  factory WorkspaceAccessResolution.unavailable({Object? error}) {
    return WorkspaceAccessResolution._(
      status: WorkspaceAccessResolutionStatus.unavailable,
      error: error,
    );
  }
}
