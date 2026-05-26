import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../../core/utils/string_utils.dart';
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
  late WsChatService _ws;
  StreamSubscription<List<ChatMessage>>? _dbSub;
  bool _peerOnline = false;

  @override
  Future<List<ChatMessage>> build(ChatArgs arg) async {
    // Open DB if not already open
    await ChatDatabase.instance.open();

    // Get our own IP
    const storage = FlutterSecureStorage();
    final selfUuid = await storage.read(key: _kUuidKey) ?? '';
    final rawIp = await NetworkInfo().getWifiIP() ?? '127.0.0.1';
    final selfIp = normalizeDigits(rawIp);

    // Start WebSocket service
    _ws = WsChatService(
      selfIp: selfIp,
      peerIp: arg.peerIp,
      onMessage: _onIncoming,
      onPeerConnected: () => _peerOnline = true,
      onPeerDisconnected: () => _peerOnline = false,
    );
    await _ws.start();

    // Subscribe to DB stream
    _dbSub = ChatDatabase.instance.watchMessages(arg.peerId).listen((msgs) {
      state = AsyncData(msgs);
    });

    ref.onDispose(() {
      _dbSub?.cancel();
      _ws.dispose();
    });

    return ChatDatabase.instance.getMessages(arg.peerId);
  }

  bool get isPeerOnline => _peerOnline;

  /// Called when a message arrives from the peer over WebSocket.
  void _onIncoming(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    if (type != 'msg') return;

    final msg = ChatMessage(
      id: 0,
      peerId: arg.peerId,
      content: payload['content'] as String,
      isSent: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (payload['ts'] as num).toInt(),
      ),
      status: MessageStatus.delivered,
      type: MessageType.text,
    );
    ChatDatabase.instance.insert(msg);
  }

  /// Send a text message to the peer.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final now = DateTime.now();

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

    // Try to send over WebSocket
    final payload = {
      'type': 'msg',
      'content': text.trim(),
      'ts': now.millisecondsSinceEpoch,
    };
    final sent = _ws.send(payload);

    ChatDatabase.instance.updateStatus(
      saved.id,
      sent ? MessageStatus.sent : MessageStatus.failed,
    );
  }
}
