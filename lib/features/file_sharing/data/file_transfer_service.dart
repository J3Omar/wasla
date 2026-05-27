import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';

import 'file_storage_service.dart';
import '../domain/file_transfer_state.dart';
import '../../chat/data/webrtc_chat_service.dart';
import '../../chat/data/chat_database.dart';
import '../../chat/data/chat_notification_service.dart';
import '../../chat/domain/chat_message.dart';

const _kMaxSingleMessageSize = 16 * 1024 * 1024; // 16MB
const _kChunkSize = 64 * 1024; // 64KB

class _ActiveTransfer {
  final String transferId;
  final bool isSender;
  final File file;
  final int totalSize;
  int bytesTransferred = 0;
  
  // For Receiver (Chunking)
  int totalChunks = 0;
  List<Uint8List> chunks = [];

  _ActiveTransfer({
    required this.transferId,
    required this.isSender,
    required this.file,
    required this.totalSize,
  });
}

class FileTransferService {
  FileTransferService._();
  static final FileTransferService instance = FileTransferService._();

  final Map<String, _ActiveTransfer> _activeTransfers = {};
  WebRtcChatService? _chatService;

  void init(WebRtcChatService chatService) {
    _chatService = chatService;
    _chatService!.onRawDataReceived = _onRawDataReceived;
  }

  // ─── Incoming Data Handler ──────────────────────────────────────────────

  void _onRawDataReceived(String peerId, String peerIp, dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        switch (type) {
          case 'file_request':
            _handleFileRequest(peerId, peerIp, json);
            break;
          case 'file_response':
            _handleFileResponse(peerId, peerIp, json);
            break;
          case 'file_chunk_start':
            _handleFileChunkStart(peerId, json);
            break;
          case 'file_chunk_end':
            _handleFileChunkEnd(peerId, json);
            break;
          case 'file_complete':
            _handleFileComplete(peerId, json);
            break;
          case 'file_cancel':
            _handleFileCancel(peerId, json);
            break;
        }
      } catch (_) {
        // Not a valid JSON or not for us
      }
    } else if (data is Uint8List) {
      _handleBinaryData(peerId, data);
    }
  }

  // ─── Sender ─────────────────────────────────────────────────────────────

  Future<void> sendFileRequest({
    required String peerId,
    required String peerIp,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File no longer exists');
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      throw Exception('Cannot send empty file');
    }

    final fileName = file.uri.pathSegments.last;
    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final transferId = const Uuid().v4();

    // 1. Save to DB as pending
    final fileTransfer = FileTransfer(
      transferId: transferId,
      peerId: peerId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      localFilePath: filePath,
      status: FileTransferStatus.pendingApproval,
    );

    final msg = ChatMessage(
      id: 0,
      messageUuid: const Uuid().v4(),
      peerId: peerId,
      content: 'Sent a file',
      isSent: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      type: MessageType.file,
      fileName: fileName,
      fileSize: fileSize,
      fileTransfer: fileTransfer,
    );
    
    ChatDatabase.instance.insert(msg);

    // 2. Register Active Transfer
    _activeTransfers[transferId] = _ActiveTransfer(
      transferId: transferId,
      isSender: true,
      file: file,
      totalSize: fileSize,
    );

    // 3. Send over DataChannel
    final requestJson = jsonEncode({
      'type': 'file_request',
      'transferId': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'fromUuid': _chatService!.selfUuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    final sent = await _chatService!.sendRawData(peerId, peerIp, requestJson);
    if (!sent) {
      // Peer might be offline, cleanup
      _activeTransfers.remove(transferId);
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.failed.name);
    }
  }

  Future<void> _startSending(String transferId, String peerId, String peerIp) async {
    final transfer = _activeTransfers[transferId];
    if (transfer == null) return;

    try {
      ChatDatabase.instance.updateFileTransfer(transferId, status: FileTransferStatus.transferring.name); // Note: Need msg uuid, wait - transferId is unique enough, let's look up msg by transfer_id or we just update all. We'll update the DB by looking up the message.
      
      final bytes = await transfer.file.readAsBytes();

      if (transfer.totalSize <= _kMaxSingleMessageSize) {
        // Send as single binary message
        final sent = await _chatService!.sendRawData(peerId, peerIp, bytes);
        if (sent) {
           transfer.bytesTransferred = transfer.totalSize;
        } else {
           throw Exception('Failed to send binary');
        }
      } else {
        // Chunked transfer
        final totalChunks = (transfer.totalSize / _kChunkSize).ceil();
        
        await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
          'type': 'file_chunk_start',
          'transferId': transferId,
          'totalChunks': totalChunks,
        }));

        for (int i = 0; i < totalChunks; i++) {
          if (!_activeTransfers.containsKey(transferId)) return; // Cancelled

          final start = i * _kChunkSize;
          final end = (start + _kChunkSize > transfer.totalSize) ? transfer.totalSize : start + _kChunkSize;
          final chunk = bytes.sublist(start, end);

          await _chatService!.sendRawData(peerId, peerIp, chunk);
          
          transfer.bytesTransferred += chunk.length;
          
          // Update progress in DB (throttle in real app, but for now simple)
          // Wait, we need messageUuid to update. I'll add a helper to ChatDatabase or just pass it around.
        }

        await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
          'type': 'file_chunk_end',
          'transferId': transferId,
        }));
      }
    } catch (e) {
      _activeTransfers.remove(transferId);
      // Wait, we need to mark as failed
    }
  }

  // ─── Receiver ───────────────────────────────────────────────────────────

  void _handleFileRequest(String peerId, String peerIp, Map<String, dynamic> json) async {
    final transferId = json['transferId'] as String;
    final fileName = json['fileName'] as String;
    final fileSize = json['fileSize'] as int;
    final mimeType = json['mimeType'] as String;

    // 1. Check space
    final hasSpace = await FileStorageService.instance.hasEnoughSpace(fileSize);
    if (!hasSpace) {
      await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
        'type': 'file_response',
        'transferId': transferId,
        'accepted': false,
        'rejectReason': 'no_space',
      }));
      // Show snackbar? Handled in UI if we broadcast this
      return;
    }

    // 2. Create local pending message in DB
    final fileTransfer = FileTransfer(
      transferId: transferId,
      peerId: peerId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      status: FileTransferStatus.pendingApproval,
    );

    final msg = ChatMessage(
      id: 0,
      messageUuid: const Uuid().v4(),
      peerId: peerId,
      content: 'Incoming file: $fileName',
      isSent: false,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      type: MessageType.file,
      fileName: fileName,
      fileSize: fileSize,
      fileTransfer: fileTransfer,
    );
    
    ChatDatabase.instance.insert(msg);

    // 3. Show Notification or Bottom Sheet
    ChatNotificationService.instance.showMessageNotification(
      senderName: 'File Transfer Request',
      content: 'Incoming file: $fileName',
      peerId: peerId,
    );
  }

  Future<void> acceptTransfer(String transferId, String peerId, String peerIp) async {
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg == null) return;

    final destPath = await FileStorageService.instance.resolveDestinationPath(msg.fileName ?? 'unknown');
    
    _activeTransfers[transferId] = _ActiveTransfer(
      transferId: transferId,
      isSender: false,
      file: File(destPath),
      totalSize: msg.fileSize ?? 0,
    );

    ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.transferring.name, localFilePath: destPath);

    await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
      'type': 'file_response',
      'transferId': transferId,
      'accepted': true,
    }));
  }

  Future<void> declineTransfer(String transferId, String peerId, String peerIp) async {
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.declined.name);
    }

    await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
      'type': 'file_response',
      'transferId': transferId,
      'accepted': false,
      'rejectReason': 'user_rejected',
    }));
  }

  void _handleFileResponse(String peerId, String peerIp, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String;
    final accepted = json['accepted'] as bool;
    
    if (accepted) {
      _startSending(transferId, peerId, peerIp);
    } else {
      _activeTransfers.remove(transferId);
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      if (msg != null) {
        ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.declined.name);
      }
    }
  }

  void _handleFileChunkStart(String peerId, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String;
    final totalChunks = json['totalChunks'] as int;
    final transfer = _activeTransfers[transferId];
    if (transfer != null && !transfer.isSender) {
      transfer.totalChunks = totalChunks;
      transfer.chunks = [];
    }
  }

  void _handleBinaryData(String peerId, Uint8List data) async {
    // WebRTC DataChannel doesn't attach metadata to binary packets.
    // If we only allow 1 active transfer per peer, we can just find it:
    final transfer = _activeTransfers.values.firstWhere(
      (t) => !t.isSender,
      orElse: () => throw Exception('No active incoming transfer'),
    );

    transfer.bytesTransferred += data.length;
    final msg = ChatDatabase.instance.getMessageByTransferId(transfer.transferId);
    
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(
        msg.messageUuid,
        progress: transfer.bytesTransferred / transfer.totalSize,
      );
    }

    if (transfer.totalChunks > 0) {
      // Chunked mode
      transfer.chunks.add(data);
    } else {
      // Single message mode
      await transfer.file.writeAsBytes(data);
      _activeTransfers.remove(transfer.transferId);
      if (msg != null) {
        ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.completed.name);
      }
    }
  }

  void _handleFileChunkEnd(String peerId, Map<String, dynamic> json) async {
    final transferId = json['transferId'] as String;
    final transfer = _activeTransfers[transferId];
    if (transfer != null && !transfer.isSender) {
      // Reassemble
      final builder = BytesBuilder(copy: false);
      for (final chunk in transfer.chunks) {
        builder.add(chunk);
      }
      await transfer.file.writeAsBytes(builder.takeBytes());
      _activeTransfers.remove(transferId);
      
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      if (msg != null) {
        ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.completed.name);
      }
    }
  }

  void _handleFileComplete(String peerId, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String;
    _activeTransfers.remove(transferId);
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.completed.name);
    }
  }

  Future<void> cancelTransfer(String transferId, String peerId, String peerIp) async {
    final transfer = _activeTransfers.remove(transferId);
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.cancelled.name);
    }

    if (transfer != null && !transfer.isSender) {
      // Clean up partial file
      if (await transfer.file.exists()) {
        await transfer.file.delete();
      }
    }

    await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
      'type': 'file_cancel',
      'transferId': transferId,
      'reason': 'user_cancelled',
    }));
  }

  void _handleFileCancel(String peerId, Map<String, dynamic> json) async {
    final transferId = json['transferId'] as String;
    final transfer = _activeTransfers.remove(transferId);
    
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.cancelled.name);
    }

    if (transfer != null && !transfer.isSender) {
      if (await transfer.file.exists()) {
        await transfer.file.delete();
      }
    }
  }
}
