# Feature Specification: P2P File Transfer Protocol

## 🎯 Objective
Enable robust, binary chunked file transfers over WebRTC SCTP Data Channels, bypassing external cloud relays and TCP limitations. Ensure memory-safe transmissions for payloads up to 2GB.

## 🏗️ Architectural Specifications

### 1. Transport Mechanisms
- **Primary:** `WebRtcChatService.sendRawData`.
- **Packet Structure:** 
  - `file_request`: Initial handshake. Contains filename, MIME type, and bytes.
  - `file_chunk`: Binary payload slices (max 64KB per slice to prevent WebRTC buffer overflows).
  - `file_complete`: Verification token post-transmission.

### 2. State & Integrity (`FileTransferService`)
- Implements an `_ActiveTransfer` state machine.
- Maintains in-memory ByteBuilders for incoming chunk reconstruction.
- Writes reconstructed files sequentially to disk to minimize RAM overhead.

### 3. File System Policies
- Validates available OS disk space before accepting `file_request` via `disk_space_plus`.
- Automatically appends integer modifiers (e.g., `_1`) to file basenames upon local storage collisions.
- OS File Paths default to the respective `Downloads/Wasla/` directory natively.

## 🧪 Acceptance Criteria
- [x] Unrestricted file extension support.
- [x] Streamed binary progress calculations update `< 100ms` latency.
- [x] Hardware cancellation dynamically purges `ByteBuilder` from memory to prevent leaks.
- [x] Security: Incoming files mandate explicit user consent via bottom sheet interceptors.
