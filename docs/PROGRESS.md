# 📊 PROGRESS & TRACKING — Wasla

---

## Overview

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Architecture & Design Systems | 🟢 Completed |
| Phase 1 | P2P Networking & Discovery Setup | 🟢 Completed |
| Phase 2 | WebRTC Engine & Core Features | 🟢 Completed |
| Phase 3 | Hardening, Refactoring & Bug Fixes | 🟡 In Progress |
| Phase 4 | Native Hardware Audio Integrations | ⬜ Pending |

---

## 🟢 Phase 0 — Design & Architecture

### Application Interfaces

| # | Screen | Status | Architecture Notes |
|---|--------|--------|--------------------|
| 1 | Splash Screen | 🟢 Implemented | Handles async storage reads. |
| 2 | Home Screen (Discovery) | 🟢 Implemented | `ListView` with animated offline pruning. |
| 3 | Chat Screen | 🟢 Implemented | Real-time SCTP synced with Drift. |
| 4 | Call Screen (Voice/Video) | 🟢 Implemented | Unified responsive interface (Mobile/Desktop bounds). |
| 5 | Incoming Call Screen | 🟢 Implemented | Listens to UDP `call_invite`. |
| 6 | Onboarding Screen | 🟢 Implemented | Generates Cryptographic UUID. |
| 7 | Screen Share Overlay | 🟢 Implemented | Floating native overlay logic. |
| 8 | Settings Screen | 🟢 Implemented | Local peer configurations. |

### Design System
- [x] Responsive Strategy: `SingleChildScrollView` + `math.max` scaling limits.
- [x] Desktop Bounds: Padded `_ControlsPill` optimized for widescreen.
- [x] Typography & Palettes normalized.

---

## 🟢 Phase 1 & 2 — Feature Implementation

- [x] **F1 — Onboarding:** Device name + UUID via secure storage.
- [x] **F2 — Device Discovery:** mDNS + UDP Broadcast (5s interval, 10s prune).
- [x] **F3 — Chat:** WebRTC Data Channels (Text payloads).
- [x] **F4 — Voice Call:** VoIP over local WebSockets. 
- [x] **F5 — Video Call:** Hardware-accelerated VP8 with aggressive 60 FPS constraints (`addTransceiver`).
- [x] **F6 — Screen Share:** Bidirectional casting.
  - Linux screen share: ✅ Working (monitor source)
  - Linux system audio: ✅ Working (PipeWire/PulseAudio)
  - Android system audio: 🔴 Requires native code
  - Windows system audio: ✅ Working (WASAPI)
  - Mic + system audio simultaneously: 🔴 Not supported on Linux (dialog shown to user)
- [x] **F7 — File Sharing:** Chunked transfer.

---

## 🟡 Phase 3 — Hardening & Recovery (Current)

- [x] **UDP Session Healing:** Added `Session ID` to state.
- [x] **Timer Architecture:** 5s ICE disconnected grace period → ICE Restart → 15s absolute kill timer.
- [x] **Reconnect Loop:** `_attemptReconnect` successfully binds new UDP packet with original `Session ID` to heal ghost calls.
- [ ] **Cross-Platform Interoperability Matrix Testing:**
  - [x] Android → Android
  - [x] Windows → Android
  - [x] Linux → Android
  - [ ] Linux → Windows

---

## ⬜ Phase 4 — Native Audio & Hardware Cryptography (Roadmap)

- [x] Linux System Audio Routing (`pactl` native monitor routing)
- [ ] Android `AudioPlaybackCapture` MethodChannel
- [ ] AES-256 Vault integration for offline contacts
