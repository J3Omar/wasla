import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../discovery/data/discovery_service.dart';
import '../../discovery/domain/device_model.dart';
import '../data/chat_database.dart';
import '../domain/chat_message.dart';

final recentChatsProvider = StreamProvider<List<ChatMessage>>((ref) {
  return ChatDatabase.instance.watchRecentConversations();
});

final unreadCountsProvider = StreamProvider<Map<String, int>>((ref) {
  return ChatDatabase.instance.watchRecentConversations().map((_) {
    return ChatDatabase.instance.getUnreadCounts();
  });
});

final totalUnreadProvider = StreamProvider<int>((ref) {
  return ChatDatabase.instance.watchRecentConversations().map((_) {
    return ChatDatabase.instance.getTotalUnread();
  });
});

class ChatsListScreen extends ConsumerWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentChatsAsync = ref.watch(recentChatsProvider);
    final unreadCounts = ref.watch(unreadCountsProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSecondary,
        elevation: 0,
        title: Text(
          'Chats',
          style: AppTypography.heading3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: recentChatsAsync.when(
        data: (messages) {
          if (messages.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const Divider(
              color: AppColors.borderDefault,
              height: 1,
              indent: 72,
            ),
            itemBuilder: (context, index) {
              final msg = messages[index];
              final unread = unreadCounts[msg.peerId] ?? 0;
              return _ChatTile(message: msg, unreadCount: unread);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryCyan)),
        error: (e, st) => Center(
          child: Text('Error loading chats', style: TextStyle(color: Colors.red.shade300)),
        ),
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.message, this.unreadCount = 0});
  final ChatMessage message;
  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesState = ref.watch(discoveryServiceProvider);
    
    // Try to find the device in the current discovery list
    Device? peerDevice;
    if (devicesState is AsyncData<Map<String, Device>>) {
      peerDevice = devicesState.value[message.peerId];
    }

    // Try to get saved name from DB if offline
    final savedName = ChatDatabase.instance.getPeerName(message.peerId);
    
    // If online, save/update their name in DB
    if (peerDevice != null) {
      ChatDatabase.instance.upsertPeer(message.peerId, peerDevice.displayName);
    }

    final displayName = peerDevice?.displayName ?? savedName ?? 'Device (${message.peerId.substring(0, 4)}...)';
    final status = peerDevice?.status ?? DeviceStatus.offline;

    final timeStr = DateFormat.jm().format(message.timestamp);

    Color statusColor;
    switch (status) {
      case DeviceStatus.available:
        statusColor = Colors.greenAccent.shade400;
        break;
      case DeviceStatus.inCall:
        statusColor = Colors.redAccent;
        break;
      case DeviceStatus.offline:
      case DeviceStatus.busy:
        statusColor = Colors.orangeAccent;
        break;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryCyan.withValues(alpha: 0.2),
            child: Text(
              displayName[0].toUpperCase(),
              style: AppTypography.heading3.copyWith(color: AppColors.primaryCyan),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bgPrimary, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              displayName,
              style: unreadCount > 0
                  ? AppTypography.heading4.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)
                  : AppTypography.heading4,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: AppTypography.labelSmall.copyWith(
                  color: unreadCount > 0 ? AppColors.primaryCyan : AppColors.textMuted,
                ),
              ),
              if (unreadCount > 0)
                const SizedBox(height: 4),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.bgDeep,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          message.isSent ? 'You: ${message.content}' : message.content,
          style: AppTypography.bodyLarge.copyWith(
            color: unreadCount > 0 ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () {
        // If we have the full device object, pass it. 
        // Otherwise, create a dummy offline device to view history.
        final targetDevice = peerDevice ?? Device(
          uuid: message.peerId,
          displayName: displayName,
          localIp: '',
          port: 0,
          status: DeviceStatus.offline,
          lastSeen: DateTime.now(),
        );

        context.push('/chat/${message.peerId}', extra: targetDevice);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: AppColors.primaryCyan.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Recent Chats',
              style: AppTypography.heading3.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'To start chatting, go to the Devices tab, tap on a device, and click the Chat button.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
