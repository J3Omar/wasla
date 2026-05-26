import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/string_utils.dart';

const _kNameKey = 'wasla_device_name';
const _kUuidKey = 'wasla_device_uuid';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _name = '';
  String _uuid = '';
  String _localIp = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const storage = FlutterSecureStorage();
    final name = await storage.read(key: _kNameKey) ?? '';
    final uuid = await storage.read(key: _kUuidKey) ?? '';

    String ip = '';
    try {
      ip = await NetworkInfo().getWifiIP() ?? '';
    } catch (_) {
      try {
        // Fallback for Linux desktop
        for (final iface in await NetworkInterface.list()) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              ip = addr.address;
              break;
            }
          }
          if (ip.isNotEmpty) break;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _name = name;
        _uuid = uuid;
        _localIp = normalizeDigits(ip);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSecondary,
        title: Text('Profile', style: AppTypography.heading3),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderDefault),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryCyan),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar ─────────────────────────────────────────────
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryCyan.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                              style: AppTypography.heading1.copyWith(
                                color: AppColors.bgDeep,
                                fontSize: 40,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.statusOnline,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.bgPrimary,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Device name
                  Center(
                    child: Text(
                      _name,
                      style: AppTypography.heading2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusOnline.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.statusOnline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 8,
                            color: AppColors.statusOnline,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'This Device',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.statusOnline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Info cards ─────────────────────────────────────────
                  _SectionLabel(label: 'DEVICE INFO'),
                  const SizedBox(height: 12),

                  _InfoCard(
                    icon: Icons.badge_outlined,
                    label: 'Display Name',
                    value: _name,
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.primaryCyan,
                      ),
                      onPressed: () async {
                        await context.push(AppRoutes.onboarding);
                        _load(); // refresh after edit
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.wifi_rounded,
                    label: 'Local IP',
                    value: _localIp.isEmpty ? 'Not connected' : _localIp,
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.fingerprint_rounded,
                    label: 'Device UUID',
                    value: _uuid.isEmpty
                        ? 'Not set'
                        : '${_uuid.substring(0, 8)}…',
                  ),

                  const SizedBox(height: 36),

                  // ── Wasla branding ─────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Image.asset('assets/images/Wasla-logo.png', height: 48),
                        const SizedBox(height: 10),
                        Text(
                          'Wasla',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          'v0.1.0 — LAN Communication',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 10,
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.capsLabel.copyWith(
        color: AppColors.textMuted,
        fontSize: 11,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryCyan),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.bodyMedium.copyWith(
                    fontFamily: label == 'Device UUID' || label == 'Local IP'
                        ? 'JetBrains Mono'
                        : null,
                    fontSize: label == 'Device UUID' ? 13 : null,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
