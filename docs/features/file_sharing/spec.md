# Feature: File Sharing

---

## 🎯 Goal
Send any file type via WebRTC Data Channel with a progress bar and automatic save.

---

## ✅ Prerequisites

- [ ] **Chat complete** — File Sharing uses the same Data Channel
- [ ] Dependencies in `pubspec.yaml`:
  ```yaml
  file_picker: ^8.x.x
  path_provider: ^2.x.x
  permission_handler: ^11.x.x
  ```
- [ ] Permissions:
  - Android: Storage access (scoped storage for Android 11+)

---

## 📝 User Stories

- [ ] As a user, I want to send any file type to another device
- [ ] As a user, I want to see transfer progress
- [ ] As a user, I want received files to be saved automatically
- [ ] As a user, I want to cancel a transfer at any time

---

## 🔧 Coding Checklist

### Step 1 — Data: File Transfer Service
- [ ] Create `lib/features/file_sharing/data/file_transfer_service.dart`
  - Chunk files into 16KB pieces (WebRTC Data Channel limit)
  - Send metadata first: `{"type": "file_start", "name": "...", "size": ..., "chunks": ...}`
  - Send chunks as binary
  - Send `{"type": "file_end"}` at completion
  - Expose `Stream<double>` for progress (0.0 → 1.0)
  - `cancelTransfer()`

### Step 2 — Data: File Storage Service
- [ ] Create `lib/features/file_sharing/data/file_storage_service.dart`
  - `getSavePath()` → platform-specific:
    ```
    Android → Downloads/Wasla/
    Windows → Documents\Wasla\
    Linux   → ~/Wasla/
    ```
  - `saveFile(name, bytes)`

### Step 3 — Presentation
- [ ] `lib/features/file_sharing/presentation/file_card.dart`
  - Glassmorphism card in chat — filename + size + progress
- [ ] Attach button in Chat Input Bar

---

## 🧪 Acceptance Criteria

- [ ] Any file type can be sent
- [ ] Progress bar updates during transfer
- [ ] Files save automatically to the correct folder
- [ ] Transfer can be cancelled at any time

---

## 📦 Required Packages

```yaml
file_picker: ^8.3.7
path_provider: ^2.1.5
permission_handler: ^11.4.0
```
