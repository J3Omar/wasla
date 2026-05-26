import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'chat_database.g.dart';

// ── Table Definitions ─────────────────────────────────────────────────────────

/// One row per remote peer — a "conversation thread".
class Conversations extends Table {
  TextColumn get peerUuid => text()();
  TextColumn get peerName => text()();
  TextColumn get lastMessage => text().withDefault(const Constant(''))();
  IntColumn get lastMessageAt =>
      integer().withDefault(const Constant(0))(); // epoch ms
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {peerUuid};
}

/// Individual messages within a conversation.
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get peerUuid => text()(); // FK → conversations.peerUuid
  TextColumn get senderUuid => text()(); // this device or peer
  TextColumn get body => text()();
  IntColumn get sentAt => integer()(); // epoch ms
  IntColumn get deliveredAt => integer().nullable()(); // null = pending
  IntColumn get readAt => integer().nullable()();
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Conversations, Messages])
class ChatDatabase extends _$ChatDatabase {
  ChatDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All conversations with messages, ordered by most recent message.
  Stream<List<Conversation>> watchConversations() {
    return (select(conversations)
          ..where((t) => t.lastMessage.equals('').not())
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastMessageAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// Upsert a conversation row (creates if absent, updates otherwise).
  Future<void> upsertConversation(ConversationsCompanion data) {
    return into(conversations).insertOnConflictUpdate(data);
  }

  /// All messages for a peer, oldest first.
  Stream<List<Message>> watchMessages(String peerUuid) {
    return (select(messages)
          ..where((t) => t.peerUuid.equals(peerUuid))
          ..orderBy([(t) => OrderingTerm(expression: t.sentAt)]))
        .watch();
  }

  /// Insert a new message and update the parent conversation summary.
  Future<void> insertMessage(MessagesCompanion msg) async {
    await into(messages).insert(msg);

    final body = msg.body.value;
    final ts = msg.sentAt.value;
    final peer = msg.peerUuid.value;

    // Check if conversation exists
    final existing = await (select(conversations)
          ..where((t) => t.peerUuid.equals(peer)))
        .getSingleOrNull();

    if (existing == null) {
      // Auto-create conversation row
      await into(conversations).insert(
        ConversationsCompanion.insert(
          peerUuid: peer,
          peerName: 'Unknown Device',
          lastMessage: Value(body),
          lastMessageAt: Value(ts),
        ),
      );
    } else {
      await (update(conversations)..where((t) => t.peerUuid.equals(peer)))
          .write(ConversationsCompanion(
        lastMessage: Value(body),
        lastMessageAt: Value(ts),
      ));
    }
  }

  /// Mark a conversation's messages as read and reset unread count.
  Future<void> markRead(String peerUuid) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(messages)
          ..where((t) =>
              t.peerUuid.equals(peerUuid) & t.readAt.isNull()))
        .write(MessagesCompanion(readAt: Value(now)));

    await (update(conversations)
          ..where((t) => t.peerUuid.equals(peerUuid)))
        .write(const ConversationsCompanion(unreadCount: Value(0)));
  }

  /// Increment unread count for a conversation (called on incoming message).
  Future<void> incrementUnread(String peerUuid) async {
    final existing = await (select(conversations)
          ..where((t) => t.peerUuid.equals(peerUuid)))
        .getSingleOrNull();
    if (existing != null) {
      await (update(conversations)..where((t) => t.peerUuid.equals(peerUuid)))
          .write(ConversationsCompanion(
        unreadCount: Value(existing.unreadCount + 1),
      ));
    }
  }

  /// All peer UUIDs that have a conversation (for offline device merging).
  Future<List<String>> knownPeerUuids() async {
    final rows = await select(conversations).get();
    return rows.map((r) => r.peerUuid).toList();
  }

  /// Get peer name from conversations table.
  Future<String?> getPeerName(String peerUuid) async {
    final row = await (select(conversations)
          ..where((t) => t.peerUuid.equals(peerUuid)))
        .getSingleOrNull();
    return row?.peerName;
  }
}

// ── DB connection helper ──────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'wasla_chat.db'));
    return NativeDatabase.createInBackground(file);
  });
}

// ── Riverpod Provider ─────────────────────────────────────────────────────────

final chatDatabaseProvider = Provider<ChatDatabase>((ref) {
  final db = ChatDatabase();
  ref.onDispose(db.close);
  return db;
});
