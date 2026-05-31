import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/file_size_formatter.dart';
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
            if (isSentByMe)
              const Text(
                'Waiting for approval...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      if (transfer?.transferId != null) {
                        FileTransferService.instance.declineTransfer(
                          transfer!.transferId,
                          message.peerId,
                          peerIp,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger, // red
                      foregroundColor: AppColors.bgDeep, // white/black text
                      minimumSize: Size.zero,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Refuse', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (transfer?.transferId != null) {
                        FileTransferService.instance.acceptTransfer(
                          transfer!.transferId,
                          message.peerId,
                          peerIp,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusOnline, // green
                      foregroundColor: AppColors.bgDeep,
                      minimumSize: Size.zero,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Accept', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
          else if (status == FileTransferStatus.transferring)
            _buildProgress(progress, fileSize, transfer?.transferId ?? '', peerIp)
          else if (status == FileTransferStatus.completed)
            _buildCompleted()
          else if (status == FileTransferStatus.failed || status == FileTransferStatus.declined || status == FileTransferStatus.cancelled)
            const Text(
              'Cancelled',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),

          // Actions
          if (status == FileTransferStatus.pendingApproval && isSentByMe) ...[
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

  Widget _buildProgress(double initialProgress, int totalSize, String transferId, String peerIp) {
    return StreamBuilder<TransferUpdate>(
      stream: FileTransferService.instance.progressStream
          .where((update) => update.transferId == transferId),
      builder: (context, snapshot) {
        final update = snapshot.data;
        final progress = update?.progress ?? initialProgress;
        final bytesTransferred = (progress * totalSize).round();
        
        String topText = '${formatFileSize(bytesTransferred)} / ${formatFileSize(totalSize)}';
        String bottomText = '';
        if (update != null && update.speedBytesPerSec > 0 && progress < 1.0) {
          final speed = '${formatFileSize(update.speedBytesPerSec)}/s';
          topText += ' • $speed';
          
          final m = update.eta.inMinutes;
          final s = update.eta.inSeconds % 60;
          bottomText = m > 0 ? '${m}m ${s}s left' : '${s}s left';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    topText,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(color: AppColors.primaryCyan, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 6,
                width: double.infinity,
                color: AppColors.bgDeep,
                alignment: Alignment.centerLeft,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      height: 6,
                      width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  bottomText,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                TextButton(
                  onPressed: () {
                    FileTransferService.instance.cancelTransfer(
                      transferId,
                      message.peerId,
                      peerIp,
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompleted() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatFileSize(message.fileSize ?? 0)} • ✓ ${isSentByMe ? 'Sent' : 'Received'}',
          style: const TextStyle(color: AppColors.statusOnline, fontSize: 12),
        ),
        if (!isSentByMe) ...[
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
                    OpenFile.open(File(path).parent.path);
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
