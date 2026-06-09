import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/call_provider.dart';
import '../domain/call_state.dart';

/// Active call screen (Voice/Video) — shown once WebRTC is connected.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, this.peerName = ''});

  final String peerName;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _hasMultipleCameras = false;
  bool _wasSpeakerOnBeforeVideo = false;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _checkCameras();
    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    setState(() => _showControls = true);
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_showControls) {
      _controlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      _startControlsTimer();
    }
  }

  Future<void> _checkCameras() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    final cameras = devices.where((d) => d.kind == 'videoinput').toList();
    if (mounted) {
      setState(() => _hasMultipleCameras = cameras.length > 1);
    }
  }

  Future<void> _onToggleVideo(CallSession state) async {
    final notifier = ref.read(callProvider.notifier);
    try {
      if (!state.isLocalVideoOn) {
        _wasSpeakerOnBeforeVideo = state.isSpeakerOn;
        await notifier.toggleVideo();
        if (!state.isSpeakerOn) notifier.toggleSpeaker();
      } else {
        await notifier.toggleVideo();
        if (state.isSpeakerOn != _wasSpeakerOnBeforeVideo) {
          notifier.toggleSpeaker();
        }
      }
    } catch (e) {
      if (e.toString().contains('NO_CAMERA')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This device doesn't support a camera")),
        );
      }
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider).valueOrNull ?? CallSession.idle;

    ref.listen(callProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      if (s.state == CallState.ended) {
        if (mounted) context.go('/home');
      }
    });

    final isConnecting =
        callState.state == CallState.connecting ||
        callState.state == CallState.incoming;

    final rawName = callState.peerName.isNotEmpty
        ? callState.peerName
        : widget.peerName;
    final String cleanName = rawName.trim();
    final String initials = cleanName.isNotEmpty
        ? cleanName
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
              .join()
        : '?';

    final bool hasAnyVideo =
        callState.isLocalVideoOn || callState.isRemoteVideoOn;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    AppColors.primaryCyan.withValues(alpha: 0.10),
                    AppColors.bgPrimary,
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Header
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () => context.go('/home'),
                            tooltip: 'Minimize call',
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasAnyVideo ? 'Video Call' : 'Voice Call',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Main View (Remote Video OR Avatar)
                  Expanded(
                    flex: 8,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 1. Background Layer (Remote Video OR Local Video OR Avatar)
                        if (callState.isRemoteVideoOn &&
                            ref.read(callProvider.notifier).remoteRenderer !=
                                null)
                          Positioned.fill(
                            child: RTCVideoView(
                              ref.read(callProvider.notifier).remoteRenderer!,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          )
                        else if (callState.isLocalVideoOn &&
                            ref.read(callProvider.notifier).localRenderer !=
                                null &&
                            !callState.isRemoteVideoOn)
                          Positioned.fill(
                            child: RTCVideoView(
                              ref.read(callProvider.notifier).localRenderer!,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),
                          )
                        else
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryCyan,
                                  AppColors.primaryPurple,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryCyan.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 30,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                initials.toUpperCase(),
                                style: AppTypography.heading2.copyWith(
                                  color: Colors.white,
                                  fontSize: 36,
                                ),
                              ),
                            ),
                          ),

                        // 2. PiP Layer (Local Video when Remote is ON)
                        if (callState.isLocalVideoOn &&
                            callState.isRemoteVideoOn &&
                            ref.read(callProvider.notifier).localRenderer !=
                                null)
                          Positioned(
                            top: 16,
                            right: 16,
                            width: 100,
                            height: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: RTCVideoView(
                                ref.read(callProvider.notifier).localRenderer!,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    callState.peerName,
                    style: AppTypography.heading2.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Show "Connecting…" until WebRTC is active, then show timer
                  if (isConnecting)
                    Text(
                      'Connecting…',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primaryCyan,
                      ),
                    )
                  else
                    CallTimerWidget(startedAt: callState.startedAt),
                  const Spacer(),
                  // ── Controls pill ──────────────────────────────────────────────────
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: _ControlsPill(
                        isMuted: callState.isMuted,
                        isSpeakerOn: callState.isSpeakerOn,
                        isLocalVideoOn: callState.isLocalVideoOn,
                        hasMultipleCameras: _hasMultipleCameras,
                        showSpeakerToggle:
                            (Platform.isAndroid || Platform.isIOS) &&
                            !callState.isLocalVideoOn,
                        onMute: () =>
                            ref.read(callProvider.notifier).toggleMute(),
                        onSpeaker: () =>
                            ref.read(callProvider.notifier).toggleSpeaker(),
                        onToggleVideo: () => _onToggleVideo(callState),
                        onSwitchCamera: () =>
                            ref.read(callProvider.notifier).switchCamera(),
                        onEnd: () {
                          ref.read(callProvider.notifier).endCall();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glassmorphism Controls Pill ───────────────────────────────────────────────

class _ControlsPill extends StatelessWidget {
  const _ControlsPill({
    required this.isMuted,
    required this.isSpeakerOn,
    required this.isLocalVideoOn,
    required this.hasMultipleCameras,
    required this.showSpeakerToggle,
    required this.onMute,
    required this.onSpeaker,
    required this.onToggleVideo,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoOn;
  final bool hasMultipleCameras;

  /// Show speaker/earpiece toggle — true on Android/iOS only.
  final bool showSpeakerToggle;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onToggleVideo;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: AppColors.borderDefault.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute toggle — always shown
          _PillButton(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            color: isMuted ? Colors.redAccent : AppColors.textSecondary,
            onTap: onMute,
          ),
          // Camera toggle
          _PillButton(
            icon: isLocalVideoOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: 'Camera',
            color: isLocalVideoOn
                ? AppColors.primaryCyan
                : AppColors.textSecondary,
            onTap: onToggleVideo,
          ),
          // Switch camera — ONLY shown if video is on and 2+ cameras exist
          if (isLocalVideoOn && hasMultipleCameras)
            _PillButton(
              icon: Icons.flip_camera_ios_rounded,
              label: 'Flip',
              color: AppColors.textSecondary,
              onTap: onSwitchCamera,
            ),
          // Speaker / Earpiece — mobile only
          if (showSpeakerToggle)
            _PillButton(
              icon: isSpeakerOn
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              label: isSpeakerOn ? 'Speaker' : 'Earpiece',
              color: isSpeakerOn
                  ? AppColors.primaryCyan
                  : AppColors.textSecondary,
              onTap: onSpeaker,
            ),
          // End call — always shown
          GestureDetector(
            onTap: onEnd,
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class CallTimerWidget extends StatefulWidget {
  const CallTimerWidget({super.key, this.startedAt});
  final DateTime? startedAt;

  @override
  State<CallTimerWidget> createState() => _CallTimerWidgetState();
}

class _CallTimerWidgetState extends State<CallTimerWidget> {
  // Bug 2 fix: If startedAt is null (call_start_sync message lost),
  // fall back to counting from the moment this widget was first built.
  late final DateTime _fallbackStart;

  @override
  void initState() {
    super.initState();
    _fallbackStart = DateTime.now();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final origin = widget.startedAt ?? _fallbackStart;
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final elapsed = DateTime.now().difference(origin);
        return Text(
          _formatDuration(elapsed),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.primaryCyan,
          ),
        );
      },
    );
  }
}
