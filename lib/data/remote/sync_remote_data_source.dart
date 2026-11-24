import '../models/sync_operation.dart';

abstract interface class SyncRemoteDataSource {
  Future<void> uploadOperation(SyncOperation operation);
}
