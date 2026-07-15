enum SyncStatus {
  synced,
  toPost, // New record waiting for upload
  toUpdate, // Edited record waiting for upload
  uploading, // Currently in progress
  error, // Server rejected data (Requires Conflict Resolution)
  warning, // Uploaded but with server warnings
}

// Helper to convert String from DB to Enum
SyncStatus parseSyncStatus(String? status) {
  switch (status) {
    case 'synced':
      return SyncStatus.synced;
    case 'to_post':
      return SyncStatus.toPost;
    case 'to_update':
      return SyncStatus.toUpdate;
    case 'uploading':
      return SyncStatus.uploading;
    case 'error':
      return SyncStatus.error;
    case 'warning':
      return SyncStatus.warning;
    default:
      return SyncStatus.toPost; // Default safety
  }
}

// Helper to convert Enum to String for DB
String syncStatusToString(SyncStatus status) {
  switch (status) {
    case SyncStatus.synced:
      return 'synced';
    case SyncStatus.toPost:
      return 'to_post';
    case SyncStatus.toUpdate:
      return 'to_update';
    case SyncStatus.uploading:
      return 'uploading';
    case SyncStatus.error:
      return 'error';
    case SyncStatus.warning:
      return 'warning';
  }
}
