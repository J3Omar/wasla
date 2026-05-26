import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../discovery/domain/device_model.dart';
import '../../discovery/presentation/home_screen.dart';
import '../../chat/presentation/chats_list_screen.dart';
import '../../chat/data/webrtc_chat_service.dart';
import '../../chat/data/chat_database.dart';
import '../../chat/data/chat_notification_service.dart';
import '../../profile/presentation/profile_screen.dart';

/// Top-level navigation shell with 3 tabs.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _tabs = [
    HomeScreen(),
    ChatsListScreen(),
    ProfileScreen()
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Open database
      await ChatDatabase.instance.open();

      // Initialize notifications
      await ChatNotificationService.instance.initialize();

      // Start WebRTC chat service and load identity
      const storage = FlutterSecureStorage();
      final service = ref.read(webrtcChatServiceProvider);
      service.selfUuid ??= await storage.read(key: 'wasla_device_uuid') ?? '';
      service.selfName ??= await storage.read(key: 'wasla_device_name') ?? 'Wasla User';
      await service.start();

      // Wire notification display when a message arrives in background
      service.onMessageReceived = (peerId, senderName, content) {
        // Only show notification if user is NOT in this specific chat
        if (service.activeChatPeerId != peerId) {
          ChatNotificationService.instance.showMessageNotification(
            senderName: senderName,
            content: content,
            peerId: peerId,
          );
        }
      };

      // Handle notification tap to open chat screen
      ChatNotificationService.instance.onNotificationTap = (peerId) {
        if (!mounted) return;
        final savedName = ChatDatabase.instance.getPeerName(peerId) ?? 'Device';
        final targetDevice = Device(
          uuid: peerId,
          displayName: savedName,
          localIp: '',
          port: 0,
          status: DeviceStatus.offline,
          lastSeen: DateTime.now(),
        );
        context.push('/chat/$peerId', extra: targetDevice);
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = ref.watch(totalUnreadProvider).valueOrNull ?? 0;
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: _WaslaNavBar(
        currentIndex: _currentIndex,
        totalUnread: totalUnread,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── Custom Bottom Nav Bar ─────────────────────────────────────────────────────

class _WaslaNavBar extends StatelessWidget {
  const _WaslaNavBar({required this.currentIndex, required this.onTap, this.totalUnread = 0});
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int totalUnread;

  static const _items = [
    _NavItem(
      icon: Icons.wifi_find_outlined,
      activeIcon: Icons.wifi_find_rounded,
      label: 'Devices',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Chats',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(
          top: BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = i == currentIndex;
              // Only show unread badge for the Chats tab (index 1)
              final badge = (i == 1) ? totalUnread : 0;
              return Expanded(
                child: _NavButton(
                  item: item,
                  isActive: isActive,
                  badge: badge,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
    this.badge = 0,
  });
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicator pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 32 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                gradient: isActive ? AppColors.primaryGradient : null,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => isActive
                      ? AppColors.primaryGradient.createShader(bounds)
                      : const LinearGradient(
                          colors: [Color(0xFF849495), Color(0xFF849495)],
                        ).createShader(bounds),
                  child: Icon(
                    isActive ? item.activeIcon : item.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTypography.labelSmall.copyWith(
                color: isActive ? AppColors.primaryCyan : AppColors.textMuted,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
