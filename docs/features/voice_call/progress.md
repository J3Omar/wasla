# Progress: P2P VoIP Engine

## Status: 🟢 Fully Implemented

## Changelog
| Version | Action | Component | Status |
|---------|--------|-----------|--------|
| V1.0 | Setup `flutter_webrtc` audio constraints | `call_manager.dart` | ✅ Done |
| V1.0 | Local dynamic WebSocket server for Signaling | `call_manager.dart` | ✅ Done |
| V1.0 | Call screens (Incoming, Outgoing, Active) | `features/call/presentation` | ✅ Done |
| V1.1 | 5s Grace Timer and ICE Restart hooks | `call_manager.dart` | ✅ Done |
| V1.1 | 15s absolute Kill Timer | `call_manager.dart` | ✅ Done |
| V1.1 | UDP Session ID injection & Connection Healing | `call_manager.dart` / `call_provider.dart` | ✅ Done |

## Technical Debt / Known Issues
- While the UDP healing mechanism handles TCP/WebSocket failures effectively, some Android devices aggressively sleep the WiFi radio when the screen is locked, leading to intermittent 15-second timer expirations. Exploring `Android WakeLocks` or `ForegroundServices` to hold the WiFi radio open during audio calls is an ongoing investigation.

## Interoperability Testing
- [x] Windows ↔ Android: Verified (Echo cancellation functioning natively on both OS bounds)
- [x] Linux ↔ Android: Verified
- [x] Android ↔ Android: Verified (UDP Healing survives physical WiFi toggles)