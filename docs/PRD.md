# Product Requirements Document (PRD) — Wasla

> Release Version: V1.0 | Updated: June 2026

---

## 1. Executive Summary

| | |
|---|---|
| **Product Name** | Wasla |
| **Category** | Decentralized LAN Communication Platform |
| **Release** | V1.0 |
| **Supported Platforms** | Android · Windows · Linux |

### Problem Statement
Internet bandwidth in many regions (e.g., Egypt) is strictly metered. Standard communication apps (WhatsApp, Telegram) route local media through external cloud servers, consuming valuable bandwidth even when both peers reside on the same physical router.

### Solution
A comprehensive, serverless communication suite (Audio, Video, Chat, File Transfer, and Screen Sharing) designed to operate **100% offline** over a Local Area Network (LAN). 

---

## 2. Core Architectural Principles

| Principle | Description |
|-----------|-------------|
| **100% Offline** | Zero cloud relays (No STUN/TURN). Zero external DNS. Completely LAN-bound. |
| **Zero Setup** | No user registration, no passwords. Peers are identified via ephemeral display names and hardware UUIDs. |
| **Private by Design** | All cryptographic keys and databases reside strictly on local hardware. |
| **Cross-Platform Parity** | A unified Flutter codebase providing identical logic across Android, Windows, and Linux. |

---

## 3. Core Feature Specifications — V1.0

### F1 — Cryptographic Onboarding
**Description:** First-launch bootstrap process.
**Acceptance Criteria:**
- [x] Displays only on the initial application launch.
- [x] Enforces Display Name limits (2-30 characters).
- [x] Automatically generates a cryptographic UUID V4.
- [x] Persists the identity within OS-level Secure Storage (`flutter_secure_storage`).

### F2 — Decentralized Device Discovery
**Description:** Autonomous node discovery on the active subnet.
**Technical Strategy:** mDNS (Multicast DNS) coupled with a UDP Broadcast fallback mechanism.
**Acceptance Criteria:**
- [x] Network peers populate within 5 seconds of launch.
- [x] Offline peers are pruned from the UI within 10 seconds (2 missed heartbeats).
- [x] Granular status broadcasting (`Available`, `In Call`, `Busy`).

### F3 — Encrypted LAN Chat
**Description:** Real-time text messaging.
**Technical Strategy:** WebRTC SCTP Data Channels persisted locally via Isar/Drift.
**Acceptance Criteria:**
- [x] Sub-500ms message delivery latency.
- [x] Local SQLite databases encrypted via SQLCipher.
- [x] Guaranteed delivery queues (pending messages dispatch upon peer reconnection).

### F4 — Resilient Voice Calls
**Description:** High-fidelity P2P VoIP.
**Technical Strategy:** WebRTC Audio Tracks over dynamic WebSocket signaling.
**Acceptance Criteria:**
- [x] Call initiation completes in `< 3 seconds`.
- [x] **UDP Session ID Healing:** If the TCP/WebSocket layer drops (e.g., WiFi network toggle), the system automatically triggers a 15-second kill timer. Before expiration, a background UDP `_attemptReconnect` payload containing the active `Session ID` is dispatched to transparently heal the connection without dropping the call.

### F5 — Aggressive Hardware Video Calls
**Description:** Low-latency P2P Video streaming.
**Technical Strategy:** Hardware-accelerated VP8/H264 encoding.
**Acceptance Criteria:**
- [x] **Strict Framerate Enforcement:** The engine aggressively forces a `60fps` capture rate via `getUserMedia`.
- [x] **Bitrate Floors/Ceilings:** WebRTC `addTransceiver` enforces hardware encoding limits of `1-2.5 Mbps` to prevent automatic network degradation.
- [x] Seamless camera toggling (`facingMode` swapping) without session renegotiation failures.

### F6 — Cross-Platform Screen Sharing
**Description:** Bidirectional screen and system audio casting.
**Acceptance Criteria:**
- [x] Interoperable casting across Android, Windows, and Linux.
- [x] **Linux Constraint Fallbacks:** The engine gracefully captures `{'video': true, 'audio': false}` if X11/Wayland display servers reject native audio loopback constraints.
- [x] UI/UX automatically adjusts `RTCVideoView` bounds (`object-fit: contain` vs `cover`) based on landscape/desktop orientation.

### F7 — Chunked File Sharing
**Description:** Uncapped peer-to-peer file transfer.
**Acceptance Criteria:**
- [x] Transport over WebRTC Data Channels (bypassing TCP limits).
- [x] Real-time binary progress bars.
- [x] Automatic persistence to `Downloads/Wasla/` via OS Native File Pickers.

---

## 4. Non-Functional Requirements (NFRs)

| Requirement | Threshold / Target |
|-------------|--------------------|
| **Android OS** | API 21 (Android 5.0)+ |
| **Linux OS** | GTK 3.0+ Dependencies (`gstreamer1.0-pipewire`) |
| **Windows OS** | Windows 10+ (64-bit) |
| **Network Latency** | `< 150ms` (Subnet constrained) |
| **Data Telemetry** | 0 Bytes (Strictly prohibited) |

---

## 5. UI/UX Responsive Scaling
The application uses responsive breakpoints to ensure the WebRTC controls and peer video streams render flawlessly:
- `SingleChildScrollView` accompanied by `math.max` height bounding constraints prevents render overflow on Mobile Landscape mode.
- The `_ControlsPill` dynamically scales padding (`isDesktop ? 100 : 12`) to optimize widescreen monitor real estate.
