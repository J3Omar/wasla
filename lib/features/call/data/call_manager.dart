import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import '../domain/call_state.dart';
import '../../../core/network/network_utils.dart';
import 'call_audio_service.dart';

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
  Timer? _timeoutTimer; // 30s no-answer auto-end

  // Fix 2D — ICE candidate queue.
  // Remote candidates that arrive before setRemoteDescription completes are
  // stored here, then flushed immediately after the remote desc is applied.
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescSet = false;

  // Fix 2F — Android foreground service state.
  bool _backgroundActive = false;

  // Bug 3: ICE restart guard
  bool _iceRestartAttempted = false;

  /// Current session snapshot — updated by the notifier.
  CallSession _session = CallSession.idle;

  // ── Outgoing call (caller side) ───────────────────────────────────────────

  // Fix 2F — Foreground service helpers ──────────────────────────────────────

  /// Enable Android foreground service so the OS doesn't kill the call
  /// when the screen turns off or the app moves to the background.
  /// No-op on non-Android platforms.
  Future<void> _enableBackground() async {
    if (!Platform.isAndroid) return;
    try {
      const config = FlutterBackgroundAndroidConfig(
        notificationTitle: 'Wasla — Voice Call',
        notificationText: 'Call in progress',
        notificationImportance: AndroidNotificationImportance.high,
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      await FlutterBackground.initialize(androidConfig: config);
      _backgroundActive =
          await FlutterBackground.enableBackgroundExecution();
    } catch (_) {
      _backgroundActive = false;
    }
  }

  /// Disable the foreground service. Called from dispose() which is the
  /// single exit point for ALL call-end scenarios.
  void _disableBackground() {
    if (!Platform.isAndroid || !_backgroundActive) return;
    try {
      FlutterBackground.disableBackgroundExecution();
    } catch (_) {}
    _backgroundActive = false;
  }

  // ───────────────────────────────────────────────────────────────────────────

  /// Start an outgoing call to [peerId] at [peerIp].
  /// Spins up a local signaling WS server, sends UDP invite, waits for answer.
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required String peerIp,
  }) async {
    debugPrint('[CallManager] startCall invoked for $peerName ($peerIp)');
    _session = CallSession(
      state: CallState.outgoing,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
    );
    onStateChanged(_session);

    debugPrint('[CallManager] startCall: Enabling background service...');
    try {
      // Fix 2F — start foreground service before ICE negotiation begins
      await _enableBackground();
    } catch (e, stack) {
      debugPrint('[CallManager] startCall error in _enableBackground: $e\n$stack');
    }

    debugPrint('[CallManager] startCall: Playing ringback audio...');
    try {
      // Part 3 — play ringback on voiceCommunication stream
      await CallAudioService.instance.playRingback();
    } catch (e, stack) {
      debugPrint('[CallManager] startCall error in playRingback: $e\n$stack');
    }

    debugPrint('[CallManager] startCall: Generating random port...');
    // Pick a random signaling port
    final signalingPort = _kMinPort + Random().nextInt(_kMaxPort - _kMinPort);
    debugPrint('[CallManager] startCall: Selected port $signalingPort');

    debugPrint('[CallManager] startCall: Starting local signaling server...');
    try {
      // Start signaling server BEFORE sending invite so callee can connect
      await _startSignalingServer(signalingPort, isInitiator: true);
    } catch (e, stack) {
      debugPrint('[CallManager] startCall error in _startSignalingServer: $e\n$stack');
    }

    debugPrint('[CallManager] startCall: Sending UDP invite to $peerIp...');
    try {
      // Send UDP invite
      await _sendCallInvite(
        peerIp: peerIp,
        signalingPort: signalingPort,
        peerId: peerId,
        peerName: peerName,
      );
      debugPrint('[CallManager] startCall: UDP invite sent successfully.');
    } catch (e, stack) {
      debugPrint('[CallManager] startCall error in _sendCallInvite: $e\n$stack');
    }

    // 30-second no-answer timeout → auto-end with "missed" reason
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_session.state == CallState.outgoing) {
        CallAudioService.instance.stopAll(); // stop ringback
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: CallEndReason.missed,
        );
        onStateChanged(_session);
        dispose();
      }
    });
  }

  // ── Incoming call (callee side) ───────────────────────────────────────────

  /// Accept an incoming call.
  /// Connects to the caller's signaling server and sends SDP answer.
  Future<void> acceptCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    debugPrint('[CallManager] acceptCall invoked for $callerIp:$signalingPort');
    _session = _session.copyWith(state: CallState.connecting);
    onStateChanged(_session);

    debugPrint('[CallManager] acceptCall: Enabling background service...');
    try {
      // Fix 2F — start foreground service before ICE negotiation begins
      await _enableBackground();
    } catch (e, stack) {
      debugPrint('[CallManager] acceptCall error in _enableBackground: $e\n$stack');
    }

    debugPrint('[CallManager] acceptCall: Connecting to signaling server...');
    try {
      await _connectToSignalingServer(callerIp, signalingPort);
      debugPrint('[CallManager] acceptCall: Connected to signaling server successfully.');
    } catch (e, stack) {
      debugPrint('[CallManager] acceptCall error in _connectToSignalingServer: $e\n$stack');
    }
  }

  /// Decline an incoming call.
  /// Sends UDP decline packet (reliable — no WS needed before acceptance)
  /// and also attempts WS signal as fallback for mid-connecting state.
  Future<void> declineCall({
    required String callerIp,
    required int signalingPort,
  }) async {
    // Primary: UDP packet — works even before callee has opened WS
    await _sendDeclineUdp(peerIp: callerIp);
    // Fallback: WS signal in case WS is already open (mid-connect)
    try {
      await _sendSignal(
        callerIp,
        signalingPort,
        jsonEncode({'type': 'call_declined', 'from': selfUuid}),
      );
    } catch (_) {}
    _session = _session.copyWith(
      state: CallState.ended,
      endReason: CallEndReason.declined,
    );
    onStateChanged(_session);
    await dispose();
  }

  // Cancel timeout when call goes active (connection established)
  void _cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

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
    final wasActive = _session.state == CallState.active;
    // If still ringing (WS not yet established), notify via UDP cancel packet
    if (_session.state == CallState.outgoing && _session.peerIp.isNotEmpty) {
      await _sendCancelInvite(peerIp: _session.peerIp);
    } else {
      // Active/connecting — notify remote peer via existing WS
      try {
        _signalingWs?.add(jsonEncode({'type': 'call_ended', 'from': selfUuid}));
      } catch (_) {}
    }
    _session = _session.copyWith(
      state: CallState.ended,
      endReason: CallEndReason.normal,
    );
    onStateChanged(_session);
    // Strict teardown: WebRTC releases AudioManager first, then audio plays
    if (!kIsWeb && Platform.isAndroid) {
      try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media); } catch (_) {}
    }
    await CallAudioService.instance.stopAll();
    if (wasActive) await CallAudioService.instance.playEndSound();
    await dispose();
  }

  // ── WebRTC internals ─────────────────────────────────────────────────────

  static const _kMinPort = 46100;
  static const _kMaxPort = 46200;

  Future<MediaStream> _getLocalAudioStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'mandatory': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
          'googTypingNoiseDetection': true,
          'googAudioMirroring': false,
          'googEchoCancellationMobile': true,
        },
        'optional': [],
      },
      'video': false,
    };
    return await navigator.mediaDevices.getUserMedia(mediaConstraints);
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

    // Fix 2B+2C — when WebRTC connects, close the signaling server to free
    // the port. The WS client socket stays open so endCall() can still send
    // call_ended. _onWsClosed will NOT kill the call once state is active.
    pc.onConnectionState = (state) async {
      debugPrint('[Call] RTCPeerConnectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _iceRestartAttempted = false; // Reset on success
        _cancelTimeout();
        // Safety net only — audio handoff already happened before getUserMedia
        await CallAudioService.instance.stopAll();

        // Phase 2 — Caller broadcasts authoritative UTC start time to Callee
        // so both timers begin from the exact same origin.
        final nowIso = DateTime.now().toUtc().toIso8601String();
        try {
          _signalingWs?.add(jsonEncode({
            'type': 'call_start_sync',
            'startedAt': nowIso,
          }));
        } catch (_) {}

        // Free the listening port — no more SDP/ICE needed
        _signalingServer?.close().catchError((_) {});
        _signalingServer = null;
        _session = _session.copyWith(
          state: CallState.active,
          startedAt: DateTime.now().toUtc(),
        );
        onStateChanged(_session);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        
        if (!_iceRestartAttempted) {
           _iceRestartAttempted = true;
           debugPrint('[Call] Attempting ICE restart due to Disconnected/Failed state...');
           await _pc?.restartIce();
           
           // Fallback terminator: If it doesn't recover within 10 seconds, end it cleanly
           Future.delayed(const Duration(seconds: 10), () async {
             if (_pc?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
               await endCall();
             }
           });
        }
      }
    };

    // Fix 2C — debug logging so we can track exactly which state it stalls at
    pc.onIceConnectionState = (state) {
      debugPrint('[Call] ICE connection state: $state');
    };
    pc.onIceGatheringState = (state) {
      debugPrint('[Call] ICE gathering state: $state');
    };
    pc.onSignalingState = (state) {
      debugPrint('[Call] Signaling state: $state');
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
      // Callee just connected (= accepted the call) — cancel no-answer timeout
      _cancelTimeout();
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
    // Strict audio handoff sequence (Phase 1 Fix):
    // Stop looping audio → release AudioFocus → WebRTC takes over AudioManager
    await CallAudioService.instance.stopAll();
    await CallAudioService.instance.releaseAudioFocus();
    if (!kIsWeb && Platform.isAndroid) {
      try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication); } catch (_) {}
    }
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
        // Strict audio handoff sequence (Phase 1 Fix):
        // Stop looping audio → release AudioFocus → WebRTC takes over AudioManager
        await CallAudioService.instance.stopAll();
        await CallAudioService.instance.releaseAudioFocus();
        if (!kIsWeb && Platform.isAndroid) {
          try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication); } catch (_) {}
        }
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
        // Fix 2D — remote desc is now set; flush any ICE candidates that
        // arrived while the offer was being processed.
        _remoteDescSet = true;
        for (final c in _pendingCandidates) {
          await _pc?.addCandidate(c);
        }
        _pendingCandidates.clear();

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
        // Fix 2D — remote desc is now set on the caller side too; flush queue.
        _remoteDescSet = true;
        for (final c in _pendingCandidates) {
          await _pc?.addCandidate(c);
        }
        _pendingCandidates.clear();
        break;

      case 'call_start_sync':
        // Phase 2 — Callee receives the Caller's authoritative UTC start time.
        // Parsing it and storing in _session means the UI timer on both devices
        // computes elapsed from the same shared origin — no drift.
        final raw = signal['startedAt'] as String?;
        if (raw != null) {
          final callerStart = DateTime.parse(raw).toLocal();
          _session = _session.copyWith(
            state: CallState.active,
            startedAt: callerStart,
          );
          onStateChanged(_session);
        }
        break;

      case 'ice':
        final c = signal['candidate'];
        final candidate = RTCIceCandidate(
          c['candidate'] as String,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        );
        if (!_remoteDescSet) {
          // Queue it — setRemoteDescription hasn't finished yet
          _pendingCandidates.add(candidate);
        } else {
          await _pc?.addCandidate(candidate);
        }
        break;

      case 'call_declined':
        final count = _session.declineCount + 1;
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: count >= 3 ? CallEndReason.busy : CallEndReason.declined,
          declineCount: count,
        );
        onStateChanged(_session);
        if (!kIsWeb && Platform.isAndroid) {
          try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media); } catch (_) {}
        }
        await CallAudioService.instance.stopAll();
        await CallAudioService.instance.playEndSound();
        await dispose();
        break;

      case 'call_ended':
        _session = _session.copyWith(
          state: CallState.ended,
          endReason: CallEndReason.normal,
        );
        onStateChanged(_session);
        if (!kIsWeb && Platform.isAndroid) {
          try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media); } catch (_) {}
        }
        await CallAudioService.instance.stopAll();
        await CallAudioService.instance.playEndSound();
        await dispose();
        break;
    }
  }

  void _onWsClosed() {
    // Fix 2B — if WebRTC is already active, the WS closing is expected
    // (we closed _signalingServer above). Do NOT kill the live call.
    if (_session.state == CallState.active) return;

    // WS died during negotiation (connecting) — treat as network loss
    if (_session.state == CallState.connecting) {
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
      // Use getBestLocalIpFor so hotspot hosts embed the correct interface IP
      final localIp = await getBestLocalIpFor(peerIp);
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(jsonEncode({
        'type': 'call_invite',
        'from': selfUuid,
        'fromName': selfName,
        'signalingPort': signalingPort,
        // callerIp lets the callee use the correct interface IP explicitly;
        // falls back to UDP source address if missing
        'callerIp': localIp,
      }));
      socket.send(
        payload,
        InternetAddress(peerIp),
        kCallInviteUdpPort,
      );
      socket.close();
    } catch (_) {}
  }

  /// Sends a UDP packet telling the callee the call was cancelled
  /// (used when caller hangs up before callee accepts).
  Future<void> _sendCancelInvite({required String peerIp}) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(jsonEncode({
        'type': 'call_cancelled',
        'from': selfUuid,
      }));
      socket.send(payload, InternetAddress(peerIp), kCallInviteUdpPort);
      socket.close();
    } catch (_) {}
  }

  /// Sends a UDP packet telling the caller the call was declined.
  /// Primary path for decline — doesn't need a WS connection.
  Future<void> _sendDeclineUdp({required String peerIp}) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(jsonEncode({
        'type': 'call_declined',
        'from': selfUuid,
      }));
      socket.send(payload, InternetAddress(peerIp), kCallInviteUdpPort);
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
    _disableBackground(); // Fix 2F — release foreground service in ALL cases
    // Safety net: release WebRTC AudioManager in case dispose() fires directly
    if (!kIsWeb && Platform.isAndroid) {
      try { await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media); } catch (_) {}
    }
    await CallAudioService.instance.stopAll(); // safety net — idempotent
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
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
