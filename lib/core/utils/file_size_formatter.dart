// Create in lib/core/utils/file_size_formatter.dart
// Pure Dart helper for file sizes and speeds

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}
