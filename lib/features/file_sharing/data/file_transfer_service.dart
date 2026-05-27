import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';
import 'package:crypto/crypto.dart';

import 'file_storage_service.dart';
import '../domain/file_transfer_state.dart';
import '../../../core/utils/digest_sink.dart';
import '../../chat/data/webrtc_chat_service.dart';
import '../../chat/data/chat_database.dart';
import '../../chat/data/chat_notification_service.dart';
import '../../chat/domain/chat_message.dart';

const _kChunkSize = 64 * 1024; // 64KB

class _ActiveTransfer {
  final String transferId;
  final String peerId;
  final bool isSender;
  final File file;
  final int totalSize;
  int bytesTransferred = 0;
  
  // For Receiver (Chunking)
  int totalChunks = 0;
  IOSink? fileSink;
  String? md5Hash;
  bool isCancelled = false;
  String? messageUuid; // cached after first DB lookup — avoids repeated queries

  // For ACK-based Flow Control
  int chunksReceived = 0;
  Completer<void>? ackCompleter;

  // For Throttling DB updates
  int lastDbUpdateMs = 0;

  final DigestSink md5Sink = DigestSink();
  late final ByteConversionSink md5Input;

  _ActiveTransfer({
    required this.transferId,
    required this.peerId,
    required this.isSender,
    required this.file,
    required this.totalSize,
  }) {
    md5Input = md5.startChunkedConversion(md5Sink);
  }
}

class FileTransferService {
  FileTransferService._();
  static final FileTransferService instance = FileTransferService._();

  final Map<String, _ActiveTransfer> _activeTransfers = {};
  WebRtcChatService? _chatService;

  final _progressController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get progressStream => _progressController.stream;

  void init(WebRtcChatService chatService) {
    _chatService = chatService;
    _chatService!.onRawDataReceived = _onRawDataReceived;
    _chatService!.onPeerDisconnected = _onPeerDisconnected;
  }

  void _onPeerDisconnected(String peerId) {
    final transfersToCancel = _activeTransfers.values.where((t) => t.peerId == peerId).toList();
    for (final transfer in transfersToCancel) {
      _handleFileCancel(peerId, {'transferId': transfer.transferId});
    }
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
          case 'file_chunk_ack':
            _handleFileChunkAck(peerId, json);
            break;
          case 'file_cancel':
            _handleFileCancel(peerId, json);
            break;
          case 'file_failed':
            _handleFileFailed(peerId, json);
            break;
          case 'file_progress':
            _handleFileProgress(peerId, json);
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
      peerId: peerId,
      isSender: true,
      file: file,
      totalSize: fileSize,
    );
    _activeTransfers[transferId]!.messageUuid = msg.messageUuid;

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
      ChatDatabase.instance.updateFileTransfer(transferId, status: FileTransferStatus.transferring.name); 
      
      final totalChunks = (transfer.totalSize / _kChunkSize).ceil();
      
      await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
        'type': 'file_chunk_start',
        'transferId': transferId,
        'totalChunks': totalChunks,
      }));

      int chunksSent = 0;
      final stream = transfer.file.openRead();
      await for (final chunk in stream) {
        if (!_activeTransfers.containsKey(transferId) || transfer.isCancelled) return;

        // Flow control: Wait if buffer exceeds 4MB
        while (_chatService!.getBufferedAmount(peerId) > 4 * 1024 * 1024) {
          if (!_activeTransfers.containsKey(transferId) || transfer.isCancelled) return;
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final bytes = chunk as Uint8List? ?? Uint8List.fromList(chunk);
        transfer.md5Input.add(bytes);
        _chatService!.sendRawData(peerId, peerIp, bytes); // fire and forget — flow control handles pacing
        
        transfer.bytesTransferred += chunk.length;
        _progressController.add({transferId: transfer.bytesTransferred / transfer.totalSize});
        
        // Strict network pacing: ACK-based flow control.
        // We require an ACK from the receiver every 16 chunks (~1MB)
        // This guarantees the sender NEVER overruns the WebRTC SCTP buffer
        // and perfectly adapts to the exact Wi-Fi speed.
        chunksSent++;
        if (chunksSent % 16 == 0) {
          transfer.ackCompleter = Completer<void>();
          try {
            await transfer.ackCompleter!.future.timeout(const Duration(seconds: 15));
          } catch (e) {
            // Timeout means receiver disconnected or is extremely slow
            cancelTransfer(transferId, peerId, peerIp);
            return;
          }
        }
        
        // Small yield to event loop for chunks that don't need ACK
        await Future.delayed(Duration.zero);
        
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - transfer.lastDbUpdateMs > 500 || transfer.bytesTransferred == transfer.totalSize) {
          transfer.lastDbUpdateMs = nowMs;
          if (transfer.messageUuid != null) {
            ChatDatabase.instance.updateFileTransfer(
              transfer.messageUuid!,
              progress: transfer.bytesTransferred / transfer.totalSize,
            );
          }
        }
      }

      transfer.md5Input.close();
      final md5String = transfer.md5Sink.value.toString();

      // Ensure the final message is sent and awaited
      await Future.delayed(const Duration(milliseconds: 100)); // allow trailing chunks to clear
      await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
        'type': 'file_chunk_end',
        'transferId': transferId,
        'md5': md5String,
      }));
    } catch (e) {
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      if (msg != null) {
        ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.failed.name);
      }
      _activeTransfers.remove(transferId);
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

    // 3. Show Notification only if not in this chat
    if (_chatService!.activeChatPeerId != peerId) {
      ChatNotificationService.instance.showMessageNotification(
        senderName: 'File Transfer Request',
        content: 'Incoming file: $fileName',
        peerId: peerId,
      );
    }
  }

  Future<void> acceptTransfer(String transferId, String peerId, String peerIp) async {
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg == null) return;

    final destPath = await FileStorageService.instance.resolveDestinationPath(msg.fileName ?? 'unknown');
    
    _activeTransfers[transferId] = _ActiveTransfer(
      transferId: transferId,
      peerId: peerId,
      isSender: false,
      file: File(destPath),
      totalSize: msg.fileSize ?? 0,
    );
    _activeTransfers[transferId]!.messageUuid = msg.messageUuid;

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
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      if (msg != null) {
        ChatDatabase.instance.updateFileTransfer(
          msg.messageUuid, 
          status: FileTransferStatus.transferring.name,
        );
      }
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
      
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      final destPath = msg?.fileTransfer?.localFilePath;
      if (destPath != null) {
        final tempPath = FileStorageService.instance.getTempDestinationPath(destPath);
        transfer.fileSink = File(tempPath).openWrite(mode: FileMode.write);
      }
    }
  }

  void _handleBinaryData(String peerId, Uint8List data) async {
    // WebRTC DataChannel doesn't attach metadata to binary packets.
    // If we only allow 1 active transfer per peer, we can just find it:
    final transfer = _activeTransfers.values.where((t) => !t.isSender).firstOrNull;
    if (transfer == null) return; // ignore stray binary data

    if (transfer.isCancelled) return;

    transfer.fileSink?.add(data);
    transfer.md5Input.add(data);

    transfer.bytesTransferred += data.length;
    _progressController.add({transfer.transferId: transfer.bytesTransferred / transfer.totalSize});
    
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    
    if (transfer.messageUuid != null && 
        (nowMs - transfer.lastDbUpdateMs > 500 || transfer.bytesTransferred == transfer.totalSize)) {
      transfer.lastDbUpdateMs = nowMs;
      ChatDatabase.instance.updateFileTransfer(
        transfer.messageUuid!,
        progress: transfer.bytesTransferred / transfer.totalSize,
      );
    }
    
    // Send ACK back to sender every 16 chunks (~1MB)
    // We get peerIp from the session via chat service, but we don't strictly need it 
    // to just send raw data if it's already connected, but we can look it up.
    transfer.chunksReceived++;
    if (transfer.chunksReceived % 16 == 0) {
      final peerIp = ChatDatabase.instance.getPeerIp(peerId) ?? '';
      _chatService!.sendRawData(peerId, peerIp, jsonEncode({
        'type': 'file_chunk_ack',
        'transferId': transfer.transferId,
      }));
    }
  }

  void _handleFileChunkAck(String peerId, Map<String, dynamic> json) {
    final transferId = json['transferId'] as String;
    final transfer = _activeTransfers[transferId];
    if (transfer != null && transfer.isSender) {
      if (transfer.ackCompleter != null && !transfer.ackCompleter!.isCompleted) {
        transfer.ackCompleter!.complete();
      }
    }
  }

  void _handleFileChunkEnd(String peerId, Map<String, dynamic> json) async {
    final transferId = json['transferId'] as String;
    final transfer = _activeTransfers[transferId];
    if (transfer != null && !transfer.isSender) {
      await transfer.fileSink?.flush();
      await transfer.fileSink?.close();
      transfer.fileSink = null;
      
      if (transfer.isCancelled) {
        _activeTransfers.remove(transferId);
        return;
      }
      
      transfer.md5Input.close();
      final localMd5 = transfer.md5Sink.value.toString();
      final expectedMd5 = json['md5'] as String?;
      
      final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
      final destPath = msg?.fileTransfer?.localFilePath;
      if (destPath != null) {
        final tempPath = FileStorageService.instance.getTempDestinationPath(destPath);
        
        // Verify MD5 instantly
        if (expectedMd5 != null && localMd5 != expectedMd5) {
            // Checksum mismatch
            await File(tempPath).delete();
            _activeTransfers.remove(transferId);
            ChatDatabase.instance.updateFileTransfer(msg!.messageUuid, status: FileTransferStatus.failed.name);
            final peerIp = ChatDatabase.instance.getPeerIp(peerId);
            if (peerIp != null) {
              await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
                'type': 'file_failed',
                'transferId': transferId,
                'reason': 'checksum_mismatch',
              }));
            }
            return;
        }
        
        await FileStorageService.instance.commitTempFile(tempPath, destPath);
        _activeTransfers.remove(transferId);
        ChatDatabase.instance.updateFileTransfer(msg!.messageUuid, status: FileTransferStatus.completed.name);
        
        final peerIp = ChatDatabase.instance.getPeerIp(peerId);
        if (peerIp != null) {
          await _chatService!.sendRawData(peerId, peerIp, jsonEncode({
            'type': 'file_complete',
            'transferId': transferId,
            'savedPath': destPath,
          }));
        }
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

    if (transfer != null) {
      transfer.isCancelled = true;
      if (!transfer.isSender) {
        await transfer.fileSink?.close();
        transfer.fileSink = null;
        final msgLocal = ChatDatabase.instance.getMessageByTransferId(transferId);
        final destPath = msgLocal?.fileTransfer?.localFilePath;
        if (destPath != null) {
           final tempPath = FileStorageService.instance.getTempDestinationPath(destPath);
           final file = File(tempPath);
           if (await file.exists()) {
             await file.delete();
           }
        }
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

    if (transfer != null) {
      transfer.isCancelled = true;
      if (!transfer.isSender) {
        await transfer.fileSink?.close();
        transfer.fileSink = null;
        final msgLocal = ChatDatabase.instance.getMessageByTransferId(transferId);
        final destPath = msgLocal?.fileTransfer?.localFilePath;
        if (destPath != null) {
           final tempPath = FileStorageService.instance.getTempDestinationPath(destPath);
           final file = File(tempPath);
           if (await file.exists()) {
             await file.delete();
           }
        }
      }
    }
  }

  void _handleFileFailed(String peerId, Map<String, dynamic> json) async {
    final transferId = json['transferId'] as String;
    final transfer = _activeTransfers.remove(transferId);
    
    final msg = ChatDatabase.instance.getMessageByTransferId(transferId);
    if (msg != null) {
      ChatDatabase.instance.updateFileTransfer(msg.messageUuid, status: FileTransferStatus.failed.name);
    }

    if (transfer != null) {
      transfer.isCancelled = true;
      if (!transfer.isSender) {
        await transfer.fileSink?.close();
        transfer.fileSink = null;
        final msgLocal = ChatDatabase.instance.getMessageByTransferId(transferId);
        final destPath = msgLocal?.fileTransfer?.localFilePath;
        if (destPath != null) {
           final tempPath = FileStorageService.instance.getTempDestinationPath(destPath);
           final file = File(tempPath);
           if (await file.exists()) {
             await file.delete();
           }
        }
      }
    }
  }

  void _handleFileProgress(String peerId, Map<String, dynamic> json) {
    // We already compute progress via sent bytes on sender side and received bytes on receiver side,
    // so we don't necessarily need to update the DB from this message. 
    // However, if we wanted to enforce receiver-acknowledged progress on the sender side, we could use this.
  }
}
