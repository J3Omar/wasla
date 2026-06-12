# Wasla 🔗

> **LAN Communication App** — Full communication without internet, strictly on your home network.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20Linux-green)](https://flutter.dev/multi-platform)
[![Status](https://img.shields.io/badge/Status-Phase%200%20%E2%80%94%20Design-yellow)](./docs/PROGRESS.md)

---

## 💡 About The Project

**Wasla** is a Flutter application for Local Area Network (LAN) communication without internet consumption.

**The Problem:** Limited internet quotas. Any call on Telegram or WhatsApp consumes data, even if the other person is in the same house on the same router.

**The Solution:** A full communication app that works purely on the internal WiFi — **Voice + Video + Chat + Files + Screen Share** — with zero internet egress.

---

## ✨ Features

| Feature | Description | Status |
|--------|-------|--------|
| 🔍 Device Discovery | Auto-discover devices on the network | 🔴 Not Started |
| 💬 Chat | Local encrypted text messages | 🔴 Not Started |
| 📞 Voice Call | 1-on-1 and group voice calls | 🔴 Not Started |
| 📹 Video Call | 720p Video calls | 🔴 Not Started |
| 🖥️ Screen Share | Bidirectional screen sharing | 🟡 In Progress (Linux ✅, Android 🔴, Windows ✅) |
| 📁 File Sharing | Send files during chat | 🔴 Not Started |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│         Local WebSocket (Signaling)          │
│         Caller creates an ephemeral Server   │
└─────────────┬───────────────────────────────┘
              │ Connection payload exchange only (LAN)
┌─────────────▼───────────────────────────────┐
│           WebRTC P2P — over LAN              │
│   Voice + Video + screen share + files       │
│     100% Local — Zero internet routing       │
└─────────────────────────────────────────────┘
```

**Security:**
- WebRTC encrypts all media automatically with DTLS-SRTP.
- All data and chats are stored locally and encrypted.
- No external accounts or servers.

---

## 🧱 Tech Stack

| Layer | Technology |
|--------|---------|
| UI + Logic | Flutter / Dart |
| Audio/Video/Screen | `flutter_webrtc` |
| Signaling | Local WebSocket Server |
| Device Discovery | mDNS + UDP Broadcast |
| Chat Storage | Drift / SQLite (local) |
| Device ID | `flutter_secure_storage` |
| Design | Google Stitch (AI UI Generator) |

---

## 📱 Screens

| # | Screen | Status |
|---|--------|--------|
| 1 | Splash Screen | 🟡 Designed |
| 2 | Onboarding (Device Name) | 🔴 Pending |
| 3 | Home — Connected Devices | 🟡 Designed |
| 4 | Chat Screen | 🟡 Designed |
| 5 | Outgoing Call Screen | 🔴 Pending |
| 6 | Incoming Call Screen | 🟡 Designed |
| 7 | Active Voice Call | 🟡 Designed |
| 8 | Active Video Call | 🔴 Pending |
| 9 | Screen Share Screen | 🔴 Pending |
| 10 | Settings Screen | 🔴 Pending |

---

## 🖥️ Supported Platforms

| Platform | OS | Minimum Requirement |
|--------|--------|-------------|
| Android | Android | 5.0 (API 21)+ |
| Windows | Windows | 10+ |
| Linux | Linux | GTK 3.0+ |

---

## 📁 Project Structure

```
wasla/
├── docs/
│   ├── PRD.md                    ← Product Requirements
│   ├── ARCHITECTURE.md           ← Technical Architecture
│   ├── PROGRESS.md               ← Overall Project Progress
│   └── features/
│       ├── onboarding/
│       ├── device_discovery/
│       ├── chat/
│       ├── voice_call/
│       ├── video_call/
│       ├── file_sharing/
│       └── screen_share/
├── design/
│   ├── design_reference.md       ← Colors and typography
│   ├── design_system.md          ← Stitch Design System
│   └── screens/                  ← Stitch Screenshots
├── lib/
│   ├── core/
│   │   ├── config/
│   │   ├── theme/
│   │   ├── router/
│   │   └── utils/
│   └── features/
│       ├── onboarding/
│       ├── discovery/
│       ├── chat/
│       ├── voice_call/
│       ├── video_call/
│       ├── file_sharing/
│       └── screen_share/
├── assets/
│   ├── images/
│   └── fonts/
└── test/
```

---

## 🚀 Running the Project

```bash
# Install dependencies
flutter pub get

# Run on Android
flutter run -d android

# Run on Linux
flutter run -d linux

# Run on Windows
flutter run -d windows
```

---

📊 **Progress Details:** [PROGRESS.md](./docs/PROGRESS.md)

---

## 🎨 Design

The design is built on **Google Stitch** with a design system named **Kinetic Ether**:
- **Theme:** Dark Only
- **Style:** Glassmorphism + Subtle Gradients
- **Vibe:** Tech / Cyberpunk / Minimal
- **Primary:** Cyan `#00DBE7`
- **Secondary:** Purple `#7000FF`
- **Fonts:** Hanken Grotesk + Inter + Geist

📐 **Full Details:** [design/design_reference.md](./design/design_reference.md)

---

## 📋 Features Spec

| Feature | Spec | Progress |
|---------|------|----------|
| Onboarding | [spec.md](./docs/features/onboarding/spec.md) | [progress.md](./docs/features/onboarding/progress.md) |
| Device Discovery | [spec.md](./docs/features/device_discovery/spec.md) | [progress.md](./docs/features/device_discovery/progress.md) |
| Chat | [spec.md](./docs/features/chat/spec.md) | [progress.md](./docs/features/chat/progress.md) |
| Voice Call | [spec.md](./docs/features/voice_call/spec.md) | [progress.md](./docs/features/voice_call/progress.md) |
| Video Call | [spec.md](./docs/features/video_call/spec.md) | [progress.md](./docs/features/video_call/progress.md) |
| File Sharing | [spec.md](./docs/features/file_sharing/spec.md) | [progress.md](./docs/features/file_sharing/progress.md) |
| Screen Share | [spec.md](./docs/features/screen_share/spec.md) | [progress.md](./docs/features/screen_share/progress.md) |

*Personal Project — No external servers, everything is kept entirely on your home network.*
