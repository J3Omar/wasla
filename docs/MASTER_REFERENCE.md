# MASTER REFERENCE DOCUMENT — Wasla

> Last Updated: June 2026 | Status: 🟢 Phase 2 — Implementation & Polish

---

## 📌 Project Philosophy

**Wasla** is a highly optimized, fully decentralized Local Area Network (LAN) communication platform built with Flutter.
**Primary Objective:** Deliver zero-latency Voice, Video, Screen Sharing, File Transfer, and Chat capabilities entirely offline, circumventing metered internet connections and external cloud servers.

---

## 💻 Target Environments

| Device Type | Operating System | Minimum OS Version |
|-------------|------------------|--------------------|
| Laptop/Desktop | Windows (64-bit) | Windows 10 |
| Laptop/Desktop | Linux | Any distribution supporting GTK 3.0+ |
| Mobile/Tablet | Android | Android 5.0 (API 21) |

> *Note: iOS/macOS compilation is theoretically supported by the codebase but falls outside the V1.0 official scope.*

---

## 🧱 Technical Stack

| Layer | Technology | Justification |
|-------|------------|---------------|
| **UI & Business Logic** | Flutter / Dart | Single codebase compilation across Android, Windows, and Linux. |
| **Media Transport** | `flutter_webrtc` | Industry-standard WebRTC API; provides hardware-accelerated VP8/H264 encoding and DTLS-SRTP encryption natively. |
| **Signaling** | Ephemeral Local WebSockets | Eliminates reliance on external cloud servers (e.g., Firebase, Supabase). |
| **Device Discovery** | `multicast_dns` & UDP Broadcast | Emits heartbeat payloads (`uuid`, `name`, `ip`) dynamically across the active subnet. |
| **State Management** | Riverpod | Predictable, reactive dependency injection. |
| **Persistence** | Drift (SQLite) | High-performance local SQL datastore for Chat histories, encrypted at rest via SQLCipher. |
| **Identity & Security** | `flutter_secure_storage` | Hardware-backed keystores for persisting user UUIDs and AES encryption keys. |

---

## 📱 Application Screens

| # | Screen | Description |
|---|--------|-------------|
| 1 | **Splash Screen** | App initialization and permissions check. |
| 2 | **Onboarding Screen** | First-run setup: Captures Display Name and generates UUID. |
| 3 | **Home Screen (Discovery)** | Dynamic dashboard displaying all active peers on the LAN. |
| 4 | **Chat Screen** | P2P text interface with SQLite history synchronization. |
| 5 | **Outgoing Call Screen** | Connects to peer and awaits SDP Answer. |
| 6 | **Incoming Call Screen** | Triggers upon UDP `call_invite`. Accepts/Declines calls. |
| 7 | **Call Screen (Voice/Video)** | Unified media interface featuring responsive scaling, hardware acceleration, and seamless `facingMode` toggling. |
| 8 | **Screen Share Overlay** | Floating PIP overlay managing cross-platform bidirectional screen casting. |
| 9 | **Settings Screen** | Profile management and network diagnostics. |

---

## 🎛️ Critical Architectural Behaviors

### Device Discovery Engine
- **Active State Required:** The app must be active (or running a valid Android foreground service) to broadcast presence.
- **Subnet Bound:** Discovery operates strictly within the `255.255.255.0` (or local) subnet boundary. 

### Call State Machine
- **Glare Protection:** Simultaneous incoming/outgoing calls instantly trigger a gracefully handled `Call Rejected` loop.
- **Declination Threshold:** 3 consecutive call rejections from a peer enforce an automatic "Busy" status block.

### Active Media Constraints (WebRTC)
- **Aggressive 60 FPS:** Forced via `getUserMedia` `frameRate: {'ideal': 60, 'max': 60}`.
- **Bitrate Enforcement:** WebRTC `addTransceiver` locks limits between `1 Mbps` and `2.5 Mbps` to prevent quality degradation.
- **Linux Fallbacks:** Screen sharing captures gracefully default to `{'video': true, 'audio': false}` if X11/Wayland lack loopback capabilities.
- **UDP Healing:** 15-second timer invokes `_attemptReconnect` via UDP if the WebSocket signaling pipe shatters. Re-injects the existing `Session ID` to avoid Ghost Calls.

### File Storage Policies
- Android: `/storage/emulated/0/Wasla/`
- Windows: `C:\Users\[User]\Documents\Wasla\`
- Linux: `~/Wasla/`

---

## 🗂️ Unified Directory Structure

```text
lib/
├── core/
│   ├── config/              ← Environment, ports, constants
│   ├── theme/               ← System tokens, colors, typography
│   ├── router/              ← go_router declarations
│   └── utils/               ← Loggers, formatters
└── features/
    ├── onboarding/          ← Cryptographic identity generation
    ├── discovery/           ← mDNS & UDP broadcast engines
    ├── chat/                ← SQLite storage + Data Channels
    ├── call/                ← Unified Media (Audio/Video/Signaling)
    ├── file_sharing/        ← Chunked binary TCP/SCTP transfers
    └── screen_share/        ← Native OS capture APIs
```

---

## 📋 Standardized Documentation Templates

### `spec.md` (Feature Specification)
```markdown
# Feature: [Feature Name]

## Objective
[Brief architectural goal]

## Technical Specifications
- Transport: [WebRTC / UDP / TCP]
- Storage: [Drift / Secure Storage]

## State Machine / Flow
1. ...
2. ...

## Acceptance Criteria
- [ ] ...
```

### `progress.md` (Feature Tracking)
```markdown
# Progress: [Feature Name]

## Status: 🟢 Implemented

## Subsystems
- [x] Logic layer
- [x] UI/UX
- [x] Hardware Fallbacks

## Known Issues / Technical Debt
- None
```
