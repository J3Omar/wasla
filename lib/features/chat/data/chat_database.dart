import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/chat_message.dart';
import '../../file_sharing/domain/file_transfer_state.dart';

const _kPageSize = 30;

/// Local SQLite persistence for chat messages using the sqlite3 package.
/// No code generation required.
class ChatDatabase {
  ChatDatabase._();
  static final ChatDatabase instance = ChatDatabase._();

  Database? _db;
  final _controller = StreamController<void>.broadcast();

  bool get isOpen => _db != null;

  /// Open (or create) the database. Safe to call multiple times.
  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'wasla_chat.db');
    try {
      _db = sqlite3.open(path);
      // Validate schema exists with expected columns
      _db!.execute('SELECT peer_id FROM messages LIMIT 1;');
    } catch (e) {
      // If the table exists but with wrong schema, delete and recreate
      try {
        File(path).deleteSync();
      } catch (_) {}
      _db = sqlite3.open(path);
    }

    // ── Messages table ──────────────────────────────────────────────────────
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        message_uuid TEXT    NOT NULL DEFAULT '',
        peer_id      TEXT    NOT NULL,
        content      TEXT    NOT NULL,
        is_sent      INTEGER NOT NULL DEFAULT 0,
        timestamp    INTEGER NOT NULL,
        status       INTEGER NOT NULL DEFAULT 0,
        type         INTEGER NOT NULL DEFAULT 0,
        file_name         TEXT,
        file_size         INTEGER,
        is_read           INTEGER NOT NULL DEFAULT 0,
        transfer_id       TEXT,
        mime_type         TEXT,
        local_file_path   TEXT,
        transfer_status   TEXT,
        transfer_progress REAL
      );
    ''');

    // Additive migrations — safe to run repeatedly
    _runSafe(
      'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0;',
    );
    _runSafe(
      'ALTER TABLE messages ADD COLUMN message_uuid TEXT NOT NULL DEFAULT \'\';',
    );
    _runSafe('ALTER TABLE messages ADD COLUMN transfer_id TEXT;');
    _runSafe('ALTER TABLE messages ADD COLUMN mime_type TEXT;');
    _runSafe('ALTER TABLE messages ADD COLUMN local_file_path TEXT;');
    _runSafe('ALTER TABLE messages ADD COLUMN transfer_status TEXT;');
    _runSafe('ALTER TABLE messages ADD COLUMN transfer_progress REAL;');

    // ── Peers table ─────────────────────────────────────────────────────────
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        uuid         TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        last_ip      TEXT
      );
    ''');
    _runSafe('ALTER TABLE peers ADD COLUMN last_ip TEXT;');

    // ── Indexes ─────────────────────────────────────────────────────────────
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_peer_ts ON messages (peer_id, timestamp);',
    );
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_uuid ON messages (message_uuid);',
    );
  }

  void _runSafe(String sql) {
    try {
      _db!.execute(sql);
    } catch (_) {}
  }

  void _notifyListeners() => _controller.add(null);

  // ── INSERT ────────────────────────────────────────────────────────────────

  /// Insert a message and return it with the generated id.
  ChatMessage insert(ChatMessage msg) {
    _db!.execute(
      '''INSERT INTO messages
         (message_uuid, peer_id, content, is_sent, timestamp, status, type, file_name, file_size, transfer_id, mime_type, local_file_path, transfer_status, transfer_progress)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        msg.messageUuid,
        msg.peerId,
        msg.content,
        msg.isSent ? 1 : 0,
        msg.timestamp.millisecondsSinceEpoch,
        msg.status.index,
        msg.type.index,
        msg.fileName,
        msg.fileSize,
        msg.fileTransfer?.transferId,
        msg.fileTransfer?.mimeType,
        msg.fileTransfer?.localFilePath,
        msg.fileTransfer?.status.name,
        msg.fileTransfer?.progress,
      ],
    );
    final id = _db!.lastInsertRowId;
    _notifyListeners();
    return msg.copyWith(id: id);
  }

  // ── STATUS UPDATES ────────────────────────────────────────────────────────

  /// Update message status by DB row id.
  void updateStatus(int id, MessageStatus status) {
    _db!.execute('UPDATE messages SET status = ? WHERE id = ? AND status < ?', [
      status.index,
      id,
      status.index,
    ]);
    _notifyListeners();
  }

  /// Update message status by UUID (preferred — survives restarts).
  /// Only upgrades status (queued→sent→delivered→read), never downgrades.
  void updateStatusByUuid(String uuid, MessageStatus status) {
    if (uuid.isEmpty) return;
    _db!.execute(
      'UPDATE messages SET status = ? WHERE message_uuid = ? AND is_sent = 1 AND status < ?',
      [status.index, uuid, status.index],
    );
    _notifyListeners();
  }

  /// Updates the file transfer status, progress, and optionally local file path for a message.
  void updateFileTransfer(String uuid, {
    String? status,
    double? progress,
    String? localFilePath,
  }) {
    final Map<String, dynamic> updates = {};
    if (status != null) updates['transfer_status'] = status;
    if (progress != null) updates['transfer_progress'] = progress;
    if (localFilePath != null) updates['local_file_path'] = localFilePath;

    if (updates.isEmpty) return;

    final setClause = updates.keys.map((k) => '$k = ?').join(', ');
    final args = [...updates.values, uuid];

    _db!.execute(
      'UPDATE messages SET $setClause WHERE message_uuid = ?',
      args,
    );
    _notifyListeners();
  }

  /// Get message by transfer ID
  ChatMessage? getMessageByTransferId(String transferId) {
    final rs = _db!.select('SELECT * FROM messages WHERE transfer_id = ? LIMIT 1', [transferId]);
    if (rs.isEmpty) return null;
    return _rowToMessage(rs.first);
  }

  /// Update message status for all sent messages up to this timestamp.
  /// Used by ack_read_all to mark everything the peer has seen.
  /// Only upgrades status, never downgrades.
  void updateStatusByTimestamp(int timestampMs, MessageStatus status) {
    _db!.execute(
      'UPDATE messages SET status = ? WHERE timestamp <= ? AND is_sent = 1 AND status < ?',
      [status.index, timestampMs, status.index],
    );
    _notifyListeners();
  }

  // ── QUERIES ───────────────────────────────────────────────────────────────

  /// Fetch all messages for a conversation (oldest → newest). Use for small chats only.
  List<ChatMessage> getMessages(String peerId) {
    final rows = _db!.select(
      'SELECT * FROM messages WHERE peer_id = ? ORDER BY timestamp ASC',
      [peerId],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Paginated fetch — newest first (offset 0 = latest 30).
  /// Call with offset=0 initially, then offset=30, 60, etc.
  List<ChatMessage> getMessagesPaged(
    String peerId, {
    int offset = 0,
    int limit = _kPageSize,
  }) {
    final rows = _db!.select(
      'SELECT * FROM messages WHERE peer_id = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?',
      [peerId, limit, offset],
    );
    // Return in chronological order for the UI
    return rows.map(_rowToMessage).toList().reversed.toList();
  }

  /// Count total messages for a peer.
  int countMessages(String peerId) {
    final rows = _db!.select(
      'SELECT COUNT(*) as cnt FROM messages WHERE peer_id = ?',
      [peerId],
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Check if a message with this UUID already exists (deduplication).
  bool hasMessage(String uuid) {
    if (uuid.isEmpty) return false;
    final rows = _db!.select(
      'SELECT id FROM messages WHERE message_uuid = ? LIMIT 1',
      [uuid],
    );
    return rows.isNotEmpty;
  }

  // ── READ TRACKING ─────────────────────────────────────────────────────────

  /// Mark all received messages from a peer as read.
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

  // ── OFFLINE QUEUE ─────────────────────────────────────────────────────────

  /// Fetch all queued messages that need to be (re)sent.
  List<ChatMessage> getUnsentMessages() {
    if (_db == null) return [];
    final rows = _db!.select(
      'SELECT * FROM messages WHERE status = ? ORDER BY timestamp ASC',
      [MessageStatus.queued.index],
    );
    return rows.map(_rowToMessage).toList();
  }

  // ── STREAMS ───────────────────────────────────────────────────────────────

  /// Stream that emits the updated message list whenever anything changes.
  /// Used for real-time UI updates.
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    int hashList(List<ChatMessage> msgs) {
      int h = msgs.length;
      for (final m in msgs) {
        h = h * 31 + m.id;
        h = h * 31 + m.status.index;
        if (m.fileTransfer != null) {
          h = h * 31 + m.fileTransfer!.status.index;
        }
      }
      return h;
    }

    int? lastHash;
    return _controller.stream
        .map((_) {
          final msgs = getMessages(peerId);
          final h = hashList(msgs);
          if (h == lastHash) return <ChatMessage>[]; // no meaningful change
          lastHash = h;
          return msgs;
        })
        .where((msgs) => msgs.isNotEmpty);
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

  /// Stream of recent conversations for the Chats list screen.
  Stream<List<ChatMessage>> watchRecentConversations() async* {
    yield getRecentConversations();
    await for (final _ in _controller.stream) {
      yield getRecentConversations();
    }
  }

  // ── PEERS ─────────────────────────────────────────────────────────────────

  /// Upsert a peer's display name and optionally their IP
  void upsertPeer(String uuid, String displayName, [String? ip]) {
    if (ip != null && ip.isNotEmpty) {
      _db!.execute(
        'INSERT OR REPLACE INTO peers (uuid, display_name, last_ip) VALUES (?, ?, ?)',
        [uuid, displayName, ip],
      );
    } else {
      _db!.execute(
        'INSERT OR IGNORE INTO peers (uuid, display_name) VALUES (?, ?)',
        [uuid, displayName],
      );
      _db!.execute('UPDATE peers SET display_name = ? WHERE uuid = ?', [
        displayName,
        uuid,
      ]);
    }
    // Don't notify listeners for peer upserts — avoids unnecessary rebuilds
  }

  /// Get a peer's display name if saved
  String? getPeerName(String uuid) {
    if (_db == null) return null;
    final rows = _db!.select(
      'SELECT display_name FROM peers WHERE uuid = ? LIMIT 1',
      [uuid],
    );
    if (rows.isEmpty) return null;
    return rows.first['display_name'] as String?;
  }

  /// Get a peer's last known IP
  String? getPeerIp(String uuid) {
    if (_db == null) return null;
    final rows = _db!.select(
      'SELECT last_ip FROM peers WHERE uuid = ? LIMIT 1',
      [uuid],
    );
    if (rows.isEmpty) return null;
    return rows.first['last_ip'] as String?;
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  /// Delete specific messages by DB row id.
  void deleteMessages(List<int> ids) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    _db!.execute('DELETE FROM messages WHERE id IN ($placeholders)', ids);
    _notifyListeners();
  }

  /// Delete all messages for a specific peer.
  void deleteChat(String uuid) {
    _db!.execute('DELETE FROM messages WHERE peer_id = ?', [uuid]);
    _notifyListeners();
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  ChatMessage _rowToMessage(Row row) {
    final transferId = row['transfer_id'] as String?;
    FileTransfer? fileTransfer;
    
    if (transferId != null) {
      fileTransfer = FileTransfer(
        transferId: transferId,
        peerId: row['peer_id'] as String,
        fileName: row['file_name'] as String? ?? 'unknown',
        fileSize: row['file_size'] as int? ?? 0,
        mimeType: row['mime_type'] as String? ?? 'application/octet-stream',
        localFilePath: row['local_file_path'] as String?,
        status: FileTransfer.statusFromString(row['transfer_status'] as String? ?? 'failed'),
        progress: row['transfer_progress'] as double? ?? 0.0,
      );
    }

    return ChatMessage(
      id: row['id'] as int,
      messageUuid: row['message_uuid'] as String? ?? '',
      peerId: row['peer_id'] as String,
      content: row['content'] as String,
      isSent: (row['is_sent'] as int) == 1,
      isRead: (row['is_read'] as int? ?? 0) == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      status: MessageStatus.values[row['status'] as int],
      type: MessageType.values[row['type'] as int],
      fileName: row['file_name'] as String?,
      fileSize: row['file_size'] as int?,
      fileTransfer: fileTransfer,
    );
  }

  void dispose() {
    _db?.dispose();
    _controller.close();
    _db = null;
  }
}
