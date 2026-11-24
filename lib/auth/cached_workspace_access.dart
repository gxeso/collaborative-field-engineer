import 'workspace_access_service.dart';

class CachedWorkspaceAccess {
  const CachedWorkspaceAccess({
    required this.uid,
    required this.workspaceId,
    required this.role,
    required this.verifiedAt,
  });

  final String uid;
  final String workspaceId;
  final WorkspaceRole role;
  final DateTime verifiedAt;

  WorkspaceAccess get access {
    return WorkspaceAccess(workspaceId: workspaceId, uid: uid, role: role);
  }

  CachedWorkspaceAccess copyWith({
    String? uid,
    String? workspaceId,
    WorkspaceRole? role,
    DateTime? verifiedAt,
  }) {
    return CachedWorkspaceAccess(
      uid: uid ?? this.uid,
      workspaceId: workspaceId ?? this.workspaceId,
      role: role ?? this.role,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'uid': uid,
      'workspace_id': workspaceId,
      'role': role.name,
      'verified_at': verifiedAt.toUtc().toIso8601String(),
    };
  }

  factory CachedWorkspaceAccess.fromMap(Map<String, Object?> map) {
    final uid = map['uid'];
    final workspaceId = map['workspace_id'];
    final role = WorkspaceRole.fromValue(map['role']);
    final verifiedAt = map['verified_at'];

    if (uid is! String || uid.trim().isEmpty) {
      throw const FormatException(
        'Cached workspace access has an invalid UID.',
      );
    }

    if (workspaceId is! String || workspaceId.trim().isEmpty) {
      throw const FormatException(
        'Cached workspace access has an invalid workspace ID.',
      );
    }

    if (role == null) {
      throw const FormatException(
        'Cached workspace access has an invalid role.',
      );
    }

    if (verifiedAt is! String || verifiedAt.trim().isEmpty) {
      throw const FormatException(
        'Cached workspace access has an invalid verification time.',
      );
    }

    return CachedWorkspaceAccess(
      uid: uid,
      workspaceId: workspaceId,
      role: role,
      verifiedAt: DateTime.parse(verifiedAt).toUtc(),
    );
  }
}
