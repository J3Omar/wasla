import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'chat_database.dart';

const _kUuidKey = 'wasla_device_uuid';

// ── Chat Repository ───────────────────────────────────────────────────────────

class ChatRepository {
  ChatRepository(this._db);
  final ChatDatabase _db;

  /// Stream of all conversations (Chats tab).
  Stream<List<Conversation>> watchConversations() => _db.watchConversations();

  /// Stream of messages for a specific peer.
  Stream<List<Message>> watchMessages(String peerUuid) =>
      _db.watchMessages(peerUuid);

  /// Send a message — persists locally. Delivery over network is handled
  /// separately by the WebRTC/WebSocket layer when the peer is online.
  Future<void> sendMessage({
    required String peerUuid,
    required String peerName,
    required String body,
  }) async {
    const storage = FlutterSecureStorage();
    final myUuid = await storage.read(key: _kUuidKey) ?? 'self';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Ensure conversation exists with correct peer name
    await _db.upsertConversation(
      ConversationsCompanion.insert(
        peerUuid: peerUuid,
        peerName: peerName,
        lastMessage: Value(body),
        lastMessageAt: Value(now),
      ),
    );

    await _db.insertMessage(
      MessagesCompanion.insert(
        peerUuid: peerUuid,
        senderUuid: myUuid,
        body: body,
        sentAt: now,
        // deliveredAt null = pending
      ),
    );
  }

  /// Mark all messages in a conversation as read.
  Future<void> markRead(String peerUuid) => _db.markRead(peerUuid);

  /// Returns list of all peer UUIDs that have chat history.
  Future<List<String>> knownPeerUuids() => _db.knownPeerUuids();

  /// Get stored peer name.
  Future<String?> getPeerName(String peerUuid) => _db.getPeerName(peerUuid);

  /// Ensure conversation row exists (called when a peer is discovered).
  Future<void> ensureConversation({
    required String peerUuid,
    required String peerName,
  }) async {
    final existing = await _db.getPeerName(peerUuid);
    if (existing == null) {
      await _db.upsertConversation(
        ConversationsCompanion.insert(peerUuid: peerUuid, peerName: peerName),
      );
    } else if (existing != peerName) {
      // Peer renamed their device — update
      await _db.upsertConversation(
        ConversationsCompanion(
          peerUuid: Value(peerUuid),
          peerName: Value(peerName),
        ),
      );
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final db = ref.watch(chatDatabaseProvider);
  return ChatRepository(db);
});

final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchConversations();
});

final messagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  peerUuid,
) {
  return ref.watch(chatRepositoryProvider).watchMessages(peerUuid);
});
