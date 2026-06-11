# Feature Specification: P2P Screen Casting

## 🎯 Objective
Enable high-framerate, bidirectional Screen Sharing over active WebRTC sessions without triggering SDP renegotiation storms. Implement specific OS-level fallbacks for robust capturing.

## 🏗️ Architectural Specifications

### 1. Transport Mechanisms (`call_manager.dart`)
- **API:** `navigator.mediaDevices.getDisplayMedia`.
- **Renegotiation Strategy:** The engine avoids renegotiating a secondary video track. Instead, it utilizes `RTCRtpSender.replaceTrack()` to instantly swap the active Camera track with the generated Screen track. This prevents WebRTC "Glare" and drastically reduces latency.

### 2. Constraints & Resolutions
- **Target Encoding:** `1280x720` (Mobile) / `1920x1080` (Desktop) at a strict `60 FPS`.

### 3. Linux Fallback Mechanism (Critical)
- **Problem:** Many Linux display servers (specifically Wayland or unconfigured X11 environments) strictly reject `getDisplayMedia` constraints if `audio: true` is passed, due to the lack of native loopback drivers. This causes the entire screen capture promise to fail.
- **Solution:** `call_manager.dart` implements a cascading `try/catch` block. If the initial capture fails, it automatically falls back to `{'video': true, 'audio': false}` to guarantee that the video cast succeeds even if system audio capturing is unsupported by the OS.

### 4. OS-Level Permission Handling
- **Android 14+:** Dynamically spins up a Foreground Service of type `mediaProjection` prior to capturing, preventing OS-level memory termination.
- **Native OS Stops:** Listeners bound to the track's `onEnded` event capture native OS "Stop Sharing" button presses (e.g., Android's floating pill) to gracefully restore the Camera track.

## 🧪 Acceptance Criteria
- [x] WebRTC `replaceTrack` executes seamlessly without terminating the P2P connection.
- [x] Linux gracefully defaults to `audio: false` without crashing.
- [x] Android Foreground Service holds Wakelock throughout the cast.
