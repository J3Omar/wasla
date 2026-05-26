import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../discovery/data/discovery_service.dart';

const _kNameKey = 'wasla_device_name';

/// First-launch screen — user sets their device display name.
class SetupNameScreen extends ConsumerStatefulWidget {
  const SetupNameScreen({super.key});

  @override
  ConsumerState<SetupNameScreen> createState() => _SetupNameScreenState();
}

class _SetupNameScreenState extends ConsumerState<SetupNameScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestedName();
  }

  /// Try to read device model/hostname as a suggested name.
  Future<void> _loadSuggestedName() async {
    try {
      final info = DeviceInfoPlugin();
      String suggested = '';

      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        // e.g. "Samsung Galaxy S23" or "Pixel 7"
        suggested = android.model;
      } else if (Platform.isLinux) {
        final linux = await info.linuxInfo;
        suggested = linux.prettyName.isNotEmpty ? linux.prettyName : linux.name;
      } else if (Platform.isWindows) {
        final windows = await info.windowsInfo;
        suggested = windows.computerName;
      } else if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        suggested = mac.computerName;
      }

      if (mounted) {
        _controller.text = suggested;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: suggested.length,
        );
      }
    } catch (_) {
      // If device info fails, leave field empty — user types manually
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    const storage = FlutterSecureStorage();
    await storage.write(key: _kNameKey, value: _controller.text.trim());

    if (mounted) {
      // Update the discovery service in-place — no restart, no port rebinding.
      // The home screen reflects the new name immediately; a UDP broadcast
      // announces it to all peers on the LAN within seconds.
      final notifier = ref.read(discoveryServiceProvider.notifier);
      notifier.updateSelfName();

      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: context.canPop()
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => context.pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryCyan),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 48,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),

                      // ── Logo ────────────────────────────────────────────
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/Wasla-logo.png',
                            height: 40,
                          ),
                          const SizedBox(width: 12),
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              'Wasla',
                              style: AppTypography.heading1.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),

                      // ── Heading ─────────────────────────────────────────
                      Text('Set up your device', style: AppTypography.heading2),
                      const SizedBox(height: 8),
                      Text(
                        'Other devices on the network will see this name. '
                        'You can change it later in settings.',
                        style: AppTypography.bodySmall,
                      ),

                      const SizedBox(height: 36),

                      // ── Name Field ──────────────────────────────────────
                      Text(
                        'DEVICE NAME',
                        style: AppTypography.capsLabel.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        style: AppTypography.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'e.g. My Phone',
                          hintStyle: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textMuted,
                          ),
                          filled: true,
                          fillColor: AppColors.bgSecondary,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppColors.borderDefault,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppColors.primaryCyan,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.statusOffline,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.statusOffline,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (val) {
                          final v = val?.trim() ?? '';
                          if (v.length < 2)
                            return 'Name must be at least 2 characters';
                          if (v.length > 30)
                            return 'Name must be 30 characters or less';
                          return null;
                        },
                      ),

                      const SizedBox(height: 36),

                      // ── CTA Button ──────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryCyan.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Start Connecting',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.bgDeep,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
