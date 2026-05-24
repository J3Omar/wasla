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

### Step 1 — Data: Screen Capture Service
- [ ] Create `lib/features/screen_share/data/screen_capture_service.dart`
  - `startScreenShare()`:
    ```dart
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'video': {'cursor': 'always'},
      'audio': false,  // optional
    });
    ```
  - Add stream as a second Video Track to the WebRTC connection
  - `stopScreenShare()` — remove the track

### Step 2 — Domain: Screen Share State
- [ ] Create `lib/features/screen_share/domain/screen_share_state.dart`
  ```dart
  enum ScreenShareState { inactive, sharing, viewing }
  ```

### Step 3 — Presentation
- [ ] Update `call_controls_bar.dart` — activate Screen Share button
- [ ] When remote peer shares: display their stream in the Video View
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
