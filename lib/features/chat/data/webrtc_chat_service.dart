import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import '../domain/chat_message.dart';
import 'chat_database.dart';

/// Provider to access the singleton WebRTC chat service.
final webrtcChatServiceProvider = Provider<WebRtcChatService>((ref) {
  final service = WebRtcChatService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ── Constants ──────────────────────────────────────────────────────────────────

/// Port used for chat signaling WebSocket servers (one per caller session, random).
/// We pick a random port each time to avoid conflicts.
const _kSignalingPortMin = 45000;
const _kSignalingPortMax = 46000;

/// UDP port for sending "chat invite" packets to wake up the signaling channel.
/// NOTE: Discovery uses port 45678, so we use 45679 here.
const kChatInviteUdpPort = 45679;

/// Fallback WebSocket port — used when WebRTC fails, for direct LAN messaging.
const kChatWsFallbackPort = 8766;

// ── WebRTC Configuration ───────────────────────────────────────────────────────

/// No STUN/TURN — we are 100% LAN only.
final _rtcConfig = <String, dynamic>{
  'iceServers': [],
  'iceTransportPolicy': 'all',
};

// ── Session tracking ───────────────────────────────────────────────────────────

class _PeerSession {
  _PeerSession({required this.peerId, required this.peerIp});
  final String peerId;
  final String peerIp;
  RTCPeerConnection? pc;
  RTCDataChannel? dataChannel;
  HttpServer? signalingServer;
  WebSocket? signalingWs;
  bool isConnected = false;
  bool isInitiator = false;
}

// ── WebRtcChatService ──────────────────────────────────────────────────────────

/// Manages WebRTC peer connections for chat data channels.
/// One RTCPeerConnection per unique peer device.
/// 
/// Message flow:
///   Sender: sendChatMessage() → DataChannel → Receiver gets it in _onDataChannelMessage()
///   Receiver: automatically sends ack_delivered → Sender updates to delivered
///   Receiver opens chat: ChatNotifier calls sendAckRead() → Sender updates to read
class WebRtcChatService {
  final Map<String, _PeerSession> _sessions = {};
  Timer? _retryTimer;

  /// The UUID of the peer whose chat screen is currently visible.
  String? activeChatPeerId;

  /// Our own UUID and display name (loaded at startup).
  String? selfUuid;
  String? selfName;

  /// UDP socket for receiving chat invite packets.
  RawDatagramSocket? _inviteSocket;

  /// Called when a new message arrives (for notifications, UI updates).
  /// Signature: (senderUuid, senderName, content)
  Function(String, String, String)? onMessageReceived;

  // ── Startup ──────────────────────────────────────────────────────────────

  Future<void> start() async {
    await _startInviteListener();
    // Retry queued messages every 5 seconds
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _flushQueue());
  }

  /// Start listening for incoming "chat invite" UDP packets.
  Future<void> _startInviteListener() async {
    try {
      _inviteSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kChatInviteUdpPort,
        reuseAddress: true,
      );
      _inviteSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _inviteSocket!.receive();
        if (dg == null) return;
        try {
          final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (json['type'] == 'chat_invite') {
            _handleChatInvite(json, dg.address.address);
          }
        } catch (_) {}
      });
    } catch (e) {
      // Port already in use (shared with discovery service) — ignore
    }
  }

  // ── Sending a message ─────────────────────────────────────────────────────

  /// Send a text message to a peer. Returns true if sent immediately.
  Future<bool> sendChatMessage({
    required String peerId,
    required String peerIp,
    required ChatMessage message,
  }) async {
    final session = _sessions[peerId];

    // If data channel is open, send directly
    if (session?.isConnected == true && session?.dataChannel != null) {
      return _sendOnDataChannel(session!, message);
    }

    // Otherwise, initiate WebRTC connection then send
    final newSession = await _initiateConnection(peerId, peerIp);
    if (newSession?.isConnected == true) {
      return _sendOnDataChannel(newSession!, message);
    }

    // WebRTC failed — message stays queued, retry timer will retry
    return false;
  }

  bool _sendOnDataChannel(_PeerSession session, ChatMessage message) {
    try {
      final dc = session.dataChannel;
      if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) return false;
      dc.send(RTCDataChannelMessage(jsonEncode({
        'type': 'msg',
        'id': message.messageUuid,
        'senderId': selfUuid,
        'senderName': selfName ?? 'Unknown',
        'content': message.content,
        'ts': message.timestamp.millisecondsSinceEpoch,
      })));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Send ack_read for a specific message UUID back to the sender.
  Future<void> sendAckRead({required String peerIp, required String peerId, required String messageUuid}) async {
    final session = _sessions[peerId];
    if (session?.isConnected == true && session?.dataChannel != null) {
      try {
        session!.dataChannel!.send(RTCDataChannelMessage(jsonEncode({
          'type': 'ack_read',
          'messageId': messageUuid,
        })));
      } catch (_) {}
    }
  }

  /// Send bulk ack_read_all (when opening chat with unread messages).
  Future<void> sendAckReadAll({required String peerIp, required String peerId, required int upToTimestamp}) async {
    final ip = peerIp.isNotEmpty ? peerIp : ChatDatabase.instance.getPeerIp(peerId);
    if (ip == null || ip.isEmpty) return; // Cannot connect without an IP

    var session = _sessions[peerId];

    if (session == null || !session.isConnected) {
      session = await _initiateConnection(peerId, ip);
    }

    if (session?.isConnected == true && session?.dataChannel != null) {
      try {
        session!.dataChannel!.send(RTCDataChannelMessage(jsonEncode({
          'type': 'ack_read_all',
          'chatId': peerId,
          'upToTimestamp': upToTimestamp,
        })));
      } catch (_) {}
    }
  }

  // ── WebRTC Connection Initiation (Caller side) ────────────────────────────

  Future<_PeerSession?> _initiateConnection(String peerId, String peerIp) async {
    // Clean up any stale session
    await _closeSession(peerId);

    final session = _PeerSession(peerId: peerId, peerIp: peerIp)
      ..isInitiator = true;
    _sessions[peerId] = session;

    // 1. Bind a local signaling WebSocket server
    final sigPort = _randomPort();
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, sigPort, shared: true)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
    session.signalingServer = server;

    // 2. Wait for the callee to connect, then do SDP exchange
    final completer = Completer<bool>();

    server.transform(WebSocketTransformer()).listen((ws) async {
      session.signalingWs = ws;
      final connected = await _doCallerHandshake(session, ws);
      if (!completer.isCompleted) completer.complete(connected);
    });

    // 3. Send UDP invite to tell the peer to connect to our signaling server
    final selfIp = await _getSelfIp();
    await _sendUdpInvite(peerIp, selfIp, sigPort, peerId);

    // 4. Wait up to 8 seconds for connection
    try {
      final ok = await completer.future.timeout(const Duration(seconds: 8));
      if (!ok) await _closeSession(peerId);
      return ok ? session : null;
    } catch (_) {
      await _closeSession(peerId);
      return null;
    }
  }

  Future<bool> _doCallerHandshake(_PeerSession session, WebSocket ws) async {
    final connected = Completer<bool>();

    final pc = await createPeerConnection(_rtcConfig);
    session.pc = pc;

    // Create data channel BEFORE offer
    final dc = await pc.createDataChannel('chat', RTCDataChannelInit()..ordered = true);
    session.dataChannel = dc;
    _setupDataChannel(dc, session);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        ws.add(jsonEncode({'type': 'ice', 'candidate': candidate.toMap()}));
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        session.isConnected = true;
        if (!connected.isCompleted) connected.complete(true);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        session.isConnected = false;
        if (!connected.isCompleted) connected.complete(false);
      }
    };

    // Listen for SDP answer + ICE from callee
    ws.listen((data) async {
      try {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'answer') {
          await pc.setRemoteDescription(RTCSessionDescription(msg['sdp'], 'answer'));
        } else if (msg['type'] == 'ice') {
          await pc.addCandidate(RTCIceCandidate(
            msg['candidate']['candidate'],
            msg['candidate']['sdpMid'],
            msg['candidate']['sdpMLineIndex'],
          ));
        }
      } catch (_) {}
    }, onError: (_) {
      if (!connected.isCompleted) connected.complete(false);
    });

    // Create and send offer
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      ws.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));
    } catch (_) {
      return false;
    }

    return connected.future;
  }

  // ── WebRTC Connection Handling (Callee side) ──────────────────────────────

  void _handleChatInvite(Map<String, dynamic> json, String fromIp) async {
    final sigIp = json['signalingIp'] as String? ?? fromIp;
    final sigPort = json['signalingPort'] as int?;
    final fromUuid = json['fromUuid'] as String?;

    if (sigPort == null || fromUuid == null) return;

    // Clean up any stale session with this peer
    await _closeSession(fromUuid);

    final session = _PeerSession(peerId: fromUuid, peerIp: fromIp);
    _sessions[fromUuid] = session;

    // Connect to the caller's signaling server
    WebSocket ws;
    try {
      ws = await WebSocket.connect('ws://$sigIp:$sigPort')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    session.signalingWs = ws;

    await _doCalleeHandshake(session, ws);
  }

  Future<void> _doCalleeHandshake(_PeerSession session, WebSocket ws) async {
    final pc = await createPeerConnection(_rtcConfig);
    session.pc = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        ws.add(jsonEncode({'type': 'ice', 'candidate': candidate.toMap()}));
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        session.isConnected = true;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        session.isConnected = false;
        _sessions.remove(session.peerId);
      }
    };

    pc.onDataChannel = (dc) {
      session.dataChannel = dc;
      _setupDataChannel(dc, session);
    };

    ws.listen((data) async {
      try {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'offer') {
          await pc.setRemoteDescription(RTCSessionDescription(msg['sdp'], 'offer'));
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          ws.add(jsonEncode({'type': 'answer', 'sdp': answer.sdp}));
        } else if (msg['type'] == 'ice') {
          await pc.addCandidate(RTCIceCandidate(
            msg['candidate']['candidate'],
            msg['candidate']['sdpMid'],
            msg['candidate']['sdpMLineIndex'],
          ));
        }
      } catch (_) {}
    }, onError: (_) {});
  }

  // ── Data Channel Message Handling ────────────────────────────────────────

  void _setupDataChannel(RTCDataChannel dc, _PeerSession session) {
    dc.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        session.isConnected = true;
      } else if (state == RTCDataChannelState.RTCDataChannelClosed ||
                 state == RTCDataChannelState.RTCDataChannelClosing) {
        session.isConnected = false;
      }
    };

    dc.onMessage = (msg) {
      try {
        final json = jsonDecode(msg.text) as Map<String, dynamic>;
        _handleDataChannelMessage(json, session, dc);
      } catch (_) {}
    };
  }

  void _handleDataChannelMessage(
    Map<String, dynamic> json,
    _PeerSession session,
    RTCDataChannel dc,
  ) {
    final type = json['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'msg':
        _handleIncomingMessage(json, session, dc);
        break;

      case 'ack_delivered':
        final msgId = json['messageId'] as String?;
        if (msgId != null) {
          ChatDatabase.instance.updateStatusByUuid(msgId, MessageStatus.delivered);
        }
        break;

      case 'ack_read':
        final msgId = json['messageId'] as String?;
        if (msgId != null) {
          ChatDatabase.instance.updateStatusByUuid(msgId, MessageStatus.read);
        }
        break;

      case 'ack_read_all':
        final ts = (json['upToTimestamp'] as num?)?.toInt();
        if (ts != null) {
          // Mark all sent messages up to this timestamp as read
          ChatDatabase.instance.updateStatusByTimestamp(ts, MessageStatus.read);
        }
        break;
    }
  }

  void _handleIncomingMessage(
    Map<String, dynamic> json,
    _PeerSession session,
    RTCDataChannel dc,
  ) {
    final msgId = json['id'] as String? ?? '';
    final senderId = json['senderId'] as String?;
    final senderName = json['senderName'] as String? ?? 'Unknown';
    final content = json['content'] as String? ?? '';
    final ts = (json['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    if (senderId == null || content.isEmpty) return;

    // Deduplicate (WebRTC can rarely re-deliver)
    if (msgId.isNotEmpty && ChatDatabase.instance.hasMessage(msgId)) return;

    // Persist the peer's name
    ChatDatabase.instance.upsertPeer(senderId, senderName);

    final msg = ChatMessage(
      id: 0,
      messageUuid: msgId,
      peerId: senderId,
      content: content,
      isSent: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      status: MessageStatus.delivered,
      type: MessageType.text,
    );
    ChatDatabase.instance.insert(msg);

    // Always send delivered ACK
    try {
      dc.send(RTCDataChannelMessage(jsonEncode({
        'type': 'ack_delivered',
        'messageId': msgId,
      })));
    } catch (_) {}

    // If user is in this chat, send read ACK immediately
    if (activeChatPeerId == senderId) {
      ChatDatabase.instance.markAllRead(senderId);
      try {
        dc.send(RTCDataChannelMessage(jsonEncode({
          'type': 'ack_read',
          'messageId': msgId,
        })));
      } catch (_) {}
    }

    // Notify UI layer (for in-app banners or system notifications)
    onMessageReceived?.call(senderId, senderName, content);
  }

  // ── Offline Queue ─────────────────────────────────────────────────────────

  Future<void> _flushQueue() async {
    if (selfUuid == null || selfName == null) return;

    final unsent = ChatDatabase.instance.getUnsentMessages();
    if (unsent.isEmpty) return;

    for (final msg in unsent) {
      final peerIp = ChatDatabase.instance.getPeerIp(msg.peerId);
      if (peerIp == null || peerIp.isEmpty) continue;

      final sent = await sendChatMessage(
        peerId: msg.peerId,
        peerIp: peerIp,
        message: msg,
      );

      if (sent) {
        ChatDatabase.instance.updateStatus(msg.id, MessageStatus.sent);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _sendUdpInvite(String peerIp, String selfIp, int sigPort, String peerId) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(jsonEncode({
        'type': 'chat_invite',
        'signalingIp': selfIp,
        'signalingPort': sigPort,
        'fromUuid': selfUuid ?? '',
        'targetUuid': peerId,
      }));
      socket.send(payload, InternetAddress(peerIp), kChatInviteUdpPort);
      // Send 3 times to reduce UDP packet loss chance
      await Future.delayed(const Duration(milliseconds: 100));
      socket.send(payload, InternetAddress(peerIp), kChatInviteUdpPort);
      await Future.delayed(const Duration(milliseconds: 100));
      socket.send(payload, InternetAddress(peerIp), kChatInviteUdpPort);
      socket.close();
    } catch (_) {}
  }

  Future<String> _getSelfIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('127.') && !ip.startsWith('169.254')) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  int _randomPort() {
    final rng = Random();
    return _kSignalingPortMin + rng.nextInt(_kSignalingPortMax - _kSignalingPortMin);
  }

  Future<void> _closeSession(String peerId) async {
    final session = _sessions.remove(peerId);
    if (session == null) return;
    try { await session.dataChannel?.close(); } catch (_) {}
    try { await session.pc?.close(); } catch (_) {}
    try { await session.signalingServer?.close(); } catch (_) {}
    try { await session.signalingWs?.close(); } catch (_) {}
    session.isConnected = false;
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _inviteSocket?.close();
    for (final peerId in _sessions.keys.toList()) {
      await _closeSession(peerId);
    }
  }
}
