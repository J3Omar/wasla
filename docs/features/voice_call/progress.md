# Progress: Voice Call

## Status: 🟡 In Progress

---

## Changelog

| Date | What | Status |
|------|------|--------|
| 2026-06-05 | Branch `feat/voice-call` created from `dev` | ✅ Done |
| 2026-06-05 | `call_state.dart` — CallState enum + CallSession model | ✅ Done |
| 2026-06-05 | `call_manager.dart` — WebRTC PeerConnection + audio tracks + signaling | ✅ Done |
| 2026-06-05 | `call_provider.dart` — Riverpod notifier + UDP invite listener | ✅ Done |
| 2026-06-05 | `outgoing_call_screen.dart` — pulsing avatar, ringing UI | ✅ Done |
| 2026-06-05 | `incoming_call_screen.dart` — ripple ring, Accept / Decline | ✅ Done |
| 2026-06-05 | `voice_call_screen.dart` — timer, glassmorphism controls pill | ✅ Done |
| 2026-06-05 | `app_router.dart` — `/call/outgoing`, `/call/incoming`, `/call/active` routes | ✅ Done |
| 2026-06-05 | `main_shell.dart` — callProvider wired, incoming call overlay | ✅ Done |
| 2026-06-05 | `home_screen.dart` — Call button on device card wired | ✅ Done |
| 2026-06-05 | `chat_screen.dart` — Call button in AppBar wired | ✅ Done |
| 2026-06-05 | 30s outgoing call timeout → auto-end + "No answer" status text | ✅ Done |
| 2026-06-05 | Incoming call system notification (background) via `ChatNotificationService` | ✅ Done |
| 2026-06-05 | `getBestLocalIpFor()` in UDP invite payload — fixes hotspot signaling IP | ✅ Done |
| 2026-06-05 | Speaker/Earpiece toggle UI — icon + label both reflect current audio output | ✅ Done |

---

## Issues
- Requires `RECORD_AUDIO` permission on Android — already declared via `permission_handler`
- Group calls (>2 devices) not yet implemented — planned for next iteration

---

## Testing Results

- [ ] Android → Android (same WiFi)
- [ ] Android → Android (hotspot)
- [ ] Linux → Android
- [ ] Windows → Android
- [ ] 3 declines → "busy" message
- [ ] Network loss → auto-disconnect
- [ ] Group Call (3 devices) — planned
- [ ] Group Call (4 devices) — planned
