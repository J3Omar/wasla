# Wasla 🔗

> **LAN Communication App** — Full communication without internet, strictly on your home network.

---

## 💡 About The Project

**Wasla** is a Flutter application for Local Area Network (LAN) communication without internet consumption.

**The Problem:** Limited internet quotas. Any call on Telegram or WhatsApp consumes data, even if the other person is in the same house on the same router.

**The Solution:** A full communication app that works purely on the internal WiFi — **Voice + Video + Chat + Files + Screen Share** — with zero internet egress.

---

## ✨ Features

| Feature | Description | Status |
|---------|-------------|--------|
| 🔍 Device Discovery | Auto-discover devices on the network | ✅ Working |
| 💬 Chat | Local encrypted text messages | ✅ Working |
| 📞 Voice Call | 1-on-1 and group voice calls | ✅ Working |
| 📹 Video Call | 720p video calls | ✅ Working |
| 🖥️ Screen Share | Bidirectional screen sharing | ✅ Working |
| 📁 File Sharing | Send files during chat | ✅ Working |

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
| 1 | Splash Screen | ✅ Done |
| 2 | Onboarding (Device Name) | ✅ Done |
| 3 | Home — Connected Devices | ✅ Done |
| 4 | Chat Screen | ✅ Done |
| 5 | Outgoing Call Screen | ✅ Done |
| 6 | Incoming Call Screen | ✅ Done |
| 7 | Active Voice Call | ✅ Done |
| 8 | Active Video Call | ✅ Done |
| 9 | Screen Share Screen | ✅ Done |
| 10 | Settings Screen | ✅ Done |

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
│   ├── ARCHITECTURE.md           ← Technical Architecture
│   ├── MASTER_REFERENCE.md       ← Master Reference
│   ├── PRD.md                    ← Product Requirements
│   ├── PROGRESS.md               ← Overall Project Progress
│   ├── ROADMAP.md                ← Project Roadmap
│   ├── UI_UX_ARCHITECTURE.md     ← UI/UX guidelines
│   └── features/
│       ├── chat/
│       ├── device_discovery/
│       ├── file_sharing/
│       ├── onboarding/
│       ├── screen_share/
│       ├── video_call/
│       └── voice_call/
├── design/
│   ├── design_reference.md       ← Colors and typography
│   ├── design_system.md          ← Stitch Design System
│   ├── screens_gallery.md        ← Screenshots overview
│   └── screens/                  ← Stitch Screenshots directory
├── lib/
│   ├── core/
│   │   ├── config/
│   │   ├── network/
│   │   ├── router/
│   │   ├── theme/
│   │   └── utils/
│   └── features/
│       ├── call/                 ← Voice/Video calls and screen sharing
│       ├── chat/                 ← Text messaging
│       ├── discovery/            ← P2P network discovery
│       ├── file_sharing/         ← File transfer
│       ├── profile/              ← User profiles
│       ├── setup/                ← App onboarding
│       └── shell/                ← Main navigation shell
├── assets/
│   ├── audio/
│   └── images/
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

## 📦 Installation Notes

### Windows
The Windows installer (`Wasla_Setup.exe`) automatically:
- Installs VB-Audio Virtual Cable — required for sharing system audio during screen share
- Configures Windows audio settings for optimal call quality

After installation, a system restart is recommended to activate the audio driver.

> **Screen share with system audio** requires VB-Audio Virtual Cable. The installer handles this automatically. If you choose to skip it during setup, screen share will still work but without system audio capture.

### Linux
System audio sharing during screen share requires PulseAudio or PipeWire (recommended). Most modern Linux distributions include this by default.

### Android
No additional setup required.

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
