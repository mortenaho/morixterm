class UploadCancelledException implements Exception {
  @override
  String toString() => 'Transfer cancelled';
}

enum TransferDirection { upload, download }

/// Tracks a single file transfer for UI progress and cancellation.
class UploadJob {
  UploadJob({
    required this.fileName,
    required this.totalBytes,
    this.direction = TransferDirection.upload,
  });

  final String fileName;
  final TransferDirection direction;
  int totalBytes;
  int sentBytes = 0;
  bool indeterminate = false;
  bool cancelling = false;
  DateTime startedAt = DateTime.now();
  void Function()? _onCancel;

  bool get isDownload => direction == TransferDirection.download;

  double? get fraction {
    if (indeterminate || totalBytes <= 0) return null;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get percent {
    final f = fraction;
    if (f == null) return 0;
    return (f * 100).round().clamp(0, 100);
  }

  double? get bytesPerSecond {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsed < 200 || sentBytes <= 0) return null;
    return sentBytes / (elapsed / 1000.0);
  }

  void bindCancel(void Function() fn) => _onCancel = fn;

  void clearCancel() => _onCancel = null;

  void cancel() {
    if (cancelling) return;
    cancelling = true;
    _onCancel?.call();
  }

  void throwIfCancelled() {
    if (cancelling) throw UploadCancelledException();
  }

  void setTotal(int bytes) {
    totalBytes = bytes < 0 ? 0 : bytes;
    if (totalBytes > 0 && sentBytes > totalBytes) {
      sentBytes = totalBytes;
    }
  }

  void report(int sent, {bool? indeterminate}) {
    if (indeterminate != null) this.indeterminate = indeterminate;
    sentBytes = sent.clamp(0, totalBytes > 0 ? totalBytes : sent);
  }
}

String formatTransferBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatTransferSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) return '—';
  return '${formatTransferBytes(bytesPerSecond.round())}/s';
}
