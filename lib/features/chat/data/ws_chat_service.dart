import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/chat_message.dart';
import 'chat_database.dart';

const kChatWsPort = 8766;

/// Provider to access the global chat server.
final globalChatServerProvider = Provider<GlobalChatServer>((ref) {
  final server = GlobalChatServer();
  ref.onDispose(() => server.dispose());
  return server;
});

/// A global service that listens for incoming LAN chat connections and manages
/// outgoing connections to peers. It handles background message receiving and acks.
class GlobalChatServer {
  HttpServer? _server;
  final Map<String, WebSocket> _outgoingConnections = {};
  bool _started = false;
  Timer? _retryTimer;

  /// The UUID of the peer whose chat screen is currently visible.
  /// If a message arrives from this peer, it is immediately marked as read.
  String? activeChatPeerId;

  /// Our own UUID, required so the peer knows who is sending the message.
  String? selfUuid;

  /// Our own display name.
  String? selfName;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        kChatWsPort,
        shared: true,
      );
      _server!.transform(WebSocketTransformer()).listen((ws) {
        ws.listen((data) {
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              _handleIncomingPayload(ws, json);
            } catch (_) {}
          }
        }, onError: (_) {});
      });
    } catch (e) {
      // Port already in use. Ignore.
    }

    _retryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _flushQueue(),
    );
  }

  Future<void> _flushQueue() async {
    if (selfUuid == null || selfName == null) return;

    final unsent = ChatDatabase.instance.getUnsentMessages();
    if (unsent.isEmpty) return;

    for (final msg in unsent) {
      final peerIp = ChatDatabase.instance.getPeerIp(msg.peerId);
      if (peerIp == null) continue;

      final payload = {
        'type': 'msg',
        'senderId': selfUuid,
        'senderName': selfName,
        'content': msg.content,
        'ts': msg.timestamp.millisecondsSinceEpoch,
      };

      final sent = await sendMessage(peerIp, payload);
      if (sent) {
        ChatDatabase.instance.updateStatus(msg.id, MessageStatus.sent);
      }
    }
  }

  void _handleIncomingPayload(WebSocket ws, Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final senderId = payload['senderId'] as String?;
    final ts = (payload['ts'] as num?)?.toInt();

    if (type == null || ts == null) return;

    // Handle acks first - they don't require senderId
    if (type == 'ack_delivery') {
      ChatDatabase.instance.updateStatusByTimestamp(
        ts,
        MessageStatus.delivered,
      );
      return;
    }

    if (type == 'ack_read') {
      ChatDatabase.instance.updateStatusByTimestamp(ts, MessageStatus.read);
      return;
    }

    // Messages require senderId
    if (senderId == null) return;

    if (type == 'msg') {
      final content = payload['content'] as String;
      final senderName = payload['senderName'] as String?;

      if (senderName != null) {
        ChatDatabase.instance.upsertPeer(senderId, senderName);
      }

      final msg = ChatMessage(
        id: 0,
        peerId: senderId,
        content: content,
        isSent: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
        status: MessageStatus.delivered,
        type: MessageType.text,
      );
      ChatDatabase.instance.insert(msg);

      // If user is actively in this chat, mark as read immediately
      if (activeChatPeerId == senderId) {
        ChatDatabase.instance.markAllRead(senderId);
      }

      // Acknowledge delivery
      _sendToSocket(ws, {
        'type': 'ack_delivery',
        'senderId': selfUuid,
        'ts': ts,
      });

      // If the user is currently looking at this chat, acknowledge read
      if (activeChatPeerId == senderId) {
        _sendToSocket(ws, {'type': 'ack_read', 'senderId': selfUuid, 'ts': ts});
      }
    }
  }

  /// Sends a message to a peer by their IP. Manages the connection automatically.
  Future<bool> sendMessage(String peerIp, Map<String, dynamic> payload) async {
    // Clean up stale connection if it exists
    final existing = _outgoingConnections[peerIp];
    if (existing != null && existing.readyState != WebSocket.open) {
      _outgoingConnections.remove(peerIp);
    }

    WebSocket? ws = _outgoingConnections[peerIp];

    if (ws == null) {
      try {
        ws = await WebSocket.connect(
          'ws://$peerIp:$kChatWsPort',
        ).timeout(const Duration(seconds: 5));
        _outgoingConnections[peerIp] = ws;

        // Listen for incoming acks on this outgoing socket
        ws.listen(
          (data) {
            if (data is String) {
              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                _handleIncomingPayload(ws!, json);
              } catch (_) {}
            }
          },
          onDone: () {
            _outgoingConnections.remove(peerIp);
          },
          onError: (_) {
            _outgoingConnections.remove(peerIp);
          },
        );
      } catch (_) {
        _outgoingConnections.remove(peerIp);
        return false;
      }
    }

    return _sendToSocket(ws, payload);
  }

  bool _sendToSocket(WebSocket ws, Map<String, dynamic> payload) {
    if (ws.readyState == WebSocket.open) {
      try {
        ws.add(jsonEncode(payload));
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _server?.close(force: true);
    for (final ws in _outgoingConnections.values) {
      await ws.close();
    }
    _outgoingConnections.clear();
  }
}
