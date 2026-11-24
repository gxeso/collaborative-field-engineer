enum SyncStatus {
  pending,
  synced,
  conflict,
  failed;

  static SyncStatus fromName(String? value) {
    return SyncStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SyncStatus.pending,
    );
  }
}
