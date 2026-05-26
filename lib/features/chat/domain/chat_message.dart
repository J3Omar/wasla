import 'package:flutter/foundation.dart';

/// Delivery status of a chat message.
/// Ordinal value matters — DB stores as int, and we only ever upgrade (never downgrade).
enum MessageStatus {
  queued, // 0 — saved locally, waiting for connection
  sent, // 1 — left our device, arrived at peer's WebRTC server
  delivered, // 2 — peer device received it (app may not be in this chat)
  read, // 3 — peer opened THIS specific chat
  failed, // 4 — unrecoverable error (kept last for ordinal safety)
}

/// Type of message content.
enum MessageType {
  text,
  file,
  // voice, image — reserved for future features
}

/// Immutable domain model for a single chat message.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerId,
    required this.content,
    required this.isSent,
    required this.timestamp,
    required this.status,
    this.messageUuid = '',
    this.type = MessageType.text,
    this.isRead = false,
    this.fileName,
    this.fileSize,
  });

  final int id;

  /// Stable UUID per message — used for ACK routing (not timestamp-based).
  final String messageUuid;

  /// The UUID of the peer device (conversation key).
  final String peerId;

  /// Text content (or file path for file messages).
  final String content;

  /// true = sent by us, false = received from peer.
  final bool isSent;
  final bool isRead;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType type;

  /// Only set for file messages.
  final String? fileName;
  final int? fileSize;

  ChatMessage copyWith({
    int? id,
    String? messageUuid,
    String? peerId,
    String? content,
    bool? isSent,
    bool? isRead,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? type,
    String? fileName,
    int? fileSize,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      messageUuid: messageUuid ?? this.messageUuid,
      peerId: peerId ?? this.peerId,
      content: content ?? this.content,
      isSent: isSent ?? this.isSent,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  /// Serialize to JSON for network transport.
  Map<String, dynamic> toJson() => {
    'id': messageUuid, // send UUID as 'id' over network
    'peerId': peerId,
    'content': content,
    'isSent': isSent,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'status': status.index,
    'type': type.index,
    if (fileName != null) 'fileName': fileName,
    if (fileSize != null) 'fileSize': fileSize,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: 0,
      messageUuid: json['id'] as String? ?? '',
      peerId: json['peerId'] as String,
      content: json['content'] as String,
      isSent: json['isSent'] as bool,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as num).toInt(),
      ),
      status: MessageStatus.values[(json['status'] as num?)?.toInt() ?? 0],
      type: MessageType.values[(json['type'] as num?)?.toInt() ?? 0],
      fileName: json['fileName'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage && other.id == id && other.status == status);

  @override
  int get hashCode => Object.hash(id, status);
}
