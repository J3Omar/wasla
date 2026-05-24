# Feature: Video Call

---

## 🎯 Goal
Add a Video Track to the existing WebRTC connection — no new signaling needed.

---

## ✅ Prerequisites

- [ ] **Voice Call fully working** — Video Call extends the same WebRTC Service
- [ ] Dependencies: `permission_handler` (for Camera permission)
- [ ] Permissions:
  - Android: `CAMERA`
  - Windows/Linux: camera access

---

## 📝 User Stories

- [ ] As a user, I want to see the other person on camera
- [ ] As a user, I want to toggle my camera on/off without ending the call

---

## 🔧 Coding Checklist

### Step 1 — Extend WebRTC Service
- [ ] In `lib/features/call/data/webrtc_service.dart` add:
  - `addVideoTrack()` — camera stream (720p / 30fps)
  - `toggleCamera(bool)` — enable/disable video track
  - `switchCamera()` — front/back (mobile only)

### Step 2 — Presentation: Video Call Screen
- [ ] Create `lib/features/call/presentation/video_call_screen.dart`
  - Full-screen `RTCVideoView` (remote feed)
  - Small corner `RTCVideoView` (local preview)
  - Same Controls Pill from Voice Call

### Step 3 — Multi-Party Video (optional initially)
- [ ] Create `lib/features/call/presentation/video_grid.dart`
  - Layout adapts: 1x1 / 2x1 / 2x2 based on participant count

---

## 🧪 Acceptance Criteria

- [ ] Video works at 720p on LAN
- [ ] Toggle camera without disconnecting
- [ ] Local preview in corner
- [ ] Group video call works (3–4 devices)

---

## 📦 Required Packages

```yaml
# No new packages — uses flutter_webrtc from Voice Call
permission_handler: ^11.4.0  # Camera permission (if not already added)
```
