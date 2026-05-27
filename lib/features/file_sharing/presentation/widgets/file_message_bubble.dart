import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:io';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/chat_message.dart';
import '../../domain/file_transfer_state.dart';
import '../../data/file_transfer_service.dart';

class FileMessageBubble extends StatelessWidget {
  const FileMessageBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
    required this.peerIp,
  });

  final ChatMessage message;
  final bool isSentByMe;
  final String peerIp;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final transfer = message.fileTransfer;
    final fileName = message.fileName ?? 'Unknown';
    final fileSize = message.fileSize ?? 0;
    
    // Status mapping
    final status = transfer?.status ?? FileTransferStatus.pendingApproval;
    final progress = transfer?.progress ?? 0.0;

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgTertiary,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isSentByMe ? Radius.zero : const Radius.circular(16),
          bottomLeft: !isSentByMe ? Radius.zero : const Radius.circular(16),
        ),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Name
          Row(
            children: [
              Icon(_getFileIcon(message.mimeType), color: AppColors.primaryCyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Body: Progress or Status
          if (status == FileTransferStatus.pendingApproval)
            Text(
              isSentByMe ? 'Waiting for approval...' : 'Tap to receive',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else if (status == FileTransferStatus.transferring)
            _buildProgress(progress, fileSize)
          else if (status == FileTransferStatus.completed)
            _buildCompleted()
          else if (status == FileTransferStatus.failed)
            const Text(
              'Transfer failed',
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            )
          else if (status == FileTransferStatus.declined)
            const Text(
              'Declined',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else if (status == FileTransferStatus.cancelled)
            const Text(
              'Cancelled',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),

          // Actions
          if (status == FileTransferStatus.transferring) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (transfer?.transferId != null) {
                    FileTransferService.instance.cancelTransfer(
                      transfer!.transferId,
                      message.peerId,
                      peerIp,
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildProgress(double progress, int totalSize) {
    final bytesTransferred = (progress * totalSize).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_formatBytes(bytesTransferred)} / ${_formatBytes(totalSize)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(color: AppColors.primaryCyan, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.bgDeep,
            minHeight: 6,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryCyan),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleted() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_formatBytes(message.fileSize ?? 0)} • ✓ Received',
          style: const TextStyle(color: AppColors.statusOnline, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () {
                final path = message.fileTransfer?.localFilePath;
                if (path != null && File(path).existsSync()) {
                  OpenFile.open(path);
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryCyan,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Open', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                final path = message.fileTransfer?.localFilePath;
                if (path != null) {
                  // Fallback generic way to open parent dir
                  launchUrlString('file://${File(path).parent.path}');
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Show in folder', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }
}
