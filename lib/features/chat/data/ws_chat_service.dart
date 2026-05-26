import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/chat_message.dart';

/// Port on which each Wasla instance runs its WebSocket chat server.
const kChatWsPort = 8766;

/// Incoming message payload over the wire.
typedef OnMessageReceived = void Function(Map<String, dynamic> payload);
typedef OnPeerConnected = void Function();
typedef OnPeerDisconnected = void Function();

/// Manages a local WebSocket server (for receiving) and an outgoing
/// WebSocket connection (for sending) to enable real-time chat on LAN.
///
/// Both sides run their own server. When device A opens chat with B:
///   - A connects to B's server as a client → A can SEND via this connection
///   - When B opens chat, B connects to A's server → A can RECEIVE from B's client
class WsChatService {
  WsChatService({
    required this.selfIp,
    required this.peerIp,
    required this.onMessage,
    this.onPeerConnected,
    this.onPeerDisconnected,
  });

  final String selfIp;
  final String peerIp;
  final OnMessageReceived onMessage;
  final OnPeerConnected? onPeerConnected;
  final OnPeerDisconnected? onPeerDisconnected;

  HttpServer? _server;
  WebSocket? _outgoing; // our connection to peer's server
  bool _started = false;
  bool _disposed = false;

  /// Start the local server and attempt to connect to the peer.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _startServer();
    await _connectToPeer();
  }

  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kChatWsPort);
      _server!.transform(WebSocketTransformer()).listen(
        (ws) {
          onPeerConnected?.call();
          ws.listen(
            (data) {
              if (data is String) {
                try {
                  final json = jsonDecode(data) as Map<String, dynamic>;
                  onMessage(json);
                } catch (_) {}
              }
            },
            onDone: () => onPeerDisconnected?.call(),
          );
        },
        onError: (_) {},
      );
    } catch (e) {
      // Port already in use — another chat might be open. Ignore for now.
    }
  }

  Future<void> _connectToPeer() async {
    if (_disposed) return;
    for (int attempt = 0; attempt < 10; attempt++) {
      if (_disposed) return;
      try {
        _outgoing = await WebSocket.connect(
          'ws://$peerIp:$kChatWsPort',
        ).timeout(const Duration(seconds: 3));
        _outgoing!.done.then((_) {
          if (!_disposed) _scheduleReconnect();
        });
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    // Could not connect — peer might not have the chat open yet
  }

  void _scheduleReconnect() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!_disposed) _connectToPeer();
    });
  }

  /// Send a JSON payload to the peer.
  bool send(Map<String, dynamic> payload) {
    if (_outgoing == null || _outgoing!.readyState != WebSocket.open) {
      return false;
    }
    try {
      _outgoing!.add(jsonEncode(payload));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get isConnected =>
      _outgoing != null && _outgoing!.readyState == WebSocket.open;

  Future<void> dispose() async {
    _disposed = true;
    await _outgoing?.close();
    await _server?.close(force: true);
    _outgoing = null;
    _server = null;
  }
}
