import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../discovery/domain/device_model.dart';
import '../domain/chat_message.dart';
import 'chat_notifier.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.device});

  final Device device;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasText = false;

  late final ChatArgs _args;

  @override
  void initState() {
    super.initState();
    _args = ChatArgs(
      peerId: widget.device.uuid,
      peerIp: widget.device.localIp,
      peerName: widget.device.displayName,
    );
    _inputController.addListener(() {
      final has = _inputController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await ref.read(chatProvider(_args).notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(_args));

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: chatState.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primaryCyan),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e', style: AppTypography.bodySmall),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return _EmptyConversation(device: widget.device);
                }
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final prev = index > 0 ? messages[index - 1] : null;
                    final showDate =
                        prev == null || !_sameDay(msg.timestamp, prev.timestamp);
                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: msg.timestamp),
                        _MessageBubble(message: msg),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _inputController,
            hasText: _hasText,
            peerName: widget.device.displayName,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgSecondary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: AppColors.textPrimary,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          _PeerAvatar(name: widget.device.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.displayName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '▾ ${widget.device.localIp}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.statusOnline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.phone_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: () => _showComingSoon(context, 'Voice call'),
        ),
        IconButton(
          icon: const Icon(
            Icons.videocam_rounded,
            color: AppColors.textSecondary,
            size: 22,
          ),
          onPressed: () => _showComingSoon(context, 'Video call'),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          color: AppColors.bgSecondary,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              child: Text('Clear chat', style: AppTypography.bodySmall),
            ),
          ],
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext ctx, String feature) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('$feature — coming soon!')),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────────────────────
// Peer Avatar
// ─────────────────────────────────────────────────────────────────────────────

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: Center(
        child: Text(
          letter,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.bgDeep,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty Conversation State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => AppColors.primaryGradient.createShader(r),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text('Start the conversation', style: AppTypography.heading3),
          const SizedBox(height: 8),
          Text(
            'Messages are sent directly over\nyour local network.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date Divider
// ─────────────────────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_sameDay(date, now)) {
      label = 'Today';
    } else if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.borderDefault)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.borderDefault)),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Bubble
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment:
            message.isSent ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: message.isSent
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              message.isSent
                  ? _SentBubble(message: message)
                  : _ReceivedBubble(message: message),
              const SizedBox(height: 3),
              _Timestamp(message: message),
            ],
          ),
        ),
      ),
    );
  }
}

class _SentBubble extends StatelessWidget {
  const _SentBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.sentMessageGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryCyan.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message.content,
        style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      ),
    );
  }
}

class _ReceivedBubble extends StatelessWidget {
  const _ReceivedBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.bgTertiary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Text(
        message.content,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a').format(message.timestamp);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
          ),
        ),
        if (message.isSent) ...[
          const SizedBox(width: 4),
          _StatusIcon(status: message.status),
        ],
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.textMuted,
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: AppColors.textMuted);
      case MessageStatus.delivered:
        return const Icon(
          Icons.done_all,
          size: 12,
          color: AppColors.primaryCyan,
        );
      case MessageStatus.failed:
        return const Icon(
          Icons.error_outline,
          size: 12,
          color: AppColors.statusOffline,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input Bar
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.peerName,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool hasText;
  final String peerName;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
            color: AppColors.textMuted,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File sharing — coming soon!')),
              );
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.bgTertiary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderDefault),
              ),
              child: TextField(
                controller: controller,
                style: AppTypography.bodyMedium,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message ${peerName.split(' ').first}…',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedScale(
            scale: hasText ? 1.0 : 0.85,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: GestureDetector(
              onTap: onSend,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasText
                      ? AppColors.primaryCyan
                      : AppColors.bgTertiary,
                  boxShadow: hasText
                      ? [
                          BoxShadow(
                            color: AppColors.primaryCyan.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: hasText ? AppColors.bgDeep : AppColors.textMuted,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
