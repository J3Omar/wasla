import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/battery_optimization_util.dart';

class BatteryPromptScreen extends StatefulWidget {
  const BatteryPromptScreen({super.key});

  @override
  State<BatteryPromptScreen> createState() => _BatteryPromptScreenState();
}

class _BatteryPromptScreenState extends State<BatteryPromptScreen> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkIfDisabled();
    }
  }

  Future<void> _checkIfDisabled() async {
    final disabled = await BatteryOptimizationUtil.isOptimizationDisabled();
    if (disabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Success! Background execution allowed.'),
          backgroundColor: AppColors.statusOnline,
        ),
      );
      await _markHandledAndProceed();
    }
  }

  Future<void> _markHandledAndProceed() async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'battery_prompt_handled', value: 'true');
    
    // Check if onboarding is needed, like in splash screen
    final name = await storage.read(key: 'wasla_device_name');
    final needsSetup = name == null || name.isEmpty || name.startsWith('Device-');
    
    if (mounted) {
      context.go(needsSetup ? AppRoutes.onboarding : AppRoutes.home);
    }
  }

  void _showSkipWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        title: const Text('Warning', style: TextStyle(color: AppColors.danger)),
        content: const Text(
          'The app may stop working in the background. Calls might not ring. Are you sure?',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Go back', style: TextStyle(color: AppColors.textPrimary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(ctx);
              _markHandledAndProceed();
            },
            child: const Text('I understand, skip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.battery_alert_rounded, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              Text(
                'Background Execution',
                style: AppTypography.heading2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Wasla needs to run in the background to receive incoming WebRTC calls and maintain file transfers. Please allow background execution in the next screen.',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryCyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await BatteryOptimizationUtil.requestDisableOptimization();
                  },
                  child: Text('Allow', style: AppTypography.heading3.copyWith(color: AppColors.bgDeep)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _showSkipWarning,
                child: Text('Skip', style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
