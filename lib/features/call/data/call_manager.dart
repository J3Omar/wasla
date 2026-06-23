import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import '../domain/call_state.dart';
import '../../../core/network/network_utils.dart';
import 'call_audio_service.dart';
import 'linux_audio_service.dart';
import 'package:path_provider/path_provider.dart';
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
// ── Windows file-based logging ──────────────────────────────────────────────

Future<void> _winLog(String message) async {
  debugPrint(message);
  if (!Platform.isWindows) return;
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}\\Wasla');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}\\debug.log');
    file.writeAsStringSync(
      '${DateTime.now()}: $message\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

// ── CallManager ───────────────────────────────────────────────────────────────

class CallManager {
  static CallManager? instance;

  CallManager({
    required this.selfUuid,
    required this.selfName,
    required this.onStateChanged,
  }) {
    instance = this;
  }

  final String selfUuid;
  final String selfName;
  final ValueChanged<CallSession> onStateChanged;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  MediaStream? _localVideoStream;
  MediaStream? _screenStream;
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

  // Bug 2 fix: track which side we are on for fallback timer sync
  bool _isInitiator = false;
  bool _isReconnecting = false;
  bool _isDisposing = false;
  bool _endSoundPlayed = false;
  Timer? _iceDisconnectTimer;
  Timer? _iceEndCallTimer;
  Timer? _finalEndCallTimer;
  MediaStreamTrack? _originalAudioTrack;
  // Windows loopback capture stream — stored so it can be stopped cleanly.
  MediaStream? _windowsLoopbackStream;
  // Windows comm device restore — set before CABLE Output opens.
  // SVV: human-readable device name used with SoundVolumeView /SetDefault.
  String? _savedWindowsCommDeviceName;
  // Registry: raw MMDevice GUID used as secondary fallback.
  String? _savedWindowsCommDeviceId;

  /// Current session snapshot — updated by the notifier.
  CallSession _session = CallSession.idle;

  bool get isInCall =>
      _session.state == CallState.active ||
      _session.state == CallState.connecting ||
      _session.state == CallState.outgoing;

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
  Future<void> _disableBackground() async {
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
    // Auto-restore mic if broken from previous crash
    if (Platform.isLinux) {
      await LinuxAudioService().restoreIfBroken();
    }
    _session = CallSession(
      state: CallState.outgoing,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
      isSpeakerOn: isVideo,
      isLocalVideoOn: isVideo,
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    onStateChanged(_session);

    if (isVideo && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
    }

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
    required String callerId,
    required String callerName,
    required String sessionId,
    bool isVideo = false,
  }) async {
    debugPrint('[CallManager] acceptCall invoked for $callerIp:$signalingPort');
    // Auto-restore mic if broken from previous crash
    if (Platform.isLinux) {
      await LinuxAudioService().restoreIfBroken();
    }
    _session = CallSession(
      state: CallState.connecting,
      peerId: callerId,
      peerName: callerName,
      peerIp: callerIp,
      isSpeakerOn: isVideo,
      isRemoteVideoOn: isVideo,
      sessionId: sessionId,
    );
    onStateChanged(_session);

    if (isVideo && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
    }

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
          'frameRate': {'ideal': 60, 'max': 60},
          'facingMode': _session.isFrontCamera ? 'user' : 'environment',
        },
        'audio': false,
      });
      _localRenderer ??= RTCVideoRenderer();
      await _localRenderer!.initialize();
      _localRenderer!.srcObject = _localVideoStream;
      if (_pc != null) {
        await _pc!.addTransceiver(
          track: _localVideoStream!.getVideoTracks().first,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv,
            streams: [_localVideoStream!],
            sendEncodings: [
              RTCRtpEncoding(
                maxBitrate: 2500000,
                minBitrate: 1000000,
                maxFramerate: 60,
              ), // Force 1-2.5 Mbps
            ],
          ),
        );
      }
      _isVideoOn = true;
      if (Platform.isAndroid || Platform.isIOS) {
        Helper.setSpeakerphoneOn(true);
      }
      _session = _session.copyWith(isLocalVideoOn: true, isSpeakerOn: true);
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

  Future<void> toggleScreenShare({bool withAudio = false}) async {
    if (_session.isScreenSharing) {
      // STOP SCREEN SHARE: Revert to Audio-Only Call
      _screenStream?.getTracks().forEach((t) => t.stop());
      _screenStream = null;
      _localRenderer?.srcObject = null;

      _session = _session.copyWith(
        isScreenSharing: false,
        isLocalVideoOn: false,
      );
      onStateChanged(_session);

      // Bug 1 fix: stop the Windows loopback capture stream so CABLE Output
      // does not keep its capture session alive after screen share ends.
      if (Platform.isWindows && _windowsLoopbackStream != null) {
        _windowsLoopbackStream!.getTracks().forEach((t) => t.stop());
        _windowsLoopbackStream = null;

        // Primary: SVV restore
        if (_savedWindowsCommDeviceName != null) {
          try {
            final svvPath =
                '${File(Platform.resolvedExecutable).parent.path}'
                r'\SoundVolumeView.exe';
            await Process.run(svvPath, [
              '/SetDefault',
              _savedWindowsCommDeviceName!,
              '4',
            ]);
            await _winLog(
              '[CallManager] SVV: Restored comm device on '
              'screen share stop.',
            );
          } catch (_) {}
          _savedWindowsCommDeviceName = null;
        }

        // Secondary: registry restore
        if (_savedWindowsCommDeviceId != null) {
          try {
            await Process.run('reg', [
              'add',
              r'HKCU\SOFTWARE\Microsoft\Multimedia\Audio\DefaultEndpointAggregator',
              '/v',
              'DefaultCommunicationsDeviceId',
              '/t',
              'REG_SZ',
              '/d',
              _savedWindowsCommDeviceId!,
              '/f',
            ]);
            await _winLog(
              '[CallManager] Registry: Restored comm device on '
              'screen share stop.',
            );
          } catch (_) {}
          _savedWindowsCommDeviceId = null;
        }
      }

      if (_pc != null) {
        final senders = await _pc!.getSenders();
        for (var sender in senders) {
          if (sender.track?.kind == 'video') {
            await _pc!.removeTrack(sender);
          } else if (sender.track?.kind == 'audio' &&
              _originalAudioTrack != null) {
            await sender.replaceTrack(_originalAudioTrack!);
            _originalAudioTrack = null;
          }
        }
      }

      if (Platform.isLinux) {
        debugPrint(
          '[CallManager] Linux deactivating screen share. Cleaning up audio routing...',
        );
        await LinuxAudioService().disableSystemAudioCapture();
      }
    } else {
      // START SCREEN SHARE
      try {
        try {
          final audioConstraint = (Platform.isAndroid && withAudio)
              ? true
              : withAudio;

          if (Platform.isLinux || Platform.isWindows) {
            final sources = await desktopCapturer.getSources(
              types: [SourceType.Screen, SourceType.Window],
            );
            DesktopCapturerSource? screenSource;
            for (final source in sources) {
              if (source.type == SourceType.Screen) {
                screenSource = source;
                break;
              }
            }
            if (screenSource == null) {
              debugPrint(
                '[CallManager] No screen source found for desktop capturer.',
              );
              return;
            }

            // 1. Route native hardware monitor to default source
            if (Platform.isLinux && withAudio) {
              debugPrint(
                '[CallManager] Linux detected with audio. Activating Native Monitor...',
              );
              await LinuxAudioService().enableSystemAudioCapture();
              await Future.delayed(
                const Duration(milliseconds: 300),
              ); // Allow PulseAudio to switch
            }

            // 2. Get the Display (Video Only)
            debugPrint('[CallManager] Fetching screen display...');
            _screenStream = await navigator.mediaDevices.getDisplayMedia({
              'video': {
                'deviceId': {'exact': screenSource.id},
                'width': {'ideal': 1280, 'max': 1920},
                'height': {'ideal': 720, 'max': 1080},
                'frameRate': {'ideal': 60, 'max': 60},
              },
              'audio': Platform.isLinux
                  ? false
                  : (withAudio
                        ? {
                            'mandatory': {
                              'echoCancellation': false,
                              'googEchoCancellation': false,
                              'autoGainControl': false,
                              'googAutoGainControl': false,
                              // Re-enable these to act as a noise gate against static hiss:
                              'noiseSuppression': true,
                              'googNoiseSuppression': true,
                              'googHighpassFilter': true,
                            },
                            'optional': [],
                          }
                        : false),
            });
            await _winLog(
              '[CallManager] Desktop screen audio tracks: ${_screenStream!.getAudioTracks().length}',
            );

            // 2b. Windows fallback: getDisplayMedia rarely
            // provides a system-audio loopback track on
            // Windows via flutter_webrtc. Try to find a
            // "Stereo Mix"-style loopback recording device
            // and use it instead.
            if (Platform.isWindows &&
                withAudio &&
                _screenStream!.getAudioTracks().isEmpty) {
              try {
                await _winLog(
                  '[CallManager] Windows: no audio track from '
                  'getDisplayMedia. Searching for a loopback '
                  'recording device (e.g. "Stereo Mix")...',
                );
                final devices = await navigator.mediaDevices.enumerateDevices();
                await _winLog(
                  '[CallManager] Windows: enumerating audio input '
                  'devices for loopback search...',
                );
                for (final d in devices) {
                  if (d.kind == 'audioinput') {
                    await _winLog(
                      '[CallManager]   device: label="${d.label}" '
                      'id="${d.deviceId}"',
                    );
                  }
                }
                MediaDeviceInfo? realMicDevice;
                for (final d in devices) {
                  if (d.kind == 'audioinput') {
                    final label = d.label.toLowerCase();
                    final isVirtual =
                        label.contains('stereo mix') ||
                        label.contains('loopback') ||
                        label.contains('what u hear') ||
                        label.contains('wave out') ||
                        label.contains('rec. playback') ||
                        label.contains('cable output') ||
                        label.contains('cable-output') ||
                        label.contains('vb-audio') ||
                        label.contains('vb-cable') ||
                        label.contains('virtual audio') ||
                        label.contains('virtual-audio');
                    if (!isVirtual) {
                      realMicDevice = d;
                      break;
                    }
                  }
                }
                if (realMicDevice != null) {
                  await _winLog(
                    '[CallManager] Identified real physical mic: '
                    '${realMicDevice.label} (${realMicDevice.deviceId})',
                  );
                }
                MediaDeviceInfo? loopbackDevice;
                for (final d in devices) {
                  if (d.kind == 'audioinput') {
                    final label = d.label.toLowerCase();
                    if (label.contains('stereo mix') ||
                        label.contains('loopback') ||
                        label.contains('what u hear') ||
                        label.contains('wave out') ||
                        label.contains('rec. playback') ||
                        label.contains('cable output') ||
                        label.contains('cable-output') ||
                        label.contains('vb-audio') ||
                        label.contains('vb-cable') ||
                        label.contains('virtual audio') ||
                        label.contains('virtual-audio')) {
                      loopbackDevice = d;
                      break;
                    }
                  }
                }
                if (loopbackDevice != null) {
                  await _winLog(
                    '[CallManager] Found loopback device: '
                    '${loopbackDevice.label}',
                  );

                  // ── PRIMARY: SoundVolumeView save ─────────────────────────
                  // Save the current default communications Render device
                  // (speakers) using SVV's CSV report before CABLE Output
                  // opens and Windows reassigns the comm device.
                  try {
                    final svvPath =
                        '${File(Platform.resolvedExecutable).parent.path}'
                        r'\SoundVolumeView.exe';
                    final csvPath =
                        '${Directory.systemTemp.path}\\wasla_audio_state.csv';
                    await Process.run(svvPath, ['/scomma', csvPath]);
                    final csvFile = File(csvPath);
                    if (await csvFile.exists()) {
                      final lines = await csvFile.readAsLines();
                      await _winLog(
                        '[CallManager] SVV CSV captured '
                        '(${lines.length} lines).',
                      );
                      // CSV columns (0-based, confirmed from live output):
                      //  0=Name, 1=Type, 2=Direction, 6=Default Communications
                      // We want: Type=Device, Direction=Render,
                      //          DefaultComm="Render" (the speakers).
                      for (final line in lines.skip(1)) {
                        // skip header
                        final cols = line.split(',');
                        if (cols.length > 6 &&
                            cols[1].trim() == 'Device' &&
                            cols[2].trim() == 'Render' &&
                            cols[6].trim() == 'Render') {
                          _savedWindowsCommDeviceName = cols[0].trim();
                          await _winLog(
                            '[CallManager] SVV saved comm device name: '
                            '"$_savedWindowsCommDeviceName"',
                          );
                          break;
                        }
                      }
                      if (_savedWindowsCommDeviceName == null) {
                        await _winLog(
                          '[CallManager] SVV: no default comm Render device '
                          'found in CSV — will rely on registry fallback.',
                        );
                      }
                    } else {
                      await _winLog(
                        '[CallManager] SVV: CSV file not created '
                        '(path=$csvPath).',
                      );
                    }
                  } catch (e) {
                    await _winLog('[CallManager] SVV save FAILED: $e');
                  }

                  // ── SECONDARY: Registry save ──────────────────────────────
                  // Bug 2/3 fix: save the current default communication
                  // playback device before opening CABLE Output, so Windows
                  // cannot silently switch the comm device to CABLE Input.
                  try {
                    final regResult = await Process.run('reg', [
                      'query',
                      r'HKCU\SOFTWARE\Microsoft\Multimedia\Audio\DefaultEndpointAggregator',
                      '/v',
                      'DefaultCommunicationsDeviceId',
                    ]);
                    final regOut = regResult.stdout.toString();
                    await _winLog(
                      '[CallManager] RAW reg query output: "$regOut" '
                      'exitCode=${regResult.exitCode} '
                      'stderr="${regResult.stderr}"',
                    );
                    final match = RegExp(
                      r'DefaultCommunicationsDeviceId\s+\S+\s+(\S+)',
                    ).firstMatch(regOut);
                    if (match != null) {
                      _savedWindowsCommDeviceId = match.group(1);
                      await _winLog(
                        '[CallManager] Saved comm device id (reg): '
                        '$_savedWindowsCommDeviceId',
                      );
                    } else {
                      await _winLog(
                        '[CallManager] Registry key/value not found — '
                        'falling back to real physical mic device id '
                        'as restore target.',
                      );
                      _savedWindowsCommDeviceId = realMicDevice?.deviceId;
                    }
                  } catch (e) {
                    await _winLog(
                      '[CallManager] Registry save FAILED with '
                      'exception: $e',
                    );
                  }

                  // Open the loopback capture device
                  final loopbackStream = await navigator.mediaDevices
                      .getUserMedia({
                        'video': false,
                        'audio': {
                          'deviceId': {'exact': loopbackDevice.deviceId},
                          'mandatory': {
                            'echoCancellation': false,
                            'googEchoCancellation': false,
                            'autoGainControl': false,
                            'googAutoGainControl': false,
                            'noiseSuppression': false,
                            'googNoiseSuppression': false,
                          },
                          'optional': [],
                        },
                      });

                  // Bug 1 fix: store the stream so we can stop it later.
                  _windowsLoopbackStream = loopbackStream;

                  if (loopbackStream.getAudioTracks().isNotEmpty &&
                      _pc != null) {
                    final loopbackTrack = loopbackStream.getAudioTracks().first;
                    final senders = await _pc!.getSenders();
                    for (var sender in senders) {
                      if (sender.track?.kind == 'audio') {
                        _originalAudioTrack ??= sender.track;
                        await sender.replaceTrack(loopbackTrack);
                        await _winLog(
                          '[CallManager] Windows loopback audio '
                          'routed to peer connection.',
                        );
                        break;
                      }
                    }
                  }

                  // ── PRIMARY: SoundVolumeView restore ─────────────────────
                  // Run immediately after getUserMedia so Windows cannot
                  // keep CABLE Input as the comm device.
                  if (_savedWindowsCommDeviceName != null) {
                    try {
                      final svvPath =
                          '${File(Platform.resolvedExecutable).parent.path}'
                          r'\SoundVolumeView.exe';
                      final svvResult = await Process.run(svvPath, [
                        '/SetDefault',
                        _savedWindowsCommDeviceName!,
                        '4', // role 4 = Communications only
                      ]);
                      await _winLog(
                        '[CallManager] SVV restore: '
                        'exitCode=${svvResult.exitCode} '
                        'stderr="${svvResult.stderr.toString().trim()}"',
                      );
                    } catch (e) {
                      await _winLog('[CallManager] SVV restore FAILED: $e');
                    }
                  } else {
                    await _winLog(
                      '[CallManager] SVV: no saved name — skipping SVV restore.',
                    );
                  }

                  // ── SECONDARY: Registry restore ───────────────────────────
                  // Bug 2/3 fix: restore the default communication playback
                  // device after getUserMedia so Windows does not remain
                  // pointed at CABLE Input and silence the real speakers.
                  if (_savedWindowsCommDeviceId != null) {
                    try {
                      final restoreResult = await Process.run('reg', [
                        'add',
                        r'HKCU\SOFTWARE\Microsoft\Multimedia\Audio\DefaultEndpointAggregator',
                        '/v',
                        'DefaultCommunicationsDeviceId',
                        '/t',
                        'REG_SZ',
                        '/d',
                        _savedWindowsCommDeviceId!,
                        '/f',
                      ]);
                      await _winLog(
                        '[CallManager] Restore comm device id: '
                        'exitCode=${restoreResult.exitCode} '
                        'stdout="${restoreResult.stdout}" '
                        'stderr="${restoreResult.stderr}"',
                      );
                      final verifyResult = await Process.run('reg', [
                        'query',
                        r'HKCU\SOFTWARE\Microsoft\Multimedia\Audio\DefaultEndpointAggregator',
                        '/v',
                        'DefaultCommunicationsDeviceId',
                      ]);
                      await _winLog(
                        '[CallManager] VERIFY after restore: '
                        '${verifyResult.stdout.toString().trim()}',
                      );
                    } catch (e) {
                      await _winLog(
                        '[CallManager] Registry restore FAILED with '
                        'exception: $e',
                      );
                    }
                  } else {
                    await _winLog(
                      '[CallManager] No saved comm device id to restore '
                      '(it was never found/saved).',
                    );
                  }
                } else {
                  await _winLog(
                    '[CallManager] No loopback/"Stereo Mix" '
                    'device found. System audio sharing is '
                    'unavailable on this Windows machine unless '
                    'the user enables "Stereo Mix" (or a similar '
                    'loopback recording device) in Windows Sound '
                    'settings > Recording devices.',
                  );
                }
              } catch (e) {
                debugPrint(
                  '[CallManager] Windows loopback fallback '
                  'failed: $e',
                );
              }
            }

            // 3. Inject the System Audio as a separate Microphone Track
            if (Platform.isLinux && withAudio && _screenStream != null) {
              try {
                debugPrint(
                  '[CallManager] Fetching virtual system audio via getUserMedia...',
                );
                final systemAudioStream = await navigator.mediaDevices
                    .getUserMedia({
                      'video': false,
                      'audio': {
                        'mandatory': {
                          'echoCancellation': false,
                          'googEchoCancellation': false,
                          'autoGainControl': false,
                          'googAutoGainControl': false,
                          // Act as a noise gate to kill the crackle/static hiss:
                          'noiseSuppression': true,
                          'googNoiseSuppression': true,
                          'googHighpassFilter': true,
                        },
                        'optional': [],
                      },
                    });

                if (systemAudioStream.getAudioTracks().isNotEmpty) {
                  final sysAudioTrack = systemAudioStream
                      .getAudioTracks()
                      .first;
                  debugPrint(
                    '[CallManager] Virtual system audio track obtained: ${sysAudioTrack.id}',
                  );

                  final freshSenders = await _pc!.getSenders();
                  for (var sender in freshSenders) {
                    if (sender.track?.kind == 'audio') {
                      _originalAudioTrack =
                          sender.track; // Save the original mic track

                      // Create a NEW software-mixed audio track using WebRTC capabilities
                      // Note: If flutter_webrtc does not natively support createLocalMediaStream mixing easily,
                      // we fallback to the safest method: Replacing with sysAudioTrack ONLY (no mic) for now to ensure stability.
                      // Since WebAudio API's gain nodes aren't fully exposed in Flutter WebRTC natively,
                      // we will explicitly REPLACE the track with system audio to guarantee zero crackle.

                      await sender.replaceTrack(sysAudioTrack);
                      break;
                    }
                  }
                }
              } catch (e) {
                debugPrint(
                  '[CallManager] Failed to get virtual system audio: $e',
                );
              }
            }
          } else {
            _screenStream = await navigator.mediaDevices.getDisplayMedia({
              'video': {
                'width': {'ideal': 960, 'max': 1280},
                'height': {'ideal': 540, 'max': 720},
                'frameRate': {'ideal': 60, 'max': 60},
                'cursor': 'always',
              },
              'audio': audioConstraint,
            });
          }
        } catch (e) {
          if (withAudio) {
            debugPrint(
              '[CallManager] getDisplayMedia failed with audio. Retrying without audio...',
            );
            _screenStream = await navigator.mediaDevices.getDisplayMedia({
              'video': true,
              'audio': false, // Fallback for Linux/Systems without loopback
            });
          } else {
            rethrow; // Re-throw if it failed even without audio
          }
        }

        // Listen for OS-level stop button (e.g., Android floating bar)
        _screenStream!.getVideoTracks().first.onEnded = () {
          debugPrint('[CallManager] OS-level screen share stop detected.');
          toggleScreenShare(); // Trigger local cleanup
        };

        final screenTrack = _screenStream!.getVideoTracks().first;
        final screenAudioTracks = _screenStream!.getAudioTracks();
        debugPrint(
          '[CallManager] Screen audio tracks found: ${screenAudioTracks.length}',
        );

        if (_pc != null) {
          final senders = await _pc!.getSenders();
          bool trackReplaced = false;
          for (var sender in senders) {
            if (sender.track?.kind == 'video') {
              // Replace existing camera track with screen track
              await sender.replaceTrack(screenTrack);
              trackReplaced = true;
              break;
            }
          }
          if (!trackReplaced) {
            // If no video track existed (Audio-only call), add it.
            await _pc!.addTrack(screenTrack, _screenStream!);
            // Note: This specific path will require renegotiation handled by onRenegotiationNeeded
          }

          // Replace the current microphone track with our MIXED virtual track
          if (screenAudioTracks.isNotEmpty) {
            debugPrint(
              '[CallManager] Screen audio track found. Replacing existing audio track with mixed stream.',
            );
            final freshSenders = await _pc!.getSenders();
            for (var sender in freshSenders) {
              if (sender.track?.kind == 'audio') {
                _originalAudioTrack = sender.track;
                await sender.replaceTrack(screenAudioTracks.first);
                break;
              }
            }
          }
        }

        // Preview local screen
        _localRenderer?.srcObject = _screenStream;
        if (Platform.isAndroid || Platform.isIOS) {
          Helper.setSpeakerphoneOn(true);
        }
        _session = _session.copyWith(isScreenSharing: true, isSpeakerOn: true);

        // Ensure regular video flag is considered off
        if (_session.isLocalVideoOn) {
          _session = _session.copyWith(isLocalVideoOn: false);
        }
        onStateChanged(_session);
      } catch (e) {
        debugPrint('[CallManager] Screen share failed or denied: $e');
      }
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
      if (!_endSoundPlayed) {
        _endSoundPlayed = true;
        await CallAudioService.instance.playEndSound();
      }
    }
    // 4. Dispose WebRTC AFTER the chime is done
    await dispose();
  }

  // ── WebRTC internals ─────────────────────────────────────────────────────

  static const _kMinPort = 46100;
  static const _kMaxPort = 46200;

  Future<MediaStream> _getLocalAudioStream() async {
    // Windows uses a broader AGC/processing set (incl. googAutoGainControl2)
    // to compensate for the lack of hardware-assisted audio paths on Windows.
    // All other platforms keep the original constraints unchanged.
    final micAudioConstraints = Platform.isWindows
        ? <String, dynamic>{
            'echoCancellation': true,
            'autoGainControl': true,
            'noiseSuppression': true,
            'googEchoCancellation': true,
            'googAutoGainControl': true,
            'googAutoGainControl2': true,
            'googNoiseSuppression': true,
            'googHighpassFilter': true,
          }
        : <String, dynamic>{
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
          };
    final Map<String, dynamic> mediaConstraints = {
      'audio': micAudioConstraints,
      'video': false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (Platform.isWindows) {
      for (final track in stream.getAudioTracks()) {
        await _winLog(
          '[CallManager] Windows local audio track: '
          'id=${track.id} enabled=${track.enabled} '
          'muted=${track.muted}',
        );
      }
    }
    return stream;
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
        if (!kIsWeb &&
            (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
          final senders = await _pc!.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'video') {
              final params = sender.parameters;
              if (params.encodings != null && params.encodings!.isNotEmpty) {
                params.encodings!.first.maxBitrate = 2000000; // 2 Mbps
                params.encodings!.first.minBitrate = 500000; // 500 kbps
                await sender.setParameters(params);
                debugPrint(
                  '[CallManager] Desktop video bitrate set: 500k-2M bps',
                );
              }
              break;
            }
          }
        }
        _cancelTimeout();
        // Safety net only — audio handoff already happened before getUserMedia
        await CallAudioService.instance.stopAll();

        if (_isReconnecting) {
          _isReconnecting = false;
          _iceDisconnectTimer?.cancel();
          _iceEndCallTimer?.cancel();
          _finalEndCallTimer?.cancel();
          debugPrint('[CallManager] ICE restart succeeded.');
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
        if (_isReconnecting) return;
        if (!_isReconnecting) {
          _isReconnecting = true;

          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
          _missedHeartbeats = 0;

          // Play reconnect sound immediately on disconnect
          debugPrint(
            '[CallManager] Connection lost. '
            'Playing reconnecting sound immediately...',
          );
          CallAudioService.instance.playReconnecting();

          // Give 5s grace before ICE restart attempt
          _iceDisconnectTimer?.cancel();
          _iceDisconnectTimer = Timer(const Duration(seconds: 5), () {
            debugPrint('[CallManager] Attempting ICE restart...');
            _pc!.restartIce(); // Trigger renegotiation internally

            // Start 15s doom timer (20s total)
            _iceEndCallTimer?.cancel();
            _iceEndCallTimer = Timer(const Duration(seconds: 15), () async {
              if (_isReconnecting) {
                debugPrint(
                  '[CallManager] ICE Recovery Failed. Attempting full re-signaling.',
                );
                await _attemptReconnect();
              }
            });
          });
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Don't end immediately — give a grace period.
        // Android often jumps here skipping Disconnected entirely.
        if (_isReconnecting) return;
        _isReconnecting = true;
        _iceDisconnectTimer?.cancel();
        _iceEndCallTimer?.cancel();
        _finalEndCallTimer?.cancel();

        debugPrint(
          '[CallManager] Connection failed. Playing reconnecting sound...',
        );
        CallAudioService.instance.playReconnecting();
        _pc!.restartIce();

        // Give 15 seconds to recover before hanging up
        _iceEndCallTimer = Timer(const Duration(seconds: 15), () async {
          if (_isReconnecting) {
            debugPrint('[CallManager] Failed recovery timeout. Ending call.');
            CallAudioService.instance.stopReconnecting();
            await endCall();
          }
        });
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

    pc.onRemoveTrack = (stream, track) {
      if (track.kind == 'video') {
        debugPrint('[CallManager] Remote video track removed.');
        _remoteRenderer?.srcObject = null;
        _session = _session.copyWith(isRemoteVideoOn: false);
        onStateChanged(_session);
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

    // Add Video if active with explicit bitrates
    if (_localVideoStream != null) {
      for (final track in _localVideoStream!.getVideoTracks()) {
        await _pc!.addTransceiver(
          track: track,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv,
            streams: [_localVideoStream!],
            sendEncodings: [
              RTCRtpEncoding(
                maxBitrate: 2500000,
                minBitrate: 1000000,
                maxFramerate: 60,
              ),
            ],
          ),
        );
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

          // ANTI-GLARE SHIELD: If we are already negotiating, ignore the incoming offer
          if (_pc!.signalingState !=
              RTCSignalingState.RTCSignalingStateStable) {
            debugPrint(
              '[CallManager] GLARE DETECTED: Ignoring offer to prevent crash. State: ${_pc!.signalingState}',
            );
            return;
          }

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
        if (!_endSoundPlayed) {
          _endSoundPlayed = true;
          await CallAudioService.instance.playEndSound();
        }
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
        if (!_endSoundPlayed) {
          _endSoundPlayed = true;
          await CallAudioService.instance.playEndSound();
        }
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
          'callerIp': localIp,
          'isVideo': _session.isLocalVideoOn,
          'sessionId': _session.sessionId,
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
    debugPrint('[CallManager] Attempting UDP re-signaling reconnect...');

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
    } catch (e) {
      debugPrint('[CallManager] Reconnect failed: $e');
      await endCall();
      return;
    }

    // Final fallback — if re-signaling doesn't produce a Connected state
    // within 10 seconds, give up and end the call.
    _finalEndCallTimer?.cancel();
    _finalEndCallTimer = Timer(const Duration(seconds: 10), () async {
      if (_isReconnecting) {
        debugPrint(
          '[CallManager] Re-signaling timeout. Remote unreachable. Ending call.',
        );
        await endCall();
      }
    });
  }

  Future<void> dispose() async {
    if (_isDisposing) return;
    _isDisposing = true;
    _endSoundPlayed = false;
    debugPrint('[CallManager] Disposing resources...');

    if (Platform.isLinux) {
      await LinuxAudioService().disableSystemAudioCapture();
    }

    await _disableBackground(); // FIX: Await to prevent Race Condition
    _iceEndCallTimer?.cancel();
    _finalEndCallTimer?.cancel();
    _originalAudioTrack = null;
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

    // Give the end-call sound 1 second to play before destroying the WebRTC streams
    await Future.delayed(const Duration(seconds: 1));

    try {
      // Bug 1 fix: ensure Windows loopback stream is stopped on call end.
      _windowsLoopbackStream?.getTracks().forEach((t) => t.stop());
      _windowsLoopbackStream = null;

      if (Platform.isWindows) {
        // Primary: SVV restore
        if (_savedWindowsCommDeviceName != null) {
          try {
            final svvPath =
                '${File(Platform.resolvedExecutable).parent.path}'
                r'\SoundVolumeView.exe';
            await Process.run(svvPath, [
              '/SetDefault',
              _savedWindowsCommDeviceName!,
              '4',
            ]);
            await _winLog(
              '[CallManager] SVV: Restored comm device on dispose.',
            );
          } catch (_) {}
          _savedWindowsCommDeviceName = null;
        }

        // Secondary: registry restore
        if (_savedWindowsCommDeviceId != null) {
          try {
            await Process.run('reg', [
              'add',
              r'HKCU\SOFTWARE\Microsoft\Multimedia\Audio\DefaultEndpointAggregator',
              '/v',
              'DefaultCommunicationsDeviceId',
              '/t',
              'REG_SZ',
              '/d',
              _savedWindowsCommDeviceId!,
              '/f',
            ]);
            await _winLog(
              '[CallManager] Registry: Restored comm device on dispose.',
            );
          } catch (_) {}
          _savedWindowsCommDeviceId = null;
        }
      }
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
      await _signalingWs?.close(); // Safe now, _isDisposing blocks the loop
    } catch (_) {}

    _localStream = null;
    _localVideoStream = null;
    _localRenderer = null;
    _remoteRenderer = null;
    _isVideoOn = false;
    _pc = null;
    _signalingServer = null;
    _signalingWs = null;
    _isDisposing = false; // Reset for future calls
  }
}
