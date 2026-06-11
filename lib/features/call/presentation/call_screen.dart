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
  bool _isVideoToggling = false;
  bool _isScreenShareToggling = false;
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
    if (_isVideoToggling) return; // Cooldown active, ignore taps
    setState(() => _isVideoToggling = true);

    try {
      final notifier = ref.read(callProvider.notifier);
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
    } finally {
      if (mounted) setState(() => _isVideoToggling = false);
    }
  }

  Future<void> _onToggleScreenShare(CallSession state) async {
    if (_isScreenShareToggling) return;

    if (!state.isScreenSharing) {
      final isCamOn = state.isLocalVideoOn;
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.bgSecondary,
          title: Text('Share Screen', style: AppTypography.heading3),
          content: Text(
            isCamOn
                ? 'Sharing your screen will replace your camera feed.\n\nDo you want to include device audio?'
                : 'Do you want to include device audio?',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'no_audio'),
              child: const Text(
                'No Audio',
                style: TextStyle(color: AppColors.primaryPurple),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'with_audio'),
              child: const Text(
                'With Audio',
                style: TextStyle(color: AppColors.statusOnline),
              ),
            ),
          ],
        ),
      );

      if (result == null || result == 'cancel') return;

      setState(() => _isScreenShareToggling = true);
      try {
        final notifier = ref.read(callProvider.notifier);
        await notifier.toggleScreenShare(withAudio: result == 'with_audio');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Screen share failed')));
        }
      } finally {
        if (mounted) setState(() => _isScreenShareToggling = false);
      }
    } else {
      // If already sharing, just toggle it off directly without asking
      setState(() => _isScreenShareToggling = true);
      try {
        await ref.read(callProvider.notifier).toggleScreenShare();
      } finally {
        if (mounted) setState(() => _isScreenShareToggling = false);
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
            // 1. ABSOLUTE BACKGROUND: Edge-to-Edge Video (No SafeArea)
            Positioned.fill(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.hardEdge,
                children: [
                  // Remote Video OR Local Video OR Avatar
                  if (callState.isRemoteVideoOn &&
                      ref.read(callProvider.notifier).remoteRenderer != null)
                    Positioned.fill(
                      child: SizedBox.expand(
                        child: OrientationBuilder(
                          builder: (context, orientation) {
                            return RTCVideoView(
                              ref.read(callProvider.notifier).remoteRenderer!,
                              objectFit:
                                  (Platform.isLinux ||
                                      Platform.isWindows ||
                                      Platform.isMacOS)
                                  ? RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitContain
                                  : (orientation == Orientation.landscape
                                        ? RTCVideoViewObjectFit
                                              .RTCVideoViewObjectFitCover
                                        : RTCVideoViewObjectFit
                                              .RTCVideoViewObjectFitContain),
                            );
                          },
                        ),
                      ),
                    )
                  else if (callState.isLocalVideoOn &&
                      ref.read(callProvider.notifier).localRenderer != null &&
                      !callState.isRemoteVideoOn)
                    Positioned.fill(
                      child: RTCVideoView(
                        ref.read(callProvider.notifier).localRenderer!,
                        mirror: false,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: double.infinity,
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
                      child: Center(
                        child: Container(
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
                      ),
                    ),
                ],
              ),
            ),

            // 2. FOREGROUND UI (Safe Area for Notch/Status Bar)
            Positioned.fill(
              child: SafeArea(
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
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Name and Timer
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Column(
                              children: [
                                Text(
                                  callState.peerName,
                                  style: AppTypography.heading2.copyWith(
                                    color: Colors.white,
                                    shadows: [
                                      const Shadow(
                                        blurRadius: 10.0,
                                        color: Colors.black54,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (isConnecting)
                                  Text(
                                    'Connecting…',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.primaryCyan,
                                      shadows: [
                                        const Shadow(
                                          blurRadius: 10.0,
                                          color: Colors.black54,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  CallTimerWidget(
                                    startedAt: callState.startedAt,
                                  ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),

                          // Controls pill
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ControlsPill(
                                  isMuted: callState.isMuted,
                                  isSpeakerOn: callState.isSpeakerOn,
                                  isLocalVideoOn: callState.isLocalVideoOn,
                                  isScreenSharing: callState.isScreenSharing,
                                  isVideoToggling: _isVideoToggling,
                                  isScreenShareToggling: _isScreenShareToggling,
                                  hasMultipleCameras: _hasMultipleCameras,
                                  showSpeakerToggle:
                                      (Platform.isAndroid || Platform.isIOS) &&
                                      !callState.isLocalVideoOn &&
                                      !callState.isScreenSharing,
                                  onMute: () => ref
                                      .read(callProvider.notifier)
                                      .toggleMute(),
                                  onSpeaker: () => ref
                                      .read(callProvider.notifier)
                                      .toggleSpeaker(),
                                  onToggleVideo: () =>
                                      _onToggleVideo(callState),
                                  onToggleScreenShare: () =>
                                      _onToggleScreenShare(callState),
                                  onSwitchCamera: () => ref
                                      .read(callProvider.notifier)
                                      .switchCamera(),
                                  onEnd: () {
                                    ref.read(callProvider.notifier).endCall();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. PiP Local Video (Above controls, safe distance from bottom)
            if (callState.isLocalVideoOn &&
                callState.isRemoteVideoOn &&
                ref.read(callProvider.notifier).localRenderer != null)
              Positioned(
                bottom: 150, // Avoid overlapping the controls
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    ref.read(callProvider.notifier).localRenderer!,
                    mirror: false,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
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
    required this.isScreenSharing,
    required this.isVideoToggling,
    required this.isScreenShareToggling,
    required this.hasMultipleCameras,
    required this.showSpeakerToggle,
    required this.onMute,
    required this.onSpeaker,
    required this.onToggleVideo,
    required this.onToggleScreenShare,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoOn;
  final bool isScreenSharing;
  final bool isVideoToggling;
  final bool isScreenShareToggling;
  final bool hasMultipleCameras;

  /// Show speaker/earpiece toggle — true on Android/iOS only.
  final bool showSpeakerToggle;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onToggleVideo;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 100 : 12),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: isDesktop ? 24 : 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(isDesktop ? 60 : 40),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mute toggle — always shown
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16.0 : 6.0),
              child: _PillButton(
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: isMuted ? 'Unmute' : 'Mute',
                color: isMuted ? Colors.redAccent : AppColors.textSecondary,
                onTap: onMute,
              ),
            ),
            // Camera toggle
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16.0 : 6.0),
              child: _PillButton(
                icon: isLocalVideoOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: isVideoToggling ? 'Wait...' : 'Camera',
                color: isVideoToggling
                    ? AppColors.textMuted
                    : isLocalVideoOn
                    ? AppColors.primaryCyan
                    : AppColors.textSecondary,
                onTap: isVideoToggling ? () {} : onToggleVideo,
              ),
            ),
            // Screen Share toggle
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16.0 : 6.0),
              child: _PillButton(
                icon: isScreenSharing
                    ? Icons.stop_screen_share_rounded
                    : Icons.present_to_all_rounded,
                label: isScreenShareToggling ? 'Wait...' : 'Screen',
                color: isScreenShareToggling
                    ? AppColors.textMuted
                    : isScreenSharing
                    ? AppColors.primaryCyan
                    : AppColors.textSecondary,
                onTap: isScreenShareToggling ? () {} : onToggleScreenShare,
              ),
            ),
            // Switch camera — ONLY shown if video is on and 2+ cameras exist
            if (isLocalVideoOn && hasMultipleCameras)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 16.0 : 6.0,
                ),
                child: _PillButton(
                  icon: Icons.flip_camera_ios_rounded,
                  label: 'Flip',
                  color: AppColors.textSecondary,
                  onTap: onSwitchCamera,
                ),
              ),
            // Speaker / Earpiece — mobile only
            if (showSpeakerToggle)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 16.0 : 6.0,
                ),
                child: _PillButton(
                  icon: isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.hearing_rounded,
                  label: isSpeakerOn ? 'Speaker' : 'Earpiece',
                  color: isSpeakerOn
                      ? AppColors.primaryCyan
                      : AppColors.textSecondary,
                  onTap: onSpeaker,
                ),
              ),
            // End call — always shown
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16.0 : 6.0),
              child: GestureDetector(
                onTap: onEnd,
                child: Container(
                  width: isDesktop ? 72.0 : 60.0,
                  height: isDesktop ? 72.0 : 60.0,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: isDesktop ? 30.0 : 26.0,
                  ),
                ),
              ),
            ),
          ],
        ),
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
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isDesktop ? 64.0 : 52.0,
            height: isDesktop ? 64.0 : 52.0,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: isDesktop ? 28.0 : 22.0),
          ),
          SizedBox(height: isDesktop ? 8.0 : 4.0),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textMuted,
              fontSize: isDesktop ? 13.0 : 11.0,
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
