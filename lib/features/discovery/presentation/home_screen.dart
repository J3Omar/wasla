import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/discovery_service.dart';
import '../domain/device_model.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryAsync = ref.watch(discoveryServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: _buildAppBar(context),
      body: discoveryAsync.when(
        loading: () => const _ScanningOverlay(),
        error: (e, _) => _ErrorView(error: e.toString()),
        data: (devicesMap) {
          // Separate self from other devices
          final self = devicesMap.values.where((d) => d.isSelf).toList();
          final others = devicesMap.values.where((d) => !d.isSelf).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));

          return _DeviceListView(self: self, others: others);
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          Image.asset('assets/images/Wasla-logo.png', height: 28),
          const SizedBox(width: 10),
          Text(
            'Wasla',
            style: AppTypography.heading3.copyWith(
              color: AppColors.primaryCyan,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.statusOnline.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.statusOnline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PulseDot(color: AppColors.statusOnline),
              const SizedBox(width: 6),
              Text(
                'Scanning',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.statusOnline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Device List View (Self card + Other Devices section) ─────────────────────

class _DeviceListView extends StatelessWidget {
  const _DeviceListView({required this.self, required this.others});
  final List<Device> self;
  final List<Device> others;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // Always show self device at top
        if (self.isNotEmpty) ...[
          Text(
            'YOUR DEVICE',
            style: AppTypography.capsLabel.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _DeviceCard(device: self.first),
          const SizedBox(height: 24),
        ],

        // Other devices section
        Text(
          'DEVICES ON NETWORK',
          style: AppTypography.capsLabel.copyWith(
            color: AppColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),

        if (others.isEmpty)
          const _NoOtherDevices()
        else
          ...others.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(device: d),
            ),
          ),
      ],
    );
  }
}

// ── Device Card ──────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(device.status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: device.isSelf
            ? AppColors.primaryCyan.withValues(alpha: 0.06)
            : AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: device.isSelf
              ? AppColors.primaryCyan.withValues(alpha: 0.3)
              : AppColors.borderDefault,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: device.isSelf
              ? null
              : () {
                  context.push(
                    '/chat/${device.uuid}',
                    extra: <String, dynamic>{
                      'peerName': device.displayName,
                      'isOnline': device.status != DeviceStatus.offline,
                    },
                  );
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    _DeviceAvatar(device: device, statusColor: statusColor),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  device.displayName,
                                  style: AppTypography.heading4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (device.isSelf) ...[
                                const SizedBox(width: 8),
                                _Badge(
                                  label: 'THIS DEVICE',
                                  color: AppColors.primaryCyan,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(device.localIp, style: AppTypography.ipAddress),
                        ],
                      ),
                    ),
                    // Status chip
                    _StatusChip(status: device.status, color: statusColor),
                  ],
                ),

                // Action buttons row for other devices (below info for mobile)
                if (!device.isSelf) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Chat',
                          color: AppColors.primaryCyan,
                          onTap: () {
                            context.push(
                              '/chat/${device.uuid}',
                              extra: <String, dynamic>{
                                'peerName': device.displayName,
                                'isOnline':
                                    device.status != DeviceStatus.offline,
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.call_outlined,
                          label: 'Call',
                          color: AppColors.statusOnline,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          color: AppColors.primaryPurple,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(DeviceStatus status) {
    return switch (status) {
      DeviceStatus.available => AppColors.statusOnline,
      DeviceStatus.inCall => AppColors.statusBusy,
      DeviceStatus.busy => AppColors.statusBusy,
      DeviceStatus.offline => AppColors.statusOffline,
    };
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({required this.device, required this.statusColor});
  final Device device;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.bgTertiary,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Center(
            child: Text(
              device.displayName.isNotEmpty
                  ? device.displayName[0].toUpperCase()
                  : '?',
              style: AppTypography.heading2.copyWith(
                color: AppColors.primaryCyan,
                fontSize: 22,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 1,
          right: 1,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bgPrimary, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});
  final DeviceStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      DeviceStatus.available => 'Available',
      DeviceStatus.inCall => 'In Call',
      DeviceStatus.busy => 'Busy',
      DeviceStatus.offline => 'Offline',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Full-width action tile (replaces small icon buttons for mobile friendliness)
class _ActionTile extends StatelessWidget {
  const _ActionTile({
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.labelSmall.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Empty / Loading / Error states ───────────────────────────────────────────

/// Shown when no OTHER devices are found (self still visible at top)
class _NoOtherDevices extends StatelessWidget {
  const _NoOtherDevices();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_find_outlined,
              size: 56,
              color: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No other devices found',
              style: AppTypography.heading4.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure other devices are running\nWasla on the same Wi-Fi network',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningOverlay extends StatefulWidget {
  const _ScanningOverlay();

  @override
  State<_ScanningOverlay> createState() => _ScanningOverlayState();
}

class _ScanningOverlayState extends State<_ScanningOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _ctrl,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: SweepGradient(
                  colors: [
                    AppColors.primaryCyan.withValues(alpha: 0.0),
                    AppColors.primaryCyan,
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Scanning network...', style: AppTypography.bodyMedium),
          const SizedBox(height: 8),
          Text(
            'Looking for devices on your LAN',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: AppColors.statusOffline,
            ),
            const SizedBox(height: 16),
            Text('Discovery failed', style: AppTypography.heading3),
            const SizedBox(height: 8),
            Text(
              error,
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
