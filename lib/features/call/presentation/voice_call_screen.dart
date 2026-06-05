import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/call_provider.dart';
import '../domain/call_state.dart';

/// Active voice call screen — shown once WebRTC audio is connected.
class VoiceCallScreen extends ConsumerStatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final callState =
        ref.watch(callProvider).valueOrNull ?? CallSession.idle;

    // Pop when call ends
    ref.listen(callProvider, (_, next) {
      if (next.valueOrNull?.state == CallState.ended) {
        if (context.mounted) context.pop();
      }
    });

    final initials = callState.peerName.isNotEmpty
        ? callState.peerName
            .trim()
            .split(' ')
            .map((w) => w[0])
            .take(2)
            .join()
        : '?';

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      Text(
                        'Voice Call',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Avatar
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
                        color: AppColors.primaryCyan.withValues(alpha: 0.3),
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
                const SizedBox(height: 24),
                Text(
                  callState.peerName,
                  style: AppTypography.heading2
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                // Timer
                Text(
                  _formatDuration(_elapsed),
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.primaryCyan),
                ),
                const Spacer(),
                // ── Glassmorphism controls pill ───────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: _ControlsPill(
                    isMuted: callState.isMuted,
                    isSpeakerOn: callState.isSpeakerOn,
                    onMute: () =>
                        ref.read(callProvider.notifier).toggleMute(),
                    onSpeaker: () =>
                        ref.read(callProvider.notifier).toggleSpeaker(),
                    onEnd: () {
                      ref.read(callProvider.notifier).endCall();
                      context.pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glassmorphism Controls Pill ───────────────────────────────────────────────

class _ControlsPill extends StatelessWidget {
  const _ControlsPill({
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onEnd,
  });

  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
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
          // Mute
          _PillButton(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            color: isMuted ? Colors.redAccent : AppColors.textSecondary,
            onTap: onMute,
          ),
          // Speaker
          _PillButton(
            icon: isSpeakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            label: 'Speaker',
            color: isSpeakerOn
                ? AppColors.primaryCyan
                : AppColors.textSecondary,
            onTap: onSpeaker,
          ),
          // End call (large red button)
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
            style:
                AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
