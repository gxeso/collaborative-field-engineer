import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../auth/sync_authorization_guard.dart';
import 'sync_engine.dart';

typedef SyncCompletedCallback = void Function(SyncBatchResult result);
typedef SyncFailedCallback = void Function(Object error, StackTrace stackTrace);

class AutomaticSyncCoordinator {
  AutomaticSyncCoordinator({
    required SyncEngine syncEngine,
    required SyncAuthorizationGuard authorizationGuard,
    Connectivity? connectivity,
  }) : _syncEngine = syncEngine,
       _authorizationGuard = authorizationGuard,
       _connectivity = connectivity ?? Connectivity();

  final SyncEngine _syncEngine;
  final SyncAuthorizationGuard _authorizationGuard;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<SyncBatchResult>? _activeSynchronization;

  bool _started = false;
  bool _wasOnline = false;

  SyncCompletedCallback? onSyncCompleted;
  SyncFailedCallback? onSyncFailed;

  bool get isSynchronizing => _activeSynchronization != null;

  bool get isOnline => _wasOnline;

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChanged,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'Connectivity monitoring failed',
          name: 'AutomaticSyncCoordinator',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    final connectivityResults = await _connectivity.checkConnectivity();
    _wasOnline = _hasConnection(connectivityResults);

    if (_wasOnline) {
      await _triggerAutomaticSync();
    }
  }

  Future<SyncBatchResult> synchronizeNow() {
    final activeSynchronization = _activeSynchronization;

    if (activeSynchronization != null) {
      return activeSynchronization;
    }

    final synchronization = _runAuthorizedSynchronization();
    _activeSynchronization = synchronization;

    return synchronization.whenComplete(() {
      if (identical(_activeSynchronization, synchronization)) {
        _activeSynchronization = null;
      }
    });
  }

  void _handleConnectivityChanged(
    List<ConnectivityResult> connectivityResults,
  ) {
    final isOnline = _hasConnection(connectivityResults);
    final connectionWasRestored = !_wasOnline && isOnline;

    _wasOnline = isOnline;

    if (connectionWasRestored) {
      developer.log(
        'Connectivity restored. Revalidating workspace access '
        'before automatic synchronization.',
        name: 'AutomaticSyncCoordinator',
      );

      unawaited(_triggerAutomaticSync());
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _triggerAutomaticSync() async {
    try {
      final result = await synchronizeNow();
      onSyncCompleted?.call(result);
    } catch (error, stackTrace) {
      onSyncFailed?.call(error, stackTrace);

      developer.log(
        'Automatic synchronization was blocked or failed',
        name: 'AutomaticSyncCoordinator',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<SyncBatchResult> _runAuthorizedSynchronization() async {
    await _authorizationGuard.requireAuthorizedAdmin();

    return _syncEngine.processPendingOperations();
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    onSyncCompleted = null;
    onSyncFailed = null;

    _started = false;
    _wasOnline = false;
  }
}
