import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import '../domain/call_state.dart';
import '../../../core/network/network_utils.dart';
import 'call_audio_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/utils/background_service_manager.dart';

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

  MediaStream? _localVideoStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _isVideoOn = false;

  RTCVideoRenderer? get localRenderer => _localRenderer;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;

  HttpServer? _signalingServer;
  WebSocket? _signalingWs;
  Timer? _timeoutTimer; // 30s no-answer auto-end

  Timer? _heartbeatTimer;
  int _missedHeartbeats = 0;
  static const _kMaxMissedHeartbeats = 3;

  Timer? _maxDurationTimer;
  static const _kMaxCallDuration = Duration(hours: 3);

  // Fix 2D — ICE candidate queue.
  // Remote candidates that arrive before setRemoteDescription completes are
  // stored here, then flushed immediately after the remote desc is applied.
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescSet = false;

  // Bug 3: UDP reconnect guard
  bool _reconnectAttempted = false;
  // Bug 1 fix: cancellation token for the delayed endCall after ICE failure
  bool _iceEndCallPending = false;
  // Bug 2 fix: track which side we are on for fallback timer sync
  bool _isInitiator = false;
  bool _isReconnecting = false;

  /// Current session snapshot — updated by the notifier.
  CallSession _session = CallSession.idle;

  // ── Outgoing call (caller side) ───────────────────────────────────────────

  // Fix 2F — Foreground service helpers ──────────────────────────────────────

  /// Enable Android foreground service so the OS doesn't kill the call
  /// when the screen turns off or the app moves to the background.
  /// No-op on non-Android platforms.
  Future<void> _enableBackground() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    await BackgroundServiceManager.instance.acquire('call');
  }

  /// Disable the foreground service. Called from dispose() which is the
  /// single exit point for ALL call-end scenarios.
  void _disableBackground() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    BackgroundServiceManager.instance.release('call');
  }

  // ───────────────────────────────────────────────────────────────────────────

  /// Start an outgoing call to [peerId] at [peerIp].
  /// Spins up a local signaling WS server, sends UDP invite, waits for answer.
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required String peerIp,
    bool isVideo = false,
  }) async {
    debugPrint('[CallManager] startCall invoked for $peerName ($peerIp)');
    _session = CallSession(
      state: CallState.outgoing,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
    );
    onStateChanged(_session);

    if (isVideo) {
      await toggleVideo();
    }

    debugPrint('[CallManager] startCall: Enabling background service...');
    try {
      // Fix 2F — start foreground service before ICE negotiation begins
      await _enableBackground();
    } catch (e, stack) {
      debugPrint(
        '[CallManager] startCall error in _enableBackground: $e\n$stack',
      );
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
      debugPrint(
        '[CallManager] startCall error in _startSignalingServer: $e\n$stack',
      );
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
      debugPrint('[CallManager] _sendCallInvite: $e\n$stack');
    }

    // 30-second no-answer timeout → auto-end with "missed" reason
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_session.state == CallState.outgoing) {
        CallAudioService.instance.stopAll(); // stop ringback
        // Tell the callee to stop ringing before we dispose
        _sendCancelInvite(peerIp: _session.peerIp);

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
      debugPrint(
        '[CallManager] acceptCall error in _enableBackground: $e\n$stack',
      );
    }

    debugPrint('[CallManager] acceptCall: Connecting to signaling server...');
    try {
      await _connectToSignalingServer(callerIp, signalingPort);
      debugPrint(
        '[CallManager] acceptCall: Connected to signaling server successfully.',
      );
    } catch (e, stack) {
      debugPrint(
        '[CallManager] SocketException: Could not connect to signaling server: $e\n$stack',
      );
      await endCall();
      return;
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
    if (Platform.isAndroid || Platform.isIOS) {
      Helper.setSpeakerphoneOn(!_session.isSpeakerOn);
    }
    _session = _session.copyWith(isSpeakerOn: !_session.isSpeakerOn);
    onStateChanged(_session);
  }

  Future<void> toggleVideo() async {
    if (!_isVideoOn) {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final hasCamera = devices.any((d) => d.kind == 'videoinput');
      if (!hasCamera) throw Exception('NO_CAMERA');

      _localVideoStream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'facingMode': 'user',
        },
        'audio': false,
      });
      _localRenderer ??= RTCVideoRenderer();
      await _localRenderer!.initialize();
      _localRenderer!.srcObject = _localVideoStream;
      if (_pc != null) {
        await _pc!.addTrack(
          _localVideoStream!.getVideoTracks().first,
          _localVideoStream!,
        );
      }
      _isVideoOn = true;
      _session = _session.copyWith(isLocalVideoOn: true);
    } else {
      final track = _localVideoStream?.getVideoTracks().first;
      if (track != null && _pc != null) {
        final senders = await _pc!.getSenders();
        for (var sender in senders) {
          if (sender.track?.id == track.id) {
            await _pc!.removeTrack(sender);
            break;
          }
        }
      }
      _localRenderer?.srcObject = null;
      _localVideoStream?.getVideoTracks().forEach((t) => t.stop());
      await _localVideoStream?.dispose();
      _localVideoStream = null;
      _isVideoOn = false;
      _session = _session.copyWith(isLocalVideoOn: false);
    }
    onStateChanged(_session);
  }

  Future<void> switchCamera() async {
    if (_isVideoOn && _localVideoStream != null) {
      await Helper.switchCamera(_localVideoStream!.getVideoTracks().first);
      _session = _session.copyWith(isFrontCamera: !_session.isFrontCamera);
      onStateChanged(_session);
    }
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
    // Correct teardown sequence (Bug 3):
    // 1. Return AudioManager to media mode — releases WebRTC's AudioFocus
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.media,
        );
      } catch (_) {}
    }
    // 2. Stop looping audio (ringback, ringtone)
    await CallAudioService.instance.stopAll();
    if (_isReconnecting) {
      _isReconnecting = false;
      CallAudioService.instance.stopReconnecting();
    }
    // 3. NOW audioplayers can acquire focus — await so chime plays fully
    if (wasActive) {
      await CallAudioService.instance.playEndSound();
    }
    // 4. Dispose WebRTC AFTER the chime is done
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
        _signalingWs?.add(
          jsonEncode({'type': 'ice', 'candidate': candidate.toMap()}),
        );
      } catch (_) {}
    };

    // Fix 2B+2C — when WebRTC connects, close the signaling server to free
    // the port. The WS client socket stays open so endCall() can still send
    // call_ended. _onWsClosed will NOT kill the call once state is active.
    pc.onConnectionState = (state) async {
      debugPrint('[Call] RTCPeerConnectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _reconnectAttempted = false; // Reset on success
        _iceEndCallPending = false; // Cancel any pending zombie timer
        _cancelTimeout();
        // Safety net only — audio handoff already happened before getUserMedia
        await CallAudioService.instance.stopAll();

        if (_isReconnecting) {
          _isReconnecting = false;
          // 500ms delay before stopping —
          // lets the 1-second loop finish naturally
          await Future.delayed(const Duration(milliseconds: 500));
          CallAudioService.instance.stopReconnecting();
        }

        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _missedHeartbeats = 0;
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
          try {
            _signalingWs?.add(jsonEncode({'type': 'ping'}));
          } catch (_) {
            _missedHeartbeats++;
            if (_missedHeartbeats >= _kMaxMissedHeartbeats) {
              debugPrint('[Call] Heartbeat lost — ending call');
              await endCall();
            }
          }
        });

        _maxDurationTimer?.cancel();
        _maxDurationTimer = Timer(_kMaxCallDuration, () async {
          debugPrint('[Call] Max call duration reached — ending call');
          await endCall();
        });

        // Phase 2 — Caller broadcasts authoritative UTC start time to Callee
        // so both timers begin from the exact same origin.
        final nowIso = DateTime.now().toUtc().toIso8601String();
        try {
          _signalingWs?.add(
            jsonEncode({'type': 'call_start_sync', 'startedAt': nowIso}),
          );
        } catch (_) {}

        if (!kIsWeb && Platform.isAndroid) {
          try {
            await Helper.setSpeakerphoneOn(false);
          } catch (_) {}
        }
        _session = _session.copyWith(
          state: CallState.active,
          isSpeakerOn: false,
          startedAt: DateTime.now().toUtc(),
        );
        onStateChanged(_session);

        // Bug 2 fix: Callee-side fallback if call_start_sync WS message was lost.
        // After 500ms, if startedAt is still null on callee, seed it locally.
        if (!_isInitiator) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_session.startedAt == null) {
              _session = _session.copyWith(startedAt: DateTime.now().toUtc());
              onStateChanged(_session);
            }
          });
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (!_isReconnecting) {
          _isReconnecting = true;
          CallAudioService.instance.playReconnecting();
        }

        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _missedHeartbeats = 0;

        // Wait 4 seconds — might self-recover on same network
        await Future.delayed(const Duration(seconds: 4));
        if (_pc?.connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          await _attemptReconnect();
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Failed is terminal — end immediately
        _iceEndCallPending = false;
        await endCall();
      }
    };

    // Fix 2C — debug logging so we can track exactly which state it stalls at
    pc.onIceConnectionState = (state) {
      debugPrint('[Call] ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        endCall();
      }
    };
    pc.onIceGatheringState = (state) {
      debugPrint('[Call] ICE gathering state: $state');
    };
    pc.onSignalingState = (state) {
      debugPrint('[Call] Signaling state: $state');
    };

    pc.onRenegotiationNeeded = () async {
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        return;
      }
      try {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _signalingWs?.add(jsonEncode({'type': 'offer', 'sdp': offer.toMap()}));
      } catch (e) {
        debugPrint('[Call] Renegotiation error: $e');
      }
    };

    pc.onTrack = (event) {
      // Remote audio track — flutter_webrtc handles playback automatically
      if (event.track.kind == 'video') {
        _remoteRenderer ??= RTCVideoRenderer();
        _remoteRenderer!.initialize().then((_) {
          _remoteRenderer!.srcObject = event.streams[0];
          _session = _session.copyWith(isRemoteVideoOn: true);
          onStateChanged(_session);
        });
        event.track.onEnded = () {
          _session = _session.copyWith(isRemoteVideoOn: false);
          onStateChanged(_session);
        };
      }
    };

    return pc;
  }

  Future<void> _startSignalingServer(
    int port, {
    required bool isInitiator,
  }) async {
    _isInitiator = isInitiator; // Store for fallback timer sync
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
      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      } catch (_) {}
    }
    _localStream = await _getLocalAudioStream();
    _pc = await _createPeerConnection();
    for (final track in _localStream!.getAudioTracks()) {
      _pc!.addTrack(track, _localStream!);
    }

    // Add Video if active
    if (_localVideoStream != null) {
      for (final track in _localVideoStream!.getVideoTracks()) {
        _pc!.addTrack(track, _localVideoStream!);
      }
    }
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _signalingWs?.add(jsonEncode({'type': 'offer', 'sdp': offer.toMap()}));
  }

  void _handleSignal(Map<String, dynamic> signal) async {
    switch (signal['type']) {
      case 'ping':
        _missedHeartbeats = 0;
        _signalingWs?.add(jsonEncode({'type': 'pong'}));
        break;
      case 'pong':
        _missedHeartbeats = 0;
        break;
      case 'offer':
        final description = RTCSessionDescription(
          signal['sdp']['sdp'] as String,
          signal['sdp']['type'] as String,
        );

        // Check if this is a mid-call Renegotiation
        if (_pc != null) {
          debugPrint('[CallManager] Handling MID-CALL Renegotiation Offer...');
          await _pc!.setRemoteDescription(description);
          _remoteDescSet = true;
          for (final c in _pendingCandidates) {
            await _pc?.addCandidate(c);
          }
          _pendingCandidates.clear();

          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          _signalingWs?.add(
            jsonEncode({'type': 'answer', 'sdp': answer.toMap()}),
          );
          return; // Exit here. Do NOT restart the call.
        }

        debugPrint('[CallManager] Handling INITIAL Offer...');
        // Strict audio handoff sequence (Phase 1 Fix):
        // Stop looping audio → release AudioFocus → WebRTC takes over AudioManager
        await CallAudioService.instance.stopAll();
        await CallAudioService.instance.releaseAudioFocus();
        if (!kIsWeb && Platform.isAndroid) {
          try {
            await Helper.setAndroidAudioConfiguration(
              AndroidAudioConfiguration.communication,
            );
          } catch (_) {}
        }
        _localStream = await _getLocalAudioStream();
        _pc = await _createPeerConnection();
        for (final track in _localStream!.getAudioTracks()) {
          _pc!.addTrack(track, _localStream!);
        }

        // Add Video if active
        if (_localVideoStream != null) {
          for (final track in _localVideoStream!.getVideoTracks()) {
            _pc!.addTrack(track, _localVideoStream!);
          }
        }
        await _pc!.setRemoteDescription(description);
        // Fix 2D — remote desc is now set; flush any ICE candidates that
        // arrived while the offer was being processed.
        _remoteDescSet = true;
        for (final c in _pendingCandidates) {
          await _pc?.addCandidate(c);
        }
        _pendingCandidates.clear();

        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _signalingWs?.add(
          jsonEncode({'type': 'answer', 'sdp': answer.toMap()}),
        );
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
          try {
            await Helper.setAndroidAudioConfiguration(
              AndroidAudioConfiguration.media,
            );
          } catch (_) {}
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
          try {
            await Helper.setAndroidAudioConfiguration(
              AndroidAudioConfiguration.media,
            );
          } catch (_) {}
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
      final socket = await RawDatagramSocket.bind(InternetAddress(localIp), 0);
      final payload = utf8.encode(
        jsonEncode({
          'type': 'call_invite',
          'from': selfUuid,
          'fromName': selfName,
          'signalingPort': signalingPort,
          // callerIp lets the callee use the correct interface IP explicitly;
          // falls back to UDP source address if missing
          'callerIp': localIp,
          'isVideo': _session.isLocalVideoOn,
        }),
      );
      socket.send(payload, InternetAddress(peerIp), kCallInviteUdpPort);
      socket.close();
    } catch (_) {}
  }

  /// Sends a UDP packet telling the callee the call was cancelled
  /// (used when caller hangs up before callee accepts).
  Future<void> _sendCancelInvite({required String peerIp}) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(
        jsonEncode({'type': 'call_cancelled', 'from': selfUuid}),
      );
      socket.send(payload, InternetAddress(peerIp), kCallInviteUdpPort);
      socket.close();
    } catch (_) {}
  }

  /// Sends a UDP packet telling the caller the call was declined.
  /// Primary path for decline — doesn't need a WS connection.
  Future<void> _sendDeclineUdp({required String peerIp}) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = utf8.encode(
        jsonEncode({'type': 'call_declined', 'from': selfUuid}),
      );
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

  Future<void> handleReconnectInvite(int newPort, String callerIp) async {
    debugPrint(
      '[Call] Reconnect invite received, connecting to new port $newPort',
    );
    _remoteDescSet = false;
    _pendingCandidates.clear();
    await _connectToSignalingServer(callerIp, newPort);
  }

  Future<void> _attemptReconnect() async {
    if (_reconnectAttempted) return;
    _reconnectAttempted = true;
    debugPrint('[Call] Attempting UDP re-signaling reconnect...');

    try {
      // 1. Close old peer connection
      await _pc?.close();
      _pc = null;
      _remoteDescSet = false;
      _pendingCandidates.clear();

      // 2. If we are the initiator (caller), start a new
      //    signaling server and send a new UDP invite
      if (_isInitiator) {
        final newPort = 46100 + Random().nextInt(100);
        await _startSignalingServer(newPort, isInitiator: true);
        await _sendCallInvite(
          peerIp: _session.peerIp,
          signalingPort: newPort,
          peerId: _session.peerId,
          peerName: _session.peerName,
        );
      }

      // 3. Set reconnect timeout
      _iceEndCallPending = true;
      Future.delayed(const Duration(seconds: 15), () {
        if (_iceEndCallPending) endCall();
      });
    } catch (e) {
      debugPrint('[Call] Reconnect failed: $e');
      await endCall();
    }
  }

  Future<void> dispose() async {
    _disableBackground(); // Fix 2F — release foreground service in ALL cases
    _iceEndCallPending = false; // Cancel any dangling ICE-restart timer
    // Safety net: release WebRTC AudioManager in case dispose() fires directly
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.media,
        );
      } catch (_) {}
    }
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _isReconnecting = false;
    CallAudioService.instance.stopReconnecting();
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      _localVideoStream?.getTracks().forEach((t) => t.stop());
      await _localVideoStream?.dispose();
      _localRenderer?.srcObject = null;
      await _localRenderer?.dispose();
      _remoteRenderer?.srcObject = null;
      await _remoteRenderer?.dispose();
      await _pc?.close();
      await _signalingServer?.close();
      await _signalingWs?.close();
    } catch (_) {}
    _localStream = null;
    _localVideoStream = null;
    _localRenderer = null;
    _remoteRenderer = null;
    _isVideoOn = false;
    _pc = null;
    _signalingServer = null;
    _signalingWs = null;
  }
}
