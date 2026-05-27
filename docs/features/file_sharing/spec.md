# Feature: File Sharing

---

## 🎯 Goal
Send any file type via WebRTC Data Channel with a progress bar, automatic save, and disk space checks without using external servers.

---

## ✅ Prerequisites

- [x] **Chat complete** — File Sharing uses the same Data Channel (`WebRtcChatService`)
- [x] Dependencies in `pubspec.yaml`:
  ```yaml
  file_picker: ^8.3.7
  path_provider: ^2.1.5
  disk_space_plus: ^0.0.3
  mime: ^1.0.5
  open_file: ^3.3.2
  ```

---

## 📝 User Stories

- [x] As a user, I want to send any file type to another device
- [x] As a user, I want to see transfer progress
- [x] As a user, I want received files to be saved automatically
- [x] As a user, I want to cancel a transfer at any time
- [x] As a user, I want to accept or decline incoming files
- [x] As a user, I want to customize my download folder in Settings

---

## 🔧 Implemented Architecture

### Step 1 — Data: Storage & DB
- `lib/features/file_sharing/data/file_storage_service.dart`:
  - `getSavePath()` / `setSavePath()`
  - Disk space checks via `disk_space_plus`
  - Auto-renaming existing files to prevent overwriting
- `lib/features/chat/data/chat_database.dart`:
  - `ChatMessage` extended to support `FileTransfer` state (status, progress, local path)

### Step 2 — Data: Transfer Protocol
- `lib/features/file_sharing/data/file_transfer_service.dart` via `WebRtcChatService.sendRawData`:
  - **Protocol JSONs**: `file_request`, `file_response`, `file_chunk_start`, `file_chunk_end`, `file_complete`, `file_cancel`
  - Small files (<16MB): Sent as a single binary packet.
  - Large files (>16MB): Chunked into 64KB pieces for stability.
  - `_ActiveTransfer` class to track in-memory state.

### Step 3 — Presentation
- `FileMessageBubble`: Glassmorphism bubble for chat history showing Name, Size, Progress, and Status.
- `FileRequestSheet`: Bottom sheet allowing users to Accept/Decline incoming transfers.
- `FilePreviewCard`: Inline preview in `chat_screen.dart`'s `_InputBar` before sending.

---

## 🧪 Acceptance Criteria

- [x] Any file type can be sent
- [x] Progress bar updates during transfer
- [x] Files save automatically to the correct folder
- [x] Transfer can be cancelled at any time
- [x] Prompts user for approval when receiving files
