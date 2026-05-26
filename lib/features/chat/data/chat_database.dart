import 'dart:async';

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
    _db = sqlite3.open(path);
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
        file_size INTEGER
      );
    ''');
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

  /// Fetch all messages for a conversation, ordered oldest → newest.
  List<ChatMessage> getMessages(String peerId) {
    final rows = _db!.select(
      'SELECT * FROM messages WHERE peer_id = ? ORDER BY timestamp ASC',
      [peerId],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Stream that emits the updated message list whenever anything changes.
  Stream<List<ChatMessage>> watchMessages(String peerId) {
    return _controller.stream.map((_) => getMessages(peerId)).distinct();
  }

  ChatMessage _rowToMessage(Row row) {
    return ChatMessage(
      id: row['id'] as int,
      peerId: row['peer_id'] as String,
      content: row['content'] as String,
      isSent: (row['is_sent'] as int) == 1,
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
