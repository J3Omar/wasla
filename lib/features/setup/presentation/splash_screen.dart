import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/router/app_router.dart';

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
      duration: const Duration(milliseconds: 2200),
    );

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.35)),
    );

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );

    _glowOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.15, 0.55)),
    );

    _progressAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 0.95, curve: Curves.easeInOut),
      ),
    );

    _ctrl.forward().then((_) => _navigate());
  }

  Future<void> _navigate() async {
    const storage = FlutterSecureStorage();
    final name = await storage.read(key: _kNameKey);
    final needsSetup =
        name == null || name.isEmpty || name.startsWith('Device-');

    if (mounted) {
      context.go(needsSetup ? AppRoutes.setup : AppRoutes.home);
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
                  width: size.width * 0.9,
                  height: size.width * 0.9,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.splashGlowGradient,
                  ),
                ),
              ),
            ),
          ),

          // Logo + wordmark
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Opacity(
                opacity: _logoOpacity.value,
                child: Transform.scale(
                  scale: _logoScale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App icon
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryCyan.withValues(alpha: 0.35),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/images/Wasla-logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // WASLA wordmark
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.primaryGradient.createShader(bounds),
                        child: Text(
                          'WASLA',
                          style: AppTypography.heading1.copyWith(
                            color: Colors.white,
                            fontSize: 36,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Arabic subtitle
                      Text(
                        'وصلة',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
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
                              color: AppColors.primaryCyan.withValues(alpha: 0.5),
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
