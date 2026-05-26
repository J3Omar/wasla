# Feature: Chat

---

## 🎯 Goal
Text messaging between two devices via WebRTC Data Channel, stored locally with Drift (SQLite).

---

## ✅ Prerequisites

- [x] **Device Discovery complete** — peer IP available from `Device.localIp`
- [x] **Transport layer** — Using `dart:io` WebSocket (port 8766) instead of WebRTC Data Channel for Phase 1. WebRTC upgrade planned for voice/video feature.
- [x] Dependencies in `pubspec.yaml`:
  ```yaml
  sqlite3: ^2.9.4
  sqlite3_flutter_libs: ^0.5.30
  path: ^1.9.0
  intl: ^0.19.0
  ```

---

## 📝 User Stories

- [ ] As a user, I want to send text messages to another device
- [ ] As a user, I want to see chat history even when the other device is offline
- [ ] As a user, I want to see a delivered indicator

---

## 🔧 Coding Checklist

### Step 1 — Data: SQLite Database
- [x] Create `lib/features/chat/domain/chat_message.dart` — ChatMessage + enums
- [x] Create `lib/features/chat/data/chat_database.dart` — SQLite via `sqlite3` package (no code gen)

### Step 2 — Data: WebSocket Transport
- [x] Create `lib/features/chat/data/ws_chat_service.dart`
  - Runs `HttpServer` on port 8766 for receiving
  - Connects to peer's server for sending
  - Auto-reconnects on disconnect
  - Sends JSON: `{"type": "msg", "content": "...", "ts": epoch_ms}`

### Step 3 — Presentation: State
- [x] Create `lib/features/chat/presentation/chat_notifier.dart`
  - `ChatArgs` (peerId, peerIp, peerName) as family arg
  - Subscribes to DB stream
  - Sends optimistically with status tracking

### Step 4 — Presentation: Chat Screen
- [x] Create `lib/features/chat/presentation/chat_screen.dart`
  - AppBar: avatar, device name, IP (green), call buttons
  - `_SentBubble` — gradient (Cyan→Purple), rounded corners, glow shadow
  - `_ReceivedBubble` — `bgTertiary` dark, left-aligned
  - `_Timestamp` with `_StatusIcon` (sending/sent/delivered/failed)
  - `_DateDivider` between different days
  - `_EmptyConversation` when no messages yet
  - `_InputBar`: attach (+), text field, animated send button

### Step 5 — Wiring
- [x] Updated router: `/chat/:deviceId` now opens `ChatScreen(device: device)`
- [x] Updated `HomeScreen` Chat tile to pass `Device` as extra
- [x] `main.dart` opens `ChatDatabase` at startup

---

## 🧪 Acceptance Criteria

- [x] Messages delivered in under 500ms on LAN
- [x] Chat history persists after closing the app
- [x] Delivered indicator works
- [x] Works only with internet

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
