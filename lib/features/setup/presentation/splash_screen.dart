import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/battery_optimization_util.dart';
import '../../../core/utils/rom_detector.dart';

const _kNameKey = 'wasla_device_name';

/// Animated splash screen — shows logo with glow + progress bar,
/// then navigates to /setup or /home based on stored device name.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _progressAnim;
  late Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // 3 seconds
    );

    _logoOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.25)));

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
      ),
    );

    _glowOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.1, 0.4)));

    // Progress bar takes exactly 3s to fill (the full duration)
    _progressAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    _ctrl.forward().then((_) => _navigate());
  }

  Future<void> _navigate() async {
    const storage = FlutterSecureStorage();

    // Battery Intercept Logic
    final handled = await storage.read(key: 'battery_prompt_handled') == 'true';
    if (!handled) {
      final disabled = await BatteryOptimizationUtil.isOptimizationDisabled();
      if (disabled) {
        await storage.write(key: 'battery_prompt_handled', value: 'true');
      } else {
        final brand = await RomDetector.getRestrictiveBrand();
        if (brand != null && mounted) {
          context.go(AppRoutes.batteryPrompt);
          return;
        }
      }
    }

    final name = await storage.read(key: _kNameKey);
    final needsSetup =
        name == null || name.isEmpty || name.startsWith('Device-');

    if (mounted) {
      context.go(needsSetup ? AppRoutes.onboarding : AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final glowSize = math.min(size.width * 0.9, 400.0);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Radial glow behind logo
          AnimatedBuilder(
            animation: _glowOpacity,
            builder: (context, _) => Opacity(
              opacity: _glowOpacity.value,
              child: Center(
                child: Container(
                  width: glowSize,
                  height: glowSize,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.splashGlowGradient,
                  ),
                ),
              ),
            ),
          ),

          // App Icon exactly in the center
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Opacity(
                opacity: _logoOpacity.value,
                child: Transform.scale(
                  scale: _logoScale.value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryCyan.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: Image.asset(
                        'assets/images/Wasla-logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // WASLA wordmark positioned below the glow circle
          Positioned(
            top: (size.height / 2) + (glowSize / 2) + 16,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.primaryGradient.createShader(bounds),
                      child: Text(
                        'WASLA',
                        style: AppTypography.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                          letterSpacing: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom progress section
          Positioned(
            left: 32,
            right: 32,
            bottom: 56,
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label
                  Row(
                    children: [
                      Icon(
                        Icons.wifi_tethering_rounded,
                        size: 14,
                        color: AppColors.primaryCyan.withValues(
                          alpha: _progressAnim.value,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ESTABLISHING MESH…',
                        style: AppTypography.capsLabel.copyWith(
                          color: AppColors.textMuted.withValues(
                            alpha: _progressAnim.value,
                          ),
                          fontSize: 11,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Progress bar track
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.bgTertiary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progressAnim.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryCyan.withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
