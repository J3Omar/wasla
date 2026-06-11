# Feature Specification: Encrypted LAN Chat

## 🎯 Objective
Enable real-time, zero-latency text messaging between two peers on the same local subnet using WebRTC SCTP Data Channels, with persistent local history via Drift (SQLite).

## 📝 User Stories
- [x] As a user, I need to send and receive text payloads asynchronously.
- [x] As a user, my chat history must persist locally and reload instantly upon app launch.
- [x] As a user, I require visual indicators for message states (Sending, Delivered, Failed).

## 🏗️ Architectural Specifications

### 1. Persistence Layer (`ChatDatabase`)
- **Technology:** Drift (SQLite wrapper).
- **Data Model:** `ChatMessage` encapsulates `id`, `peerId`, `content`, `timestamp`, `isMine`, and `status`.
- **Encryption:** Configured to support SQLCipher for AES-256 at-rest encryption (where applicable).

### 2. Transport Layer (`WebRtcChatService`)
- **Technology:** `flutter_webrtc` Data Channels (`RTCDataChannel`).
- **Topology:** Peer-to-Peer (P2P). Bypasses the WebSocket signaling server post-negotiation.
- **Payload Format:** JSON serialized payloads containing `{"type": "msg", "content": "...", "ts": epoch_ms}`.
- **Legacy Fallback:** Contains an internal `ws_chat_service.dart` fallback on port 8766 for peers unable to establish SCTP connections.

### 3. State Management (`ChatNotifier`)
- **Technology:** Riverpod `AsyncNotifierFamily<ChatArgs>`.
- **Flow:**
  1. Captures UI input.
  2. Optimistically writes to SQLite with `status: sending`.
  3. Dispatches via `WebRtcChatService`.
  4. On ACK, updates SQLite to `status: delivered`.

### 4. UI Layer (`ChatScreen`)
- **Components:**
  - `_SentBubble` & `_ReceivedBubble`: Distinct gradient and alignment behaviors.
  - `_StatusIcon`: Reactive indicator hooked to the Drift DB stream.
  - `_InputBar`: Hardware-accelerated animations for the send button.
- **Routing:** `/chat/:deviceId` injection via `go_router`.

## 🧪 Acceptance Criteria
- [x] WebRTC SCTP payloads execute in `< 10ms` on LAN.
- [x] Drift stream reflects new rows without manual setState.
- [x] App restart preserves the entire conversation history.
