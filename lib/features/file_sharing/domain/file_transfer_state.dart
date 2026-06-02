enum FileTransferStatus {
  pendingApproval,
  transferring,
  completed,
  failed,
  declined,
  cancelled,
}

class FileTransfer {
  final String transferId;
  final String peerId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String? localFilePath;
  final FileTransferStatus status;
  final double progress; // 0.0 to 1.0

  const FileTransfer({
    required this.transferId,
    required this.peerId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.localFilePath,
    this.status = FileTransferStatus.pendingApproval,
    this.progress = 0.0,
  });

  FileTransfer copyWith({
    String? localFilePath,
    FileTransferStatus? status,
    double? progress,
  }) {
    return FileTransfer(
      transferId: transferId,
      peerId: peerId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      localFilePath: localFilePath ?? this.localFilePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }

  /// Helper to convert string to enum
  static FileTransferStatus statusFromString(String statusStr) {
    return FileTransferStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => FileTransferStatus.failed,
    );
  }
}
