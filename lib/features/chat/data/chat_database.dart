import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/chat_message.dart';

/// Local SQLite persistence for chat messages using the sqlite3 package.
/// No code generation required.
class ChatDatabase {
  ChatDatabase._();
  static final ChatDatabase instance = ChatDatabase._();

  Database? _db;
  final _controller = StreamController<void>.broadcast();

  /// Open (or create) the database. Call once at app start.
  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'wasla_chat.db');
    try {
      _db = sqlite3.open(path);
      // Test if it's our schema by checking for peer_id
      // If it's an old drift db, this will throw and trigger the recreation
      try {
        _db!.execute('SELECT peer_id FROM messages LIMIT 1;');
      } catch (e) {
        // If the table exists but has no peer_id, it's the old schema
        throw Exception('Schema mismatch');
      }
    } catch (e) {
      // If the database is corrupted or from an incompatible drift version, delete and recreate
      try {
        File(path).deleteSync();
      } catch (_) {}
      _db = sqlite3.open(path);
    }
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_id   TEXT    NOT NULL,
        content   TEXT    NOT NULL,
        is_sent   INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        status    INTEGER NOT NULL DEFAULT 0,
        type      INTEGER NOT NULL DEFAULT 0,
        file_name TEXT,
        file_size INTEGER,
        is_read   INTEGER NOT NULL DEFAULT 0
      );
    ''');
    try {
      _db!.execute('ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        uuid         TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        last_ip      TEXT
      );
    ''');
    try {
      _db!.execute('ALTER TABLE peers ADD COLUMN last_ip TEXT;');
    } catch (_) {}
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_peer ON messages (peer_id, timestamp);',
    );
  }

  void _notifyListeners() => _controller.add(null);

  /// Insert a message and return it with the generated id.
  ChatMessage insert(ChatMessage msg) {
    _db!.execute(
      '''INSERT INTO messages
         (peer_id, content, is_sent, timestamp, status, type, file_name, file_size)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        msg.peerId,
        msg.content,
        msg.isSent ? 1 : 0,
        msg.timestamp.millisecondsSinceEpoch,
        msg.status.index,
        msg.type.index,
        msg.fileName,
        msg.fileSize,
      ],
    );
    final id = _db!.lastInsertRowId;
    _notifyListeners();
    return msg.copyWith(id: id);
  }

  /// Update message status (e.g. sending → sent → delivered).
  void updateStatus(int id, MessageStatus status) {
    _db!.execute(
      'UPDATE messages SET status = ? WHERE id = ?',
      [status.index, id],
    );
    _notifyListeners();
  }

  /// Update message status by timestamp (used for network acks).
  /// Only upgrades status (sent→delivered→read), never downgrades.
  void updateStatusByTimestamp(int timestampMs, MessageStatus status) {
    _db!.execute(
      'UPDATE messages SET status = ? WHERE timestamp = ? AND is_sent = 1 AND status < ?',
      [status.index, timestampMs, status.index],
    );
    _notifyListeners();
  }

  /// Fetch all messages for a conversation, ordered oldest → newest.
  List<ChatMessage> getMessages(String peerId) {
    final rows = _db!.select(
      'SELECT * FROM messages WHERE peer_id = ? ORDER BY timestamp ASC',
      [peerId],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Mark all messages from a peer as read.
  void markAllRead(String peerId) {
    _db!.execute(
      'UPDATE messages SET is_read = 1 WHERE peer_id = ? AND is_sent = 0',
      [peerId],
    );
    _notifyListeners();
  }

  /// Count unread (received, not-read) messages per peer.
  Map<String, int> getUnreadCounts() {
    if (_db == null) return {};
    final rows = _db!.select(
      'SELECT peer_id, COUNT(*) as cnt FROM messages WHERE is_sent = 0 AND is_read = 0 GROUP BY peer_id',
    );
    return {for (final r in rows) r['peer_id'] as String: r['cnt'] as int};
  }

  /// Total unread across all peers (for nav-bar badge).
  int getTotalUnread() {
    if (_db == null) return 0;
    final rows = _db!.select(
      'SELECT COUNT(*) as cnt FROM messages WHERE is_sent = 0 AND is_read = 0',
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Fetch all unsent or failed messages
  List<ChatMessage> getUnsentMessages() {
    if (_db == null) return [];
    final rows = _db!.select(
      'SELECT * FROM messages WHERE status = ? OR status = ? ORDER BY timestamp ASC',
      [MessageStatus.sending.index, MessageStatus.failed.index],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Stream that emits the updated message list whenever anything changes.
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    return _controller.stream.map((_) => getMessages(peerId)).distinct();
  }

  /// Fetch the latest message for each peer to display in the Chats list.
  List<ChatMessage> getRecentConversations() {
    if (_db == null) return [];
    final rows = _db!.select('''
      SELECT m.* FROM messages m
      INNER JOIN (
        SELECT peer_id, MAX(timestamp) as max_ts
        FROM messages
        GROUP BY peer_id
      ) latest ON m.peer_id = latest.peer_id AND m.timestamp = latest.max_ts
      ORDER BY m.timestamp DESC
    ''');
    return rows.map(_rowToMessage).toList();
  }

  /// Stream of recent conversations for the UI.
  Stream<List<ChatMessage>> watchRecentConversations() async* {
    yield getRecentConversations();
    await for (final _ in _controller.stream) {
      yield getRecentConversations();
    }
  }

  /// Upsert a peer's display name and optionally their IP
  void upsertPeer(String uuid, String displayName, [String? ip]) {
    if (ip != null) {
      _db!.execute(
        'INSERT OR REPLACE INTO peers (uuid, display_name, last_ip) VALUES (?, ?, ?)',
        [uuid, displayName, ip],
      );
    } else {
      _db!.execute(
        'INSERT OR IGNORE INTO peers (uuid, display_name) VALUES (?, ?)',
        [uuid, displayName],
      );
      _db!.execute(
        'UPDATE peers SET display_name = ? WHERE uuid = ?',
        [displayName, uuid],
      );
    }
    _notifyListeners();
  }

  /// Get a peer's display name if saved
  String? getPeerName(String uuid) {
    final rows = _db!.select('SELECT display_name FROM peers WHERE uuid = ? LIMIT 1', [uuid]);
    if (rows.isEmpty) return null;
    return rows.first['display_name'] as String?;
  }

  /// Get a peer's last known IP
  String? getPeerIp(String uuid) {
    final rows = _db!.select('SELECT last_ip FROM peers WHERE uuid = ? LIMIT 1', [uuid]);
    if (rows.isEmpty) return null;
    return rows.first['last_ip'] as String?;
  }

  /// Delete specific messages
  void deleteMessages(List<int> ids) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    _db!.execute('DELETE FROM messages WHERE id IN ($placeholders)', ids);
    _notifyListeners();
  }

  /// Delete all messages for a specific peer
  void deleteChat(String uuid) {
    _db!.execute('DELETE FROM messages WHERE peer_id = ?', [uuid]);
    _notifyListeners();
  }

  ChatMessage _rowToMessage(Row row) {
    return ChatMessage(
      id: row['id'] as int,
      peerId: row['peer_id'] as String,
      content: row['content'] as String,
      isSent: (row['is_sent'] as int) == 1,
      isRead: (row['is_read'] as int? ?? 0) == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      status: MessageStatus.values[row['status'] as int],
      type: MessageType.values[row['type'] as int],
      fileName: row['file_name'] as String?,
      fileSize: row['file_size'] as int?,
    );
  }

  void dispose() {
    _db?.dispose();
    _controller.close();
    _db = null;
  }
}
