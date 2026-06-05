import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../discovery/domain/device_model.dart';
import '../../discovery/data/discovery_service.dart';
import '../domain/chat_message.dart';
import '../data/chat_database.dart';
import '../data/webrtc_chat_service.dart';
import 'chat_notifier.dart';
import '../../file_sharing/presentation/widgets/file_message_bubble.dart';
import '../../file_sharing/presentation/widgets/file_preview_card.dart';
import '../../file_sharing/data/file_transfer_service.dart';
import '../../call/domain/call_provider.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

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
  File? _selectedFile;

  // Selection state as ValueNotifiers so toggling selection does NOT call
  // setState on _ChatScreenState, preventing Consumer + ListView rebuild.
  final _isSelectionMode = ValueNotifier(false);
  final _selectedIds = ValueNotifier(<int>{});
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

    // Listen for scroll-to-top to trigger pagination
    _scrollController.addListener(_onScroll);

    // Proactively warm up the WebRTC connection so the first message is fast.
    // Fire-and-forget: runs in background while user types.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(webrtcChatServiceProvider)
          .warmupConnection(peerId: widget.device.uuid, peerIp: _bestPeerIp());
    });
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
    _isSelectionMode.dispose();
    _selectedIds.dispose();
    super.dispose();
  }

  /// Get the best known IP for the peer — looks up the registry first so we
  /// always use the most recently discovered (and reachable) IP, not the
  /// stale one captured at initState.
  String _bestPeerIp() {
    final devicesState = ref.read(discoveryServiceProvider);
    if (devicesState is AsyncData<Map<String, Device>>) {
      final live = devicesState.value[widget.device.uuid];
      if (live != null && live.localIp.isNotEmpty) return live.localIp;
    }
    // Fall back to the IP stored in the chat database
    return ChatDatabase.instance.getPeerIp(widget.device.uuid) ??
        widget.device.localIp;
  }

  Future<void> _onSend() async {
    final text = _inputController.text.trim();
    final file = _selectedFile;
    if (text.isEmpty && file == null) return;

    // Always resolve the freshest peerIp — covers hotspot IP changes
    final peerIp = _bestPeerIp();

    if (file != null) {
      final fileSize = await file.length();
      if (fileSize > 500 * 1024 * 1024) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgSecondary,
            title: const Text(
              'File Too Large',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: const Text(
              'This file is very large (+500MB). Do you want to continue?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryCyan,
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(color: AppColors.bgPrimary),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      try {
        await FileTransferService.instance.sendFileRequest(
          peerId: _args.peerId,
          peerIp: peerIp,
          filePath: file.path,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }

      setState(() {
        _selectedFile = null;
      });
    }

    if (text.isNotEmpty) {
      // Pass freshest IP so the notifier routes the message to the right interface
      ref
          .read(chatProvider(_args).notifier)
          .sendMessage(text, freshPeerIp: peerIp);
      _inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Outer build() is now nearly static — only rebuilds when _selectedFile
    // changes (file pick/cancel). All message & selection rendering is isolated.
    return ValueListenableBuilder(
      valueListenable: _isSelectionMode,
      builder: (context, selectionMode, _) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          appBar: selectionMode
              ? _buildSelectionAppBar()
              : _buildAppBar(),
          body: Column(
            children: [
              Expanded(
                // Consumer isolates DB-driven rebuilds to the message list only
                child: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(chatProvider(_args));
                    return state.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryCyan,
                        ),
                      ),
                      error: (e, _) => Center(
                        child:
                            Text('Error: $e', style: AppTypography.bodySmall),
                      ),
                      data: (pageState) {
                        final messages = pageState.messages;
                        if (messages.isEmpty) {
                          return _EmptyConversation(device: widget.device);
                        }
                        return Stack(
                          children: [
                            ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: messages.length +
                                  (pageState.hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (pageState.hasMore &&
                                    index == messages.length) {
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

                                final reversedIndex =
                                    messages.length - 1 - index;
                                final msg = messages[reversedIndex];
                                final prev = reversedIndex > 0
                                    ? messages[reversedIndex - 1]
                                    : null;
                                final showDate = prev == null ||
                                    !_sameDay(
                                        msg.timestamp, prev.timestamp);

                                // Stable key → Flutter skips rebuild for
                                // unchanged items even when list order shifts
                                return RepaintBoundary(
                                  key: ValueKey(msg.id),
                                  child: Column(
                                    children: [
                                      if (showDate)
                                        _DateDivider(date: msg.timestamp),
                                      // Nested ValueListenableBuilders so that
                                      // tapping to select ONLY repaints the
                                      // affected bubble, not the entire list
                                      ValueListenableBuilder(
                                        valueListenable: _selectedIds,
                                        builder: (context, ids, _) =>
                                            ValueListenableBuilder(
                                          valueListenable: _isSelectionMode,
                                          builder: (context, selMode, _) =>
                                              _MessageBubble(
                                            message: msg,
                                            peerIp: _args.peerIp,
                                            isSelected: ids.contains(msg.id),
                                            isSelectionMode: selMode,
                                            onTap: () {
                                              if (selMode) {
                                                final next =
                                                    Set<int>.from(ids);
                                                if (next.contains(msg.id)) {
                                                  next.remove(msg.id);
                                                  if (next.isEmpty) {
                                                    _isSelectionMode.value =
                                                        false;
                                                  }
                                                } else {
                                                  next.add(msg.id);
                                                }
                                                _selectedIds.value = next;
                                              }
                                            },
                                            onLongPress: () {
                                              if (!selMode) {
                                                _selectedIds.value = {msg.id};
                                                _isSelectionMode.value = true;
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              _InputBar(
                controller: _inputController,
                focusNode: _focusNode,
                peerName: widget.device.displayName,
                onSend: _onSend,
                selectedFile: _selectedFile,
                onPickFile: () async {
                  final result = await FilePicker.platform.pickFiles();
                  if (result != null && result.files.single.path != null) {
                    setState(() {
                      _selectedFile = File(result.files.single.path!);
                    });
                  }
                },
                onCancelFile: () {
                  setState(() => _selectedFile = null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final ids = _selectedIds.value;
    final chatState = ref.read(chatProvider(_args));
    return AppBar(
      backgroundColor: AppColors.bgSecondary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
        onPressed: () {
          _isSelectionMode.value = false;
          _selectedIds.value = {};
        },
      ),
      title: Text(
        '${ids.length} selected',
        style: AppTypography.heading3.copyWith(color: AppColors.textPrimary),
      ),
      actions: [
        if (chatState.hasValue) ...[
          Builder(
            builder: (context) {
              final messages = chatState.value!.messages;
              final selectedMessages =
                  messages.where((m) => ids.contains(m.id)).toList();
              final hasTextSelected = selectedMessages.any(
                (m) => m.type == MessageType.text,
              );
              if (!hasTextSelected) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.copy, color: AppColors.textPrimary),
                tooltip: 'Copy',
                onPressed: () {
                  final textOnly = selectedMessages
                      .where((m) => m.type == MessageType.text)
                      .map((m) => m.content)
                      .join('\n');
                  Clipboard.setData(ClipboardData(text: textOnly));
                  _isSelectionMode.value = false;
                  _selectedIds.value = {};
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        selectedMessages.length == 1
                            ? 'Message copied'
                            : '${selectedMessages.where((m) => m.type == MessageType.text).length} messages copied',
                      ),
                      duration: const Duration(seconds: 2),
                      backgroundColor: AppColors.bgTertiary,
                    ),
                  );
                },
              );
            },
          ),
        ],
        IconButton(
          icon: const Icon(
            Icons.select_all_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (chatState.hasValue) {
              final allIds =
                  chatState.value!.messages.map((m) => m.id).toSet();
              if (ids.length == allIds.length) {
                _selectedIds.value = {};
                _isSelectionMode.value = false;
              } else {
                _selectedIds.value = allIds;
              }
            }
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.redAccent,
          ),
          onPressed: () async {
            if (ids.isEmpty) return;
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.bgSecondary,
                title: Text('Delete Messages', style: AppTypography.heading3),
                content: Text(
                  'Are you sure you want to delete ${ids.length} message(s)?',
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
              ChatDatabase.instance.deleteMessages(ids.toList());
              _isSelectionMode.value = false;
              _selectedIds.value = {};
              final remaining =
                  ChatDatabase.instance.countMessages(widget.device.uuid);
              if (remaining == 0 && mounted) {
                Navigator.of(context).pop();
              }
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
            color: AppColors.statusOnline,
            size: 20,
          ),
          tooltip: 'Voice call',
          onPressed: () async {
            final peerIp = _bestPeerIp();
            await ref.read(callProvider.notifier).startCall(
                  peerId: widget.device.uuid,
                  peerName: widget.device.displayName,
                  peerIp: peerIp,
                );
            if (mounted) {
              context.push('/call/outgoing');
            }
          },
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
              _selectedIds.value = {};
              _isSelectionMode.value = true;
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
                          ? FileMessageBubble(
                              message: message,
                              isSentByMe: message.isSent,
                              peerIp: peerIp,
                            )
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
      child: _buildMessageText(context, message.content, isSent: true),
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
      child: _buildMessageText(context, message.content, isSent: false),
    );
  }
}

// URL detection regex
final _urlRegex = RegExp(
  r'(https?://[^\s]+|www\.[^\s]+)',
  caseSensitive: false,
);

Widget _buildMessageText(
  BuildContext context,
  String content, {
  required bool isSent,
}) {
  final matches = _urlRegex.allMatches(content);
  final defaultStyle = AppTypography.bodyMedium.copyWith(
    color: isSent ? Colors.white : AppColors.textPrimary,
  );

  if (matches.isEmpty) {
    // No URLs — plain text as before
    return Text(content, style: defaultStyle);
  }

  // Build RichText with clickable URL spans
  final spans = <InlineSpan>[];
  int lastEnd = 0;

  for (final match in matches) {
    // Text before URL
    if (match.start > lastEnd) {
      spans.add(
        TextSpan(
          text: content.substring(lastEnd, match.start),
          style: defaultStyle,
        ),
      );
    }

    // The URL itself
    final url = match.group(0)!;
    spans.add(
      TextSpan(
        text: url,
        style: defaultStyle.copyWith(
          color: isSent ? Colors.white : AppColors.primaryCyan,
          decoration: TextDecoration.underline,
          decorationColor: isSent ? Colors.white : AppColors.primaryCyan,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _confirmAndOpenUrl(context, url),
      ),
    );

    lastEnd = match.end;
  }

  // Remaining text after last URL
  if (lastEnd < content.length) {
    spans.add(TextSpan(text: content.substring(lastEnd), style: defaultStyle));
  }

  return RichText(text: TextSpan(children: spans));
}

Future<void> _confirmAndOpenUrl(BuildContext context, String rawUrl) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgSecondary,
          title: const Text(
            'Open External Link',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            'You are about to leave Wasla and open your browser.\nDo you want to continue?\n\n$rawUrl',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryCyan,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Open',
                style: TextStyle(color: AppColors.bgPrimary),
              ),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed) return;

  // Add https:// if missing
  final urlStr = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';
  final uri = Uri.tryParse(urlStr);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.peerName,
    required this.onSend,
    this.selectedFile,
    required this.onPickFile,
    required this.onCancelFile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String peerName;
  final VoidCallback onSend;
  final File? selectedFile;
  final VoidCallback onPickFile;
  final VoidCallback onCancelFile;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // Listen locally — setState only rebuilds _InputBar, not the whole screen
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final has =
        widget.controller.text.trim().isNotEmpty || widget.selectedFile != null;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void didUpdateWidget(_InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // selectedFile changed from parent — re-evaluate hasText
    if (oldWidget.selectedFile != widget.selectedFile) {
      final has =
          widget.controller.text.trim().isNotEmpty ||
          widget.selectedFile != null;
      if (has != _hasText) setState(() => _hasText = has);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

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
          if (widget.selectedFile != null)
            FilePreviewCard(
              file: widget.selectedFile!,
              onCancel: widget.onCancelFile,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                color: AppColors.textMuted,
                onPressed: widget.onPickFile,
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
                    controller: widget.controller,
                    focusNode: widget.focusNode,
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
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: _hasText ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: GestureDetector(
                  onTap: widget.onSend,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasText
                          ? AppColors.primaryCyan
                          : AppColors.bgTertiary,
                      boxShadow: _hasText
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
                      color: _hasText ? AppColors.bgDeep : AppColors.textMuted,
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
