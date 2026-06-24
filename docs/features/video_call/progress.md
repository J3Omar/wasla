# Progress: P2P Hardware Video Calling

## Status: 🟢 Fully Implemented

## Changelog
| Version | Action | Component | Status |
|---------|--------|-----------|--------|
| V1.0 | Initial WebRTC Video implementation | `call_manager.dart` | ✅ Done |
| V1.0 | PiP Local Video overlay and Camera toggle | `call_screen.dart` | ✅ Done |
| V1.1 | Enforce `60fps` and `1-2.5Mbps` transceiver ceilings | `call_manager.dart` | ✅ Done |
| V1.1 | Re-Signaling Architecture (`Session ID` injection) | `call_manager.dart` / `call_provider.dart` | ✅ Done |
| V1.1 | `_attemptReconnect` fallback sequence | `call_manager.dart` | ✅ Done |

## Technical Debt / Known Issues
- Currently, `addTransceiver` properties effectively bypass dynamic network bandwidth estimation, forcing high-fidelity streams. On extensively saturated networks, this could result in packet loss. A future V2.0 optimization may introduce an adaptive fallback tier if jitter exceeds 500ms over 3 consecutive ICE checks.

## Interoperability Testing
- [x] Windows ↔ Android: Verified (Transceivers correctly force hardware bounds)
- [x] Linux ↔ Android: Verified 
- [x] Android ↔ Android: Verified (UDP Connection Healing successfully restores sessions post-WiFi drop)
