import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/file_transfer_service.dart';

class FileRequestSheet extends StatelessWidget {
  const FileRequestSheet({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderName,
    required this.peerId,
    required this.peerIp,
  });

  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderName;
  final String peerId;
  final String peerIp;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.bgQuaternary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(
            Icons.file_present_rounded,
            size: 48,
            color: AppColors.primaryCyan,
          ),
          const SizedBox(height: 16),
          Text(
            '$senderName wants to send you a file',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '$fileName (${_formatBytes(fileSize)})',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    FileTransferService.instance.declineTransfer(transferId, peerId, peerIp);
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    FileTransferService.instance.acceptTransfer(context, transferId, peerId, peerIp);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryCyan,
                    foregroundColor: AppColors.bgPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

void showFileRequestSheet(
  BuildContext context, {
  required String transferId,
  required String fileName,
  required int fileSize,
  required String senderName,
  required String peerId,
  required String peerIp,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => FileRequestSheet(
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      senderName: senderName,
      peerId: peerId,
      peerIp: peerIp,
    ),
  );
}
