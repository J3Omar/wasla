import 'package:flutter/foundation.dart';

/// Delivery status of a chat message.
enum MessageStatus {
  sending, // locally created, not yet sent
  sent, // sent over the network
  delivered, // peer acknowledged receipt
  failed, // send failed
  read, // peer has seen the message
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
    this.type = MessageType.text,
    this.isRead = false,
    this.fileName,
    this.fileSize,
  });

  final int id;

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
    'id': id,
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
      id: (json['id'] as num?)?.toInt() ?? 0,
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
      identical(this, other) || (other is ChatMessage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
