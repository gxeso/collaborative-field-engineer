import 'package:flutter_test/flutter_test.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_service.dart';

void main() {
  group('WorkspaceRole.fromValue', () {
    test('parses supported workspace roles', () {
      expect(WorkspaceRole.fromValue('viewer'), WorkspaceRole.viewer);
      expect(WorkspaceRole.fromValue('editor'), WorkspaceRole.editor);
      expect(WorkspaceRole.fromValue('admin'), WorkspaceRole.admin);
    });

    test('rejects unknown roles', () {
      expect(WorkspaceRole.fromValue('owner'), isNull);
    });

    test('rejects non-string values', () {
      expect(WorkspaceRole.fromValue(1), isNull);
      expect(WorkspaceRole.fromValue(null), isNull);
    });
  });

  group('WorkspaceAccess', () {
    test('admin can read and synchronize', () {
      const access = WorkspaceAccess(
        workspaceId: 'juma-field-engineering',
        uid: 'admin-user',
        role: WorkspaceRole.admin,
      );

      expect(access.canRead, isTrue);
      expect(access.canSynchronize, isTrue);
    });

    test('editor has read-only access', () {
      const access = WorkspaceAccess(
        workspaceId: 'juma-field-engineering',
        uid: 'editor-user',
        role: WorkspaceRole.editor,
      );

      expect(access.canRead, isTrue);
      expect(access.canSynchronize, isFalse);
    });

    test('viewer has read-only access', () {
      const access = WorkspaceAccess(
        workspaceId: 'juma-field-engineering',
        uid: 'viewer-user',
        role: WorkspaceRole.viewer,
      );

      expect(access.canRead, isTrue);
      expect(access.canSynchronize, isFalse);
    });
  });
}
