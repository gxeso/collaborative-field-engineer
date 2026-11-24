import 'package:firebase_database/firebase_database.dart';

enum WorkspaceRole {
  viewer,
  editor,
  admin;

  static WorkspaceRole? fromValue(Object? value) {
    if (value is! String) {
      return null;
    }

    for (final role in WorkspaceRole.values) {
      if (role.name == value) {
        return role;
      }
    }

    return null;
  }
}

class WorkspaceAccess {
  const WorkspaceAccess({
    required this.workspaceId,
    required this.uid,
    required this.role,
  });

  final String workspaceId;
  final String uid;
  final WorkspaceRole role;

  bool get canRead => true;

  bool get canSynchronize => role == WorkspaceRole.admin;
}

abstract interface class WorkspaceAccessRemoteDataSource {
  String get workspaceId;

  Future<WorkspaceAccess?> getAccessForUser(String uid);
}

class WorkspaceAccessService implements WorkspaceAccessRemoteDataSource {
  WorkspaceAccessService({
    FirebaseDatabase? database,
    this.workspaceId = 'juma-field-engineering',
  }) : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  @override
  final String workspaceId;

  @override
  Future<WorkspaceAccess?> getAccessForUser(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(
        uid,
        'uid',
        'The Firebase user ID cannot be empty.',
      );
    }

    final snapshot = await _database
        .ref('workspaceMembers')
        .child(workspaceId)
        .child(normalizedUid)
        .child('role')
        .get();

    if (!snapshot.exists) {
      return null;
    }

    final role = WorkspaceRole.fromValue(snapshot.value);

    if (role == null) {
      return null;
    }

    return WorkspaceAccess(
      workspaceId: workspaceId,
      uid: normalizedUid,
      role: role,
    );
  }
}
