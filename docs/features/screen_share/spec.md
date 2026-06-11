# Feature: Screen Share

---

## 🎯 Goal
Add a Screen Track to the WebRTC connection — bidirectional between all platforms.

---

## ✅ Prerequisites

- [ ] **Video Call fully working** — Screen Share is a second Video Track
- [ ] No new packages — `flutter_webrtc` handles `getDisplayMedia`
- [ ] Permissions:
  - Android: `MediaProjection` API (requires foreground service)
  - Windows/Linux: `getDisplayMedia()` — built into flutter_webrtc

---

## 📝 User Stories

- [ ] As a desktop user, I want to share my screen with a mobile device
- [ ] As a mobile user, I want to share my screen with a desktop
- [ ] As a user, I want to stop screen sharing easily

---

## 🔧 Coding Checklist

### Step 1 — Core Logic (call_manager.dart)
- [x] Create `toggleScreenShare()` in `call_manager.dart`
  - Use `navigator.mediaDevices.getDisplayMedia` with ideal `1280x720` at `60fps`.
  - Use `sender.replaceTrack()` to seamlessly swap the Camera track for the Screen track. Do NOT add a second video track (prevents WebRTC Glare/renegotiation storms).
  - Handle OS-level stop button (e.g., Android floating bar) via track `onEnded` listener.

### Step 2 — Domain (call_state.dart)
- [x] Add `isScreenSharing` to `CallSession` state.

### Step 3 — Presentation & OS Permissions
- [ ] Update `AndroidManifest.xml` to include `mediaProjection` foreground service type for Android 14+.
- [ ] Update `call_controls_bar.dart` — activate Screen Share button.
- [ ] Overlay indicator: "You are sharing your screen"

---

## 🧪 Acceptance Criteria

- [ ] Screen Share works Windows → Android
- [ ] Screen Share works Android → Windows
- [ ] Screen Share works Android → Android
- [ ] Stop button works during a call
- [ ] Optional device audio sharing

---

## 📦 Required Packages

```yaml
# No new packages — everything is in flutter_webrtc
```
