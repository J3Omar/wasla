# Progress: Chat

## Status: ✅ Done

---

## Changelog

| Date       | What                                                              | Status       |
|------------|-------------------------------------------------------------------|--------------|
| 2026-05-26 | Created `feat/chat` branch from `dev`                             | ✅ Done      |
| 2026-05-26 | `domain/chat_message.dart` — ChatMessage model + enums            | ✅ Done      |
| 2026-05-26 | `data/chat_database.dart` — SQLite persistence (no codegen)       | ✅ Done      |
| 2026-05-26 | `data/ws_chat_service.dart` — WebSocket server + client (LAN)    | ✅ Done      |
| 2026-05-26 | `presentation/chat_notifier.dart` — Riverpod AsyncNotifier        | ✅ Done      |
| 2026-05-26 | `presentation/chat_screen.dart` — Full UI matching design         | ✅ Done      |
| 2026-05-26 | Router wired — tapping Chat tile opens real ChatScreen             | ✅ Done      |
| 2026-05-26 | Added `sqlite3`, `path`, `intl` to pubspec                        | ✅ Done      |
| 2026-05-26 | DB opened at startup in `main.dart`                               | ✅ Done      |
| -          | End-to-end testing Android ↔ Android, Android ↔ Linux              | ⏳ Pending  |

---

## Issues
- None known yet

---

## Testing Results

- [x] Windows → Android
- [x] Android → Windows
- [x] Android → Android
- [x] Linux → Android
