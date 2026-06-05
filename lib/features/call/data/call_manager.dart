import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import '../domain/call_state.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

/// UDP port for call invite packets (discovery=45678, chat=45679, call=45680).
const kCallInviteUdpPort = 45680;

/// WebRTC config — LAN only, no STUN/TURN.
final _rtcConfig = <String, dynamic>{
  'iceServers': [],
  'iceTransportPolicy': 'all',
};

// ── CallManager ───────────────────────────────────────────────────────────────

/// Manages the WebRTC PeerConnection for a voice call.
/// One instance per call session — create a fresh one for each call.
class CallManager {
  CallManager({
    required this.selfUuid,
    required this.selfName,
    required this.onStateChanged,
  });

  final String selfUuid;
  final String selfName;
  final ValueChanged<CallSession> onStateChanged;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  HttpServer? _signalingServer;
  WebSocket? _signalingWs;

  /// Current session snapshot — updated by the notifier.
  CallSession _session = CallSession.idle;

  // ── Outgoing call (caller side) ───────────────────────────────────────────

  /// Start an outgoing call to [peerId] at [peerIp].
  /// Spins up a local signaling WS server, sends UDP invite, waits for answer.
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required String peerIp,
  }) async {
    _session = CallSession(
      state: CallState.outgoing,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
    );
    onStateChanged(_session);

    // Pick a random signaling port
    final signalingPort = _kMinPort + Random().nextInt(_kMaxPort - _kMinPort);

    // Start signaling server BEFORE sending invite so callee can connect
    await _startSignalingServer(signalingPort, isInitiator: true);

    // Send UDP invite
    await _sendCallInvite(
      peerIp: peerIp,
      signalingPort: signalingPort,
      peerId: peerId,
      peerName: peerName,
    );
  }

  // ── Incoming call (callee side) ───────────────────────────────────────────

  /// Accept an incoming call.
  /// Connects to the caller's signaling server and sends SDP answer.
  Future<void> acceptCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    _session = _session.copyWith(state: CallState.connecting);
    onStateChanged(_session);

    await _connectToSignalingServer(callerIp, signalingPort);
  }

  /// Decline an incoming call — sends a decline packet back to caller.
  Future<void> declineCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    await _sendSignal(
      callerIp,
      signalingPort,
      jsonEncode({'type': 'call_declined', 'from': selfUuid}),
    );
    _session = _session.copyWith(
      state: CallState.ended,
      endReason: CallEndReason.declined,
    );
    onStateChanged(_session);
    await dispose();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  void toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !t.enabled;
    }
    _session = _session.copyWith(isMuted: !_session.isMuted);
    onStateChanged(_session);
  }

  void toggleSpeaker() {
    // flutter_webrtc exposes Helper.setSpeakerphoneOn
    Helper.setSpeakerphoneOn(!_session.isSpeakerOn);
    _session = _session.copyWith(isSpeakerOn: !_session.isSpeakerOn);
    onStateChanged(_session);
  }

  Future<void> endCall() async {
    _session = _session.copyWith(
      state: CallState.ended,
      endReason: CallEndReason.normal,
    );
    onStateChanged(_session);
    // Notify remote peer
    try {
      _signalingWs?.add(jsonEncode({'type': 'call_ended', 'from': selfUuid}));
    } catch (_) {}
    await dispose();
  }

  // ── WebRTC internals ─────────────────────────────────────────────────────

  static const _kMinPort = 46100;
  static const _kMaxPort = 46200;

  Future<MediaStream> _getLocalAudioStream() async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_rtcConfig);

    pc.onIceCandidate = (candidate) {
      try {
        _signalingWs?.add(jsonEncode({
          'type': 'ice',
          'candidate': candidate.toMap(),
        }));
      } catch (_) {}
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _session = _session.copyWith(
          state: CallState.active,
          startedAt: DateTime.now(),
        );
        onStateChanged(_session);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: CallEndReason.networkLoss,
        );
        onStateChanged(_session);
        dispose();
      }
    };

    pc.onTrack = (event) {
      // Remote audio track — flutter_webrtc handles playback automatically
    };

    return pc;
  }

  Future<void> _startSignalingServer(int port, {required bool isInitiator}) async {
    _signalingServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _signalingServer!.transform(WebSocketTransformer()).listen((ws) async {
      _signalingWs = ws;
      if (isInitiator) {
        await _initiateOffer();
      }
      ws.listen(
        (data) => _handleSignal(jsonDecode(data as String)),
        onDone: _onWsClosed,
        onError: (_) => _onWsClosed(),
      );
    });
  }

  Future<void> _connectToSignalingServer(String ip, int port) async {
    _signalingWs = await WebSocket.connect('ws://$ip:$port');
    _signalingWs!.listen(
      (data) => _handleSignal(jsonDecode(data as String)),
      onDone: _onWsClosed,
      onError: (_) => _onWsClosed(),
    );
  }

  Future<void> _initiateOffer() async {
    _localStream = await _getLocalAudioStream();
    _pc = await _createPeerConnection();
    for (final track in _localStream!.getAudioTracks()) {
      _pc!.addTrack(track, _localStream!);
    }
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _signalingWs?.add(jsonEncode({'type': 'offer', 'sdp': offer.toMap()}));
  }

  void _handleSignal(Map<String, dynamic> signal) async {
    switch (signal['type']) {
      case 'offer':
        _localStream = await _getLocalAudioStream();
        _pc = await _createPeerConnection();
        for (final track in _localStream!.getAudioTracks()) {
          _pc!.addTrack(track, _localStream!);
        }
        await _pc!.setRemoteDescription(
          RTCSessionDescription(
            signal['sdp']['sdp'] as String,
            signal['sdp']['type'] as String,
          ),
        );
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _signalingWs?.add(jsonEncode({'type': 'answer', 'sdp': answer.toMap()}));
        break;

      case 'answer':
        await _pc?.setRemoteDescription(
          RTCSessionDescription(
            signal['sdp']['sdp'] as String,
            signal['sdp']['type'] as String,
          ),
        );
        break;

      case 'ice':
        final c = signal['candidate'];
        await _pc?.addCandidate(
          RTCIceCandidate(
            c['candidate'] as String,
            c['sdpMid'] as String?,
            c['sdpMLineIndex'] as int?,
          ),
        );
        break;

      case 'call_declined':
        final count = _session.declineCount + 1;
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: count >= 3 ? CallEndReason.busy : CallEndReason.declined,
          declineCount: count,
        );
        onStateChanged(_session);
        await dispose();
        break;

      case 'call_ended':
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: CallEndReason.normal,
        );
        onStateChanged(_session);
        await dispose();
        break;
    }
  }

  void _onWsClosed() {
    if (_session.state == CallState.active ||
        _session.state == CallState.connecting) {
      _session = _session.copyWith(
        state: CallState.ended,
        endReason: CallEndReason.networkLoss,
      );
      onStateChanged(_session);
    }
    dispose();
  }

  Future<void> _sendCallInvite({
    required String peerIp,
    required int signalingPort,
    required String peerId,
    required String peerName,
  }) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(jsonEncode({
        'type': 'call_invite',
        'from': selfUuid,
        'fromName': selfName,
        'signalingPort': signalingPort,
      }));
      socket.send(
        payload,
        InternetAddress(peerIp),
        kCallInviteUdpPort,
      );
      socket.close();
    } catch (_) {}
  }

  Future<void> _sendSignal(String ip, int port, String data) async {
    try {
      final ws = await WebSocket.connect('ws://$ip:$port');
      ws.add(data);
      await ws.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      await _pc?.close();
      await _signalingServer?.close();
      await _signalingWs?.close();
    } catch (_) {}
    _localStream = null;
    _pc = null;
    _signalingServer = null;
    _signalingWs = null;
  }
}
