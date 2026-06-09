# Feature: Video Call

---

## 🎯 Goal
Add a Video Track to the existing WebRTC connection — no new signaling needed.

---

## ✅ Prerequisites

- [x] **Voice Call fully working** — Video Call extends the same WebRTC Service
- [x] Dependencies: `permission_handler` (for Camera permission)
- [x] Permissions:
  - Android: `CAMERA`
  - Windows/Linux: camera access

---

## 📝 User Stories

- [x] As a user, I want to see the other person on camera
- [x] As a user, I want to toggle my camera on/off without ending the call

---

## 🔧 Coding Checklist

### Step 1 — Extend WebRTC Service
- [x] In `lib/features/call/data/call_manager.dart` add:
  - `toggleVideo()` — camera stream (720p / 30fps with flexible constraints)
  - Video track negotiation during SDP Offer/Answer phase

### Step 2 — Presentation: Video Call Screen
- [x] Update `lib/features/call/presentation/call_screen.dart`
  - Full-screen `RTCVideoView` (remote feed)
  - Small corner `RTCVideoView` (local preview) via PiP Stack
  - Same Controls Pill from Voice Call, updated with Camera toggle

### Step 3 — Multi-Party Video (optional initially)
- [ ] Create `lib/features/call/presentation/video_grid.dart`
  - Layout adapts: 1x1 / 2x1 / 2x2 based on participant count

---

## 🧪 Acceptance Criteria

- [x] Video works at 720p on LAN
- [x] Toggle camera without disconnecting
- [x] Local preview in corner

---

## 📦 Required Packages

```yaml
# No new packages — uses flutter_webrtc from Voice Call
permission_handler: ^11.4.0  # Camera permission (if not already added)
```
