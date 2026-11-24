import 'package:flutter_test/flutter_test.dart';
import 'package:offline_survey_and_sync_app/auth/sync_authorization_guard.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_resolution.dart';
import 'package:offline_survey_and_sync_app/auth/workspace_access_service.dart';

void main() {
  const workspaceId = 'juma-field-engineering';
  const uid = 'authorized-user';

  final verifiedAt = DateTime.utc(2026, 10, 19, 5);

  WorkspaceAccess accessFor(WorkspaceRole role) {
    return WorkspaceAccess(workspaceId: workspaceId, uid: uid, role: role);
  }

  test('allows synchronization for an online-verified admin', () async {
    final guard = SyncAuthorizationGuard(
      currentUid: () => uid,
      resolveAccess: (_) async {
        return WorkspaceAccessResolution.online(
          access: accessFor(WorkspaceRole.admin),
          verifiedAt: verifiedAt,
        );
      },
    );

    final access = await guard.requireAuthorizedAdmin();

    expect(access.uid, uid);
    expect(access.role, WorkspaceRole.admin);
    expect(access.canSynchronize, isTrue);
  });

  test('blocks synchronization when no user is authenticated', () async {
    final guard = SyncAuthorizationGuard(
      currentUid: () => null,
      resolveAccess: (_) async {
        fail('The resolver must not run without an authenticated user.');
      },
    );

    await expectLater(
      guard.requireAuthorizedAdmin(),
      throwsA(
        isA<SyncAuthorizationException>().having(
          (error) => error.failure,
          'failure',
          SyncAuthorizationFailure.unauthenticated,
        ),
      ),
    );
  });

  test('blocks a cached admin until online revalidation succeeds', () async {
    final guard = SyncAuthorizationGuard(
      currentUid: () => uid,
      resolveAccess: (_) async {
        return WorkspaceAccessResolution.offline(
          access: accessFor(WorkspaceRole.admin),
          verifiedAt: verifiedAt,
          error: StateError('No network connection.'),
        );
      },
    );

    await expectLater(
      guard.requireAuthorizedAdmin(),
      throwsA(
        isA<SyncAuthorizationException>().having(
          (error) => error.failure,
          'failure',
          SyncAuthorizationFailure.onlineRevalidationRequired,
        ),
      ),
    );
  });

  test('blocks an online-verified viewer', () async {
    final guard = SyncAuthorizationGuard(
      currentUid: () => uid,
      resolveAccess: (_) async {
        return WorkspaceAccessResolution.online(
          access: accessFor(WorkspaceRole.viewer),
          verifiedAt: verifiedAt,
        );
      },
    );

    await expectLater(
      guard.requireAuthorizedAdmin(),
      throwsA(
        isA<SyncAuthorizationException>().having(
          (error) => error.failure,
          'failure',
          SyncAuthorizationFailure.insufficientRole,
        ),
      ),
    );
  });

  test('blocks an unauthorized workspace user', () async {
    final guard = SyncAuthorizationGuard(
      currentUid: () => uid,
      resolveAccess: (_) async {
        return WorkspaceAccessResolution.unauthorized();
      },
    );

    await expectLater(
      guard.requireAuthorizedAdmin(),
      throwsA(
        isA<SyncAuthorizationException>().having(
          (error) => error.failure,
          'failure',
          SyncAuthorizationFailure.unauthorized,
        ),
      ),
    );
  });

  test(
    'blocks synchronization when online verification is unavailable',
    () async {
      final guard = SyncAuthorizationGuard(
        currentUid: () => uid,
        resolveAccess: (_) async {
          return WorkspaceAccessResolution.unavailable(
            error: StateError('Firebase is unavailable.'),
          );
        },
      );

      await expectLater(
        guard.requireAuthorizedAdmin(),
        throwsA(
          isA<SyncAuthorizationException>().having(
            (error) => error.failure,
            'failure',
            SyncAuthorizationFailure.unavailable,
          ),
        ),
      );
    },
  );
}
