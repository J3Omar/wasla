import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_database.dart';
import '../data/webrtc_chat_service.dart';
import '../data/chat_notification_service.dart';
import '../domain/chat_message.dart';

const _kNameKey = 'wasla_device_name';
const _kUuidKey = 'wasla_device_uuid';
const _kPageSize = 20;
const _uuid = Uuid();

// ── Chat Page State ───────────────────────────────────────────────────────────

class ChatPageState {
  const ChatPageState({
    required this.messages,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final bool isLoadingMore;

  ChatPageState copyWith({
    List<ChatMessage>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return ChatPageState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final chatProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      ChatNotifier,
      ChatPageState,
      ChatArgs
    >(ChatNotifier.new);

class ChatArgs {
  const ChatArgs({
    required this.peerId,
    required this.peerIp,
    required this.peerName,
  });
  final String peerId;
  final String peerIp;
  final String peerName;

  @override
  bool operator ==(Object other) => other is ChatArgs && other.peerId == peerId;

  @override
  int get hashCode => peerId.hashCode;
}

// ── ChatNotifier ──────────────────────────────────────────────────────────────

class ChatNotifier
    extends AutoDisposeFamilyAsyncNotifier<ChatPageState, ChatArgs> {
  StreamSubscription<List<ChatMessage>>? _dbSub;
  int _loadedCount = _kPageSize;

  @override
  Future<ChatPageState> build(ChatArgs arg) async {
    await ChatDatabase.instance.open();

    // Save peer's IP so the offline queue can reach them later
    if (arg.peerIp.isNotEmpty) {
      ChatDatabase.instance.upsertPeer(arg.peerId, arg.peerName, arg.peerIp);
    }

    final service = ref.read(webrtcChatServiceProvider);

    // Mark this peer as the active chat (so incoming messages get read ACK)
    service.activeChatPeerId = arg.peerId;

    // Dismiss any pending notification for this peer — covers both tapping
    // the notification AND navigating to the chat manually.
    ChatNotificationService.instance.cancelNotification(arg.peerId);

    // Load identity so WebRTC service can sign messages
    const storage = FlutterSecureStorage();
    service.selfUuid ??= await storage.read(key: _kUuidKey) ?? '';
    service.selfName ??= await storage.read(key: _kNameKey) ?? 'Wasla User';

    // Subscribe to DB changes and rebuild immediately.
    // _mergeMessages is idempotent, so duplicate emissions are harmless.
    _dbSub = ChatDatabase.instance.watchMessages(arg.peerId).listen((msgs) {
      if (state.hasValue) {
        final current = state.value!;
        state = AsyncData(
          current.copyWith(messages: _mergeMessages(current.messages, msgs)),
        );
      }
    });

    ref.onDispose(() {
      _dbSub?.cancel();
      if (service.activeChatPeerId == arg.peerId) {
        service.activeChatPeerId = null;
      }
    });

    // Load initial page (last 30 messages, chronologically)
    final total = ChatDatabase.instance.countMessages(arg.peerId);
    final initialMessages = ChatDatabase.instance.getMessagesPaged(
      arg.peerId,
      offset: 0,
      limit: _kPageSize,
    );

    // Mark all received messages as read and send bulk ACK to sender
    await _markAllReadAndAck(service, initialMessages);

    return ChatPageState(
      messages: initialMessages,
      hasMore: total > _kPageSize,
    );
  }

  /// Load 30 older messages (scroll-up pagination).
  Future<void> loadMoreMessages() async {
    if (!state.hasValue) return;
    final current = state.value!;
    if (!current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final total = ChatDatabase.instance.countMessages(arg.peerId);
    final nextOffset = _loadedCount;
    final older = ChatDatabase.instance.getMessagesPaged(
      arg.peerId,
      offset: nextOffset,
      limit: _kPageSize,
    );

    _loadedCount += older.length;

    state = AsyncData(
      current.copyWith(
        messages: [...older, ...current.messages],
        hasMore: _loadedCount < total,
        isLoadingMore: false,
      ),
    );
  }

  /// Send a text message to the peer.
  /// [freshPeerIp] — pass the latest known IP from the device registry so
  /// the hotspot host's correct interface IP is always used.
  Future<void> sendMessage(String text, {String? freshPeerIp}) async {
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    final service = ref.read(webrtcChatServiceProvider);

    // Use the freshest known IP, update the DB so the retry queue benefits too
    final peerIp = (freshPeerIp != null && freshPeerIp.isNotEmpty)
        ? freshPeerIp
        : arg.peerIp;
    if (freshPeerIp != null && freshPeerIp.isNotEmpty) {
      ChatDatabase.instance.upsertPeer(arg.peerId, arg.peerName, freshPeerIp);
    }

    // Create draft with a stable UUID
    final draft = ChatMessage(
      id: 0,
      messageUuid: _uuid.v4(),
      peerId: arg.peerId,
      content: text.trim(),
      isSent: true,
      timestamp: now,
      status: MessageStatus.queued,
      type: MessageType.text,
    );

    // Optimistically insert (triggers DB stream → UI update)
    final saved = ChatDatabase.instance.insert(draft);

    // Try to send via WebRTC
    final sent = await service.sendChatMessage(
      peerId: arg.peerId,
      peerIp: peerIp,
      message: saved,
    );

    // Update status — if sent, mark as sent; if not, stay queued (retry timer handles it)
    ChatDatabase.instance.updateStatus(
      saved.id,
      sent ? MessageStatus.sent : MessageStatus.queued,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _markAllReadAndAck(
    WebRtcChatService service,
    List<ChatMessage> messages,
  ) async {
    // Find unread received messages
    final unread = messages.where((m) => !m.isSent && !m.isRead).toList();
    if (unread.isEmpty) return;

    // Mark locally
    ChatDatabase.instance.markAllRead(arg.peerId);

    // Send bulk read ACK if we have an active connection
    final latestTs = unread
        .map((m) => m.timestamp.millisecondsSinceEpoch)
        .reduce((a, b) => a > b ? a : b);
    await service.sendAckReadAll(
      peerIp: arg.peerIp,
      peerId: arg.peerId,
      upToTimestamp: latestTs,
    );
  }

  /// Merge new messages from the DB stream with the currently displayed list.
  /// Handles both new incoming messages (appends) and deletions (removes).
  List<ChatMessage> _mergeMessages(
    List<ChatMessage> current,
    List<ChatMessage> all,
  ) {
    // If the DB says there are no messages at all, trust it (bulk delete case)
    if (all.isEmpty) return [];
    if (current.isEmpty) return all;
    // Get the timestamp of the oldest loaded message to know our lower bound
    final oldestLoaded = current.first.timestamp;
    // From all messages, keep those >= oldestLoaded (don't go beyond pagination)
    final filtered = all
        .where((m) => !m.timestamp.isBefore(oldestLoaded))
        .toList();
    // If filtered is empty but 'all' is not, the remaining messages are older
    // than our page window — show all (handles partial deletions near page boundary)
    return filtered.isEmpty ? all : filtered;
  }
}
