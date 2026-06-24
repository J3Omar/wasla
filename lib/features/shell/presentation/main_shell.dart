import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../file_sharing/data/file_transfer_service.dart';
import '../../profile/presentation/profile_screen.dart';
import 'dart:io';
import '../../call/domain/call_provider.dart';
import '../../call/domain/call_state.dart';
import '../../call/data/call_audio_service.dart';
import '../../discovery/data/discovery_service.dart';
import '../../../core/utils/background_service_manager.dart';

/// Top-level navigation shell with 3 tabs.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _tabs = [HomeScreen(), ChatsListScreen(), ProfileScreen()];

  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onDetach: () {
        // Force cleanup background services so they don't zombie
        BackgroundServiceManager.instance.releaseAll();
        // Best-effort offline broadcast before process dies
        ref
            .read(discoveryServiceProvider.notifier)
            .updateLocalStatus(DeviceStatus.offline);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Open database
      await ChatDatabase.instance.open();

      // Initialize notifications
      await ChatNotificationService.instance.initialize();
      // Start WebRTC chat service and load identity
      const storage = FlutterSecureStorage();
      final service = ref.read(webrtcChatServiceProvider);

      // Initialize file transfer service
      FileTransferService.instance.init(service);

      service.selfUuid ??= await storage.read(key: 'wasla_device_uuid') ?? '';
      service.selfName ??=
          await storage.read(key: 'wasla_device_name') ?? 'Wasla User';
      await service.start();

      // Wire notification display when a message arrives in background
      service.onMessageReceived = (peerId, senderName, content) {
        final isInChat = service.activeChatPeerId == peerId;

        if (isInChat) {
          // User is looking at this chat — play in-chat sound only
          // No notification needed
          CallAudioService.instance.playMessageReceived();
        } else {
          // User is elsewhere — show notification with sound
          ChatNotificationService.instance.showMessageNotification(
            senderName: senderName,
            content: content,
            peerId: peerId,
          );
          // Desktop: notification service doesn't play mp3 natively
          // so we play notification.mp3 manually here
          if (!Platform.isAndroid && !Platform.isIOS) {
            CallAudioService.instance.playNotification();
          }
          // Android: notification channel handles its own sound
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

      // Start call provider (spins up UDP invite listener on port 45680)
      final callNotifier = ref.read(callProvider.notifier);
      // Wire incoming call → navigate to IncomingCallScreen
      callNotifier.onIncomingCall = (info) {
        if (!mounted) return;
        debugPrint('[DEBUG] callerName to router: "${info['peerName']}"');
        context.push(
          '/call/incoming',
          extra: {
            'callerId': info['peerId'] as String,
            'callerName': info['peerName'] as String,
            'callerIp': info['callerIp'] as String,
            'signalingPort': info['signalingPort'] as int,
            'isVideo': info['isVideo'] as bool? ?? false,
          },
        );
      };
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = ref.watch(totalUnreadProvider).valueOrNull ?? 0;
    final session = ref.watch(callProvider).valueOrNull;
    final isInCall =
        session != null &&
        (session.state == CallState.active ||
            session.state == CallState.connecting ||
            session.state == CallState.outgoing);

    final hasActiveTransfers = FileTransferService.instance.hasActiveTransfers;
    final hasActiveOperation = isInCall || hasActiveTransfers;

    return PopScope(
      canPop: !hasActiveOperation,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Active call or transfer in progress"),
            content: const Text(
              "Closing the app now will end your call or interrupt a file transfer. Are you sure you want to exit?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Exit anyway"),
              ),
            ],
          ),
        );

        if (shouldPop == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Column(
          children: [
            if (isInCall)
              SafeArea(
                bottom: false,
                child: GestureDetector(
                  onTap: () {
                    if (session.state == CallState.outgoing) {
                      context.push('/call/outgoing');
                    } else {
                      context.push('/call/active'); // connecting or active
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    color: Colors.amber.withValues(alpha: 0.9),
                    padding: const EdgeInsets.only(
                      top: 4,
                      bottom: 4,
                      left: 16,
                      right: 16,
                    ),
                    height: 32,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.phone_in_talk_rounded,
                          size: 14,
                          color: Colors.black87,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'In Call — tap to return',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _tabs),
            ),
          ],
        ),
        bottomNavigationBar: _WaslaNavBar(
          currentIndex: _currentIndex,
          totalUnread: totalUnread,
          onTap: (i) => setState(() => _currentIndex = i),
        ),
      ),
    );
  }
}

// ── Custom Bottom Nav Bar ─────────────────────────────────────────────────────

class _WaslaNavBar extends StatelessWidget {
  const _WaslaNavBar({
    required this.currentIndex,
    required this.onTap,
    this.totalUnread = 0,
  });
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
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
