sealed class SyncRemoteException implements Exception {
  const SyncRemoteException(this.message);

  final String message;

  @override
  String toString() {
    return '$runtimeType: $message';
  }
}

final class TemporarySyncException extends SyncRemoteException {
  const TemporarySyncException(super.message, {this.retryAfter});

  final Duration? retryAfter;
}

final class SyncConflictException extends SyncRemoteException {
  const SyncConflictException(super.message, {this.remotePayload});

  final Map<String, dynamic>? remotePayload;
}

final class PermanentSyncException extends SyncRemoteException {
  const PermanentSyncException(super.message);
}
