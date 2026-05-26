import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/chat_database.dart';
import '../data/ws_chat_service.dart';
import '../domain/chat_message.dart';

const _kNameKey = 'wasla_device_name';
const _kUuidKey = 'wasla_device_uuid';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Provider for the chat notifier for a specific peer device.
/// Key: peerId (UUID string)
final chatProvider = AsyncNotifierProviderFamily<ChatNotifier, List<ChatMessage>, ChatArgs>(
  ChatNotifier.new,
);

class ChatArgs {
  const ChatArgs({required this.peerId, required this.peerIp, required this.peerName});
  final String peerId;
  final String peerIp;
  final String peerName;

  @override
  bool operator ==(Object other) =>
      other is ChatArgs && other.peerId == peerId;

  @override
  int get hashCode => peerId.hashCode;
}

/// State notifier for a single conversation.
class ChatNotifier extends FamilyAsyncNotifier<List<ChatMessage>, ChatArgs> {
  StreamSubscription<List<ChatMessage>>? _dbSub;

  @override
  Future<List<ChatMessage>> build(ChatArgs arg) async {
    // Open DB if not already open
    await ChatDatabase.instance.open();

    // Save the peer's last known IP so the background queue can reach them offline
    ChatDatabase.instance.upsertPeer(arg.peerId, arg.peerName, arg.peerIp);

    // Mark this peer as active in the global server so incoming messages get ack_read
    final server = ref.read(globalChatServerProvider);
    server.activeChatPeerId = arg.peerId;

    // Load our own UUID and Name for sending and background queue
    const storage = FlutterSecureStorage();
    server.selfUuid ??= await storage.read(key: _kUuidKey) ?? '';
    server.selfName ??= await storage.read(key: _kNameKey) ?? 'Wasla User';

    // Subscribe to DB stream (the GlobalChatServer will insert into DB)
    _dbSub = ChatDatabase.instance.watchMessages(arg.peerId).listen((msgs) {
      state = AsyncData(msgs);
    });

    ref.onDispose(() {
      _dbSub?.cancel();
      // If we are leaving this chat, unmark active peer
      if (server.activeChatPeerId == arg.peerId) {
        server.activeChatPeerId = null;
      }
    });

    // Mark all existing messages from this peer as read
    // and notify the sender so they see blue ticks
    final messages = ChatDatabase.instance.getMessages(arg.peerId);
    final unreadReceived = messages.where((m) => !m.isSent && !m.isRead).toList();
    ChatDatabase.instance.markAllRead(arg.peerId);
    
    // Send ack_read for each unread message so the sender gets blue ticks
    if (unreadReceived.isNotEmpty && arg.peerIp.isNotEmpty) {
      for (final msg in unreadReceived) {
        await server.sendMessage(arg.peerIp, {
          'type': 'ack_read',
          'senderId': server.selfUuid,
          'ts': msg.timestamp.millisecondsSinceEpoch,
        });
      }
    }

    return ChatDatabase.instance.getMessages(arg.peerId);
  }

  /// Send a text message to the peer.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    final server = ref.read(globalChatServerProvider);

    const storage = FlutterSecureStorage();
    final selfName = await storage.read(key: _kNameKey) ?? 'Unknown';

    // Optimistically insert as "sending"
    final draft = ChatMessage(
      id: 0,
      peerId: arg.peerId,
      content: text.trim(),
      isSent: true,
      timestamp: now,
      status: MessageStatus.sending,
      type: MessageType.text,
    );
    final saved = ChatDatabase.instance.insert(draft);

    // Try to send over WebSocket via Global Server
    final payload = {
      'type': 'msg',
      'senderId': server.selfUuid,
      'senderName': selfName,
      'content': text.trim(),
      'ts': now.millisecondsSinceEpoch,
    };
    
    final sent = await server.sendMessage(arg.peerIp, payload);

    // If it fails to send immediately, we leave it as sending! 
    // The GlobalChatServer background queue will auto-retry every 5 seconds.
    ChatDatabase.instance.updateStatus(
      saved.id,
      sent ? MessageStatus.sent : MessageStatus.sending,
    );
  }
}
