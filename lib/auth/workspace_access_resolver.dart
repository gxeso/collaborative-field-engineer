import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import 'cached_workspace_access.dart';
import 'workspace_access_cache.dart';
import 'workspace_access_resolution.dart';
import 'workspace_access_service.dart';

class WorkspaceAccessResolver {
  WorkspaceAccessResolver({
    required WorkspaceAccessRemoteDataSource remoteService,
    required WorkspaceAccessCache cache,
    DateTime Function()? clock,
    Duration remoteTimeout = const Duration(seconds: 8),
    Duration maxOfflineAccessAge = const Duration(hours: 24),
  }) : _remoteService = remoteService,
       _cache = cache,
       _clock = clock ?? DateTime.now,
       _remoteTimeout = remoteTimeout,
       _maxOfflineAccessAge = maxOfflineAccessAge {
    if (remoteTimeout <= Duration.zero) {
      throw ArgumentError.value(
        remoteTimeout,
        'remoteTimeout',
        'The remote timeout must be greater than zero.',
      );
    }

    if (maxOfflineAccessAge <= Duration.zero) {
      throw ArgumentError.value(
        maxOfflineAccessAge,
        'maxOfflineAccessAge',
        'The maximum offline access age must be greater than zero.',
      );
    }
  }

  final WorkspaceAccessRemoteDataSource _remoteService;
  final WorkspaceAccessCache _cache;
  final DateTime Function() _clock;
  final Duration _remoteTimeout;
  final Duration _maxOfflineAccessAge;

  Duration get maxOfflineAccessAge => _maxOfflineAccessAge;

  Future<WorkspaceAccessResolution> resolve(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(
        uid,
        'uid',
        'The Firebase user ID cannot be empty.',
      );
    }

    try {
      final remoteAccess = await _remoteService
          .getAccessForUser(normalizedUid)
          .timeout(_remoteTimeout);

      if (remoteAccess == null) {
        await _removeCachedAccess(normalizedUid);

        return WorkspaceAccessResolution.unauthorized();
      }

      return _cacheRemoteAccess(remoteAccess);
    } on TimeoutException catch (error) {
      return _resolveFromCache(uid: normalizedUid, error: error);
    } on FirebaseException catch (error) {
      if (!_isRemoteUnavailable(error)) {
        rethrow;
      }

      return _resolveFromCache(uid: normalizedUid, error: error);
    }
  }

  Future<WorkspaceAccessResolution> _cacheRemoteAccess(
    WorkspaceAccess remoteAccess,
  ) async {
    final verifiedAt = _clock().toUtc();

    await _cache.save(
      CachedWorkspaceAccess(
        uid: remoteAccess.uid,
        workspaceId: remoteAccess.workspaceId,
        role: remoteAccess.role,
        verifiedAt: verifiedAt,
      ),
    );

    return WorkspaceAccessResolution.online(
      access: remoteAccess,
      verifiedAt: verifiedAt,
    );
  }

  Future<WorkspaceAccessResolution> _resolveFromCache({
    required String uid,
    required Object error,
  }) async {
    final cachedAccess = await _cache.get(
      uid: uid,
      workspaceId: _remoteService.workspaceId,
    );

    if (cachedAccess == null) {
      return WorkspaceAccessResolution.unavailable(error: error);
    }

    final now = _clock().toUtc();
    final verifiedAt = cachedAccess.verifiedAt.toUtc();
    final cacheAge = now.difference(verifiedAt);

    if (cacheAge.isNegative) {
      await _removeCachedAccess(uid);

      return WorkspaceAccessResolution.unavailable(
        error: StateError(
          'The cached workspace authorization contains an invalid '
          'future verification timestamp. Connect to the internet '
          'to verify your membership again.',
        ),
      );
    }

    if (cacheAge > _maxOfflineAccessAge) {
      await _removeCachedAccess(uid);

      return WorkspaceAccessResolution.unavailable(
        error: StateError(
          'Offline workspace authorization has expired. '
          'Connect to the internet to verify your membership again.',
        ),
      );
    }

    return WorkspaceAccessResolution.offline(
      access: cachedAccess.access,
      verifiedAt: verifiedAt,
      error: error,
    );
  }

  Future<void> _removeCachedAccess(String uid) {
    return _cache.remove(uid: uid, workspaceId: _remoteService.workspaceId);
  }

  bool _isRemoteUnavailable(FirebaseException error) {
    return switch (error.code.toLowerCase()) {
      'disconnected' || 'network-error' || 'unavailable' || 'timeout' => true,
      _ => false,
    };
  }
}
