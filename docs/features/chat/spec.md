# Feature: Chat

---

## 🎯 Goal
Text messaging between two devices via WebRTC Data Channel, stored locally with Drift (SQLite).

---

## ✅ Prerequisites

- [ ] **Device Discovery complete** — need the peer's IP to establish a connection
- [ ] **WebRTC Signaling working** — Data Channel requires a peer connection first
- [ ] Dependencies in `pubspec.yaml`:
  ```yaml
  flutter_webrtc: ^0.x.x
  drift: ^2.x.x
  sqlite3_flutter_libs: ^0.5.x
  drift_dev: ^2.x.x        # dev dependency
  build_runner: ^2.x.x      # dev dependency
  ```

> **Note:** Chat uses the same WebRTC connection that Voice/Video Call will use — build the signaling layer once for both.

---

## 📝 User Stories

- [ ] As a user, I want to send text messages to another device
- [ ] As a user, I want to see chat history even when the other device is offline
- [ ] As a user, I want to see a delivered indicator

---

## 🔧 Coding Checklist

### Step 1 — Data: Drift Database
- [ ] Create `lib/features/chat/data/chat_database.dart`
  ```dart
  class Messages extends Table {
    IntColumn get id => integer().autoIncrement()();
    TextColumn get conversationId => text()();  // peer UUID
    TextColumn get content => text()();
    BoolColumn get isSent => boolean()();
    DateTimeColumn get timestamp => dateTime()();
    IntColumn get status => intEnum<MessageStatus>()();
    IntColumn get type => intEnum<MessageType>()();
    TextColumn get fileName => text().nullable()();
    IntColumn get fileSize => integer().nullable()();
  }
  ```
- [ ] Run `dart run build_runner build`

### Step 2 — Data: Chat Repository
- [ ] Create `lib/features/chat/data/chat_repository.dart`
  - `saveMessage(Message)` → Drift
  - `watchMessages(conversationId)` → `Stream<List<Message>>`
  - `updateStatus(id, status)`

### Step 3 — Data: Data Channel Service
- [ ] Create `lib/features/chat/data/data_channel_service.dart`
  - Create WebRTC Data Channel
  - Send JSON: `{"type": "msg", "content": "...", "ts": "..."}`
  - Receive + parse + save to Drift

### Step 4 — Presentation: Chat Screen
- [ ] Create `lib/features/chat/presentation/chat_screen.dart`
  - `ListView` with messages from Drift
  - `MessageBubble` — received (dark bg) vs sent (gradient)
  - Input bar + Send button
  - Call buttons in AppBar

---

## 🧪 Acceptance Criteria

- [ ] Messages delivered in under 500ms on LAN
- [ ] Chat history persists after closing the app
- [ ] Delivered indicator works
- [ ] Works without internet

---

## 📦 Required Packages

```yaml
flutter_webrtc: ^0.14.1
drift: ^2.25.0
sqlite3_flutter_libs: ^0.5.30

dev_dependencies:
  drift_dev: ^2.25.0
  build_runner: ^2.4.15
```
