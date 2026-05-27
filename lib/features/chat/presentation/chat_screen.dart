import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../discovery/domain/device_model.dart';
import '../../discovery/data/discovery_service.dart';
import '../domain/chat_message.dart';
import '../data/chat_database.dart';
import 'chat_notifier.dart';
import '../../file_sharing/presentation/widgets/file_message_bubble.dart';
import '../../file_sharing/presentation/widgets/file_preview_card.dart';
import '../../file_sharing/data/file_transfer_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.device});
  final Device device;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  File? _selectedFile;

  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  bool _isLoadingMore = false;

  late final ChatArgs _args;

  @override
  void initState() {
    super.initState();
    _args = ChatArgs(
      peerId: widget.device.uuid,
      peerIp: widget.device.localIp,
      peerName: widget.device.displayName,
    );

    // Save the peer name to database so we remember it offline
    ChatDatabase.instance.upsertPeer(
      widget.device.uuid,
      widget.device.displayName,
    );

    _inputController.addListener(() {
      final has = _inputController.text.trim().isNotEmpty || _selectedFile != null;
      if (has != _hasText) setState(() => _hasText = has);
    });

    // Listen for scroll-to-top to trigger pagination
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // With reverse:true, pixels==0 is the TOP (oldest messages)
    if (_scrollController.position.pixels <= 80 && !_isLoadingMore) {
      _isLoadingMore = true;
      ref.read(chatProvider(_args).notifier).loadMoreMessages().then((_) {
        _isLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final text = _inputController.text.trim();
    final file = _selectedFile;
    if (text.isEmpty && file == null) return;

    if (file != null) {
      final fileSize = await file.length();
      if (fileSize > 500 * 1024 * 1024) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgSecondary,
            title: const Text('الملف كبير جداً', style: TextStyle(color: AppColors.textPrimary)),
            content: const Text('هذا الملف كبير جداً (+500MB). هل تريد المتابعة؟', style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryCyan),
                child: const Text('متابعة', style: TextStyle(color: AppColors.bgPrimary)),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      try {
        await FileTransferService.instance.sendFileRequest(
          peerId: _args.peerId,
          peerIp: _args.peerIp,
          filePath: file.path,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      
      setState(() {
        _selectedFile = null;
        _hasText = _inputController.text.trim().isNotEmpty;
      });
    }

    if (text.isNotEmpty) {
      ref.read(chatProvider(_args).notifier).sendMessage(text);
      _inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(_args));

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(chatState)
          : _buildAppBar(),
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
              data: (pageState) {
                final messages = pageState.messages;
                if (messages.isEmpty) {
                  return _EmptyConversation(device: widget.device);
                }
                return Stack(
                  children: [
                    // reverse: true means index 0 = newest, auto-anchors to bottom
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: messages.length + (pageState.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Loading indicator at top (last item in reversed list)
                        if (pageState.hasMore && index == messages.length) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: pageState.isLoadingMore
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primaryCyan,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          );
                        }

                        // reversed: index 0 = last message (newest)
                        final reversedIndex = messages.length - 1 - index;
                        final msg = messages[reversedIndex];
                        final prev = reversedIndex > 0
                            ? messages[reversedIndex - 1]
                            : null;
                        final showDate =
                            prev == null ||
                            !_sameDay(msg.timestamp, prev.timestamp);

                        return RepaintBoundary(
                          child: Column(
                            children: [
                              if (showDate) _DateDivider(date: msg.timestamp),
                              _MessageBubble(
                                message: msg,
                                peerIp: _args.peerIp,
                                isSelected: _selectedIds.contains(msg.id),
                                isSelectionMode: _isSelectionMode,
                                onTap: () {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      if (_selectedIds.contains(msg.id)) {
                                        _selectedIds.remove(msg.id);
                                        if (_selectedIds.isEmpty) {
                                          _isSelectionMode = false;
                                        }
                                      } else {
                                        _selectedIds.add(msg.id);
                                      }
                                    });
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedIds.add(msg.id);
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          _InputBar(
            controller: _inputController,
            focusNode: _focusNode,
            hasText: _hasText,
            peerName: widget.device.displayName,
            onSend: _onSend,
            selectedFile: _selectedFile,
            onPickFile: () async {
              final result = await FilePicker.platform.pickFiles();
              if (result != null && result.files.single.path != null) {
                setState(() {
                  _selectedFile = File(result.files.single.path!);
                  _hasText = true;
                });
              }
            },
            onCancelFile: () {
              setState(() {
                _selectedFile = null;
                _hasText = _inputController.text.trim().isNotEmpty;
              });
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
    AsyncValue<ChatPageState> chatState,
  ) {
    return AppBar(
      backgroundColor: AppColors.bgSecondary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
        onPressed: () {
          setState(() {
            _isSelectionMode = false;
            _selectedIds.clear();
          });
        },
      ),
      title: Text(
        '${_selectedIds.length} selected',
        style: AppTypography.heading3.copyWith(color: AppColors.textPrimary),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.select_all_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (chatState.hasValue) {
              setState(() {
                final allIds = chatState.value!.messages
                    .map((m) => m.id)
                    .toSet();
                if (_selectedIds.length == allIds.length) {
                  _selectedIds.clear();
                  _isSelectionMode = false;
                } else {
                  _selectedIds.addAll(allIds);
                }
              });
            }
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.redAccent,
          ),
          onPressed: () async {
            if (_selectedIds.isEmpty) return;
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.bgSecondary,
                title: Text('Delete Messages', style: AppTypography.heading3),
                content: Text(
                  'Are you sure you want to delete ${_selectedIds.length} message(s)?',
                  style: AppTypography.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      'Cancel',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      'Delete',
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              ChatDatabase.instance.deleteMessages(_selectedIds.toList());
              setState(() {
                _isSelectionMode = false;
                _selectedIds.clear();
              });
            }
          },
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final devicesState = ref.watch(discoveryServiceProvider);
    Device? currentDevice;
    if (devicesState is AsyncData<Map<String, Device>>) {
      currentDevice = devicesState.value[widget.device.uuid];
    }

    final displayDevice =
        currentDevice ?? widget.device.copyWith(status: DeviceStatus.offline);

    String statusText;
    Color statusColor;
    switch (displayDevice.status) {
      case DeviceStatus.available:
        statusText = 'Online • ${displayDevice.localIp}';
        statusColor = AppColors.statusOnline;
        break;
      case DeviceStatus.inCall:
        statusText = 'On Call • ${displayDevice.localIp}';
        statusColor = Colors.redAccent;
        break;
      case DeviceStatus.busy:
      case DeviceStatus.offline:
        statusText = 'Offline';
        statusColor = AppColors.statusOffline;
        break;
    }

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
          _PeerAvatar(name: displayDevice.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayDevice.displayName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    statusText,
                    style: AppTypography.labelSmall.copyWith(
                      color: statusColor,
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
          onSelected: (value) {
            if (value == 'delete') {
              setState(() {
                _isSelectionMode = true;
                _selectedIds.clear();
              });
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete messages', style: AppTypography.bodySmall),
            ),
          ],
        ),
      ],
    );
  }

  void _showComingSoon(BuildContext ctx, String feature) {
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text('$feature — coming soon!')));
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
  const _MessageBubble({
    required this.message,
    required this.peerIp,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final ChatMessage message;
  final String peerIp;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: isSelected
            ? AppColors.primaryCyan.withValues(alpha: 0.15)
            : Colors.transparent,
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8.0, left: 4.0),
                child: IgnorePointer(
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) {},
                    activeColor: AppColors.primaryCyan,
                    side: const BorderSide(color: AppColors.textMuted),
                  ),
                ),
              ),
            Expanded(
              child: Align(
                alignment: message.isSent
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Column(
                    crossAxisAlignment: message.isSent
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      message.type == MessageType.file
                          ? FileMessageBubble(message: message, isSentByMe: message.isSent, peerIp: peerIp)
                          : message.isSent
                              ? _SentBubble(message: message)
                              : _ReceivedBubble(message: message),
                      const SizedBox(height: 3),
                      _Timestamp(message: message),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
      case MessageStatus.queued:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.textMuted,
          ),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: AppColors.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: AppColors.textMuted);
      case MessageStatus.read:
        return const Icon(
          Icons.done_all,
          size: 14,
          color: AppColors.primaryCyan,
        );
      case MessageStatus.failed:
        return const Icon(
          Icons.error_outline,
          size: 14,
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
    required this.focusNode,
    required this.hasText,
    required this.peerName,
    required this.onSend,
    this.selectedFile,
    required this.onPickFile,
    required this.onCancelFile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final String peerName;
  final VoidCallback onSend;
  final File? selectedFile;
  final VoidCallback onPickFile;
  final VoidCallback onCancelFile;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedFile != null) FilePreviewCard(file: selectedFile!, onCancel: onCancelFile),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                color: AppColors.textMuted,
                onPressed: onPickFile,
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
                focusNode: focusNode,
                style: AppTypography.bodyMedium,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Write message...',
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
                  color: hasText ? AppColors.primaryCyan : AppColors.bgTertiary,
                  boxShadow: hasText
                      ? [
                          BoxShadow(
                            color: AppColors.primaryCyan.withValues(
                              alpha: 0.35,
                            ),
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
        ],
      ),
    );
  }
}
