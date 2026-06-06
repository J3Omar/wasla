import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/smart_permission_handler.dart';
import '../domain/call_provider.dart';
import '../domain/call_state.dart';

/// Shown when another device is calling this device.
/// Passes [callerId], [callerName], [callerIp], [signalingPort] via extra.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callerName,
    required this.callerIp,
    required this.signalingPort,
  });

  final String callerId;
  final String callerName;
  final String callerIp;
  final int signalingPort;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  // Bug fix: prevent multiple rapid taps from triggering accept/decline twice
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    // Auto-navigate when call connects, or auto-dismiss when caller cancels
    ref.listen(callProvider, (_, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      if (s.state == CallState.active) {
        if (mounted) context.pushReplacement('/call/active');
      } else if (s.state == CallState.ended) {
        // Caller cancelled before we answered — pop immediately
        if (mounted) context.pop();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Warm gradient for incoming
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.4,
                colors: [
                  AppColors.statusOnline.withValues(alpha: 0.12),
                  AppColors.bgPrimary,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                // Avatar
                _IncomingAvatar(name: widget.callerName),
                const SizedBox(height: 24),
                Text(
                  widget.callerName,
                  style: AppTypography.heading2
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Incoming voice call',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textMuted),
                ),
                const Spacer(),
                // Accept / Decline row — centered with equal spacing
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Decline
                      _CallButton(
                        icon: Icons.call_end_rounded,
                        color: Colors.redAccent,
                        label: 'Decline',
                        onTap: _isProcessing
                            ? null
                            : () {
                                setState(() => _isProcessing = true);
                                ref.read(callProvider.notifier).declineCall(
                                      callerIp: widget.callerIp,
                                      signalingPort: widget.signalingPort,
                                    );
                                if (mounted) context.pop();
                              },
                      ),
                      // Accept — check mic permission, then navigate immediately
                      _CallButton(
                        icon: Icons.call_rounded,
                        color: AppColors.statusOnline,
                        label: 'Accept',
                        onTap: _isProcessing
                            ? null
                            : () async {
                                // Fix 2E — require microphone before accepting
                                final granted =
                                    await SmartPermissionHandler.request(
                                  context,
                                  Permission.microphone,
                                  'Microphone',
                                  'to make voice calls',
                                );
                                if (!granted) return;
                                setState(() => _isProcessing = true);
                                // Start WebRTC in background
                                ref.read(callProvider.notifier).acceptCall(
                                      callerIp: widget.callerIp,
                                      signalingPort: widget.signalingPort,
                                      callerId: widget.callerId,
                                      callerName: widget.callerName,
                                    );
                                // Navigate immediately — don't wait for WebRTC
                                if (mounted) {
                                  context.pushReplacement('/call/active');
                                }
                              },
                      ),
                    ],
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

// ── Avatar ────────────────────────────────────────────────────────────────────

class _IncomingAvatar extends StatefulWidget {
  const _IncomingAvatar({required this.name});
  final String name;

  @override
  State<_IncomingAvatar> createState() => _IncomingAvatarState();
}

class _IncomingAvatarState extends State<_IncomingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _ring = Tween(begin: 0.9, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.name.isNotEmpty
        ? widget.name.trim().split(' ').map((w) => w[0]).take(2).join()
        : '?';
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple ring
          AnimatedBuilder(
            animation: _ring,
            builder: (context, _) => Transform.scale(
              scale: _ring.value,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.statusOnline
                        .withValues(alpha: 1.0 - (_ring.value - 0.9) / 0.3),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          // Avatar circle
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.statusOnline, AppColors.primaryCyan],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.statusOnline.withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: AppTypography.heading2
                    .copyWith(color: Colors.white, fontSize: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Call Button ───────────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  /// Null disables the button (processing guard).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedOpacity(
            opacity: isDisabled ? 0.5 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
