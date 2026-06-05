import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/call_provider.dart';
import '../domain/call_state.dart';

/// Shown on the caller's device while ringing ("Calling...").
class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({super.key});

  @override
  ConsumerState<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen> {
  // Prevent double-pop from Future.delayed + immediate pop race
  bool _didPop = false;

  void _safePop() {
    if (_didPop) return;
    _didPop = true;
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final callState =
        ref.watch(callProvider).valueOrNull ?? CallSession.idle;

    // Auto-navigate when call becomes active or ends
    ref.listen(callProvider, (_, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      if (s.state == CallState.active) {
        if (mounted) context.pushReplacement('/call/active');
      } else if (s.state == CallState.ended) {
        // Brief pause so "No answer" / "Call declined" text is visible, then pop
        Future.delayed(const Duration(seconds: 2), _safePop);
      }
    });

    // Status text driven by call state
    final String statusText;
    final Color statusColor;
    switch (callState.state) {
      case CallState.ended when callState.endReason == CallEndReason.missed:
        statusText = 'No answer';
        statusColor = Colors.orangeAccent;
        break;
      case CallState.ended when callState.endReason == CallEndReason.declined:
        statusText = 'Call declined';
        statusColor = Colors.redAccent;
        break;
      case CallState.ended when callState.endReason == CallEndReason.busy:
        statusText = 'Device busy';
        statusColor = Colors.redAccent;
        break;
      case CallState.connecting:
        statusText = 'Connecting…';
        statusColor = AppColors.primaryCyan;
        break;
      default:
        statusText = 'Calling…';
        statusColor = AppColors.textMuted;
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Radial gradient background
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.4,
                colors: [
                  AppColors.primaryCyan.withValues(alpha: 0.15),
                  AppColors.bgPrimary,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                // Pulsing avatar
                _PulsingAvatar(name: callState.peerName),
                const SizedBox(height: 24),
                Text(
                  callState.peerName,
                  style: AppTypography.heading2
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: AppTypography.bodyMedium
                      .copyWith(color: statusColor),
                ),
                const Spacer(),
                // End call button — centered
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: GestureDetector(
                      onTap: () {
                        ref.read(callProvider.notifier).endCall();
                        _safePop();
                      },
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
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

// ── Pulsing Avatar ────────────────────────────────────────────────────────────

class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.name});
  final String name;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
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
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primaryCyan, AppColors.primaryPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryCyan.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Text(
            initials.toUpperCase(),
            style: AppTypography.heading2
                .copyWith(color: Colors.white, fontSize: 36),
          ),
        ),
      ),
    );
  }
}
