# Feature: Voice Call

---

## 🎯 Goal
P2P voice call between two devices (up to 4 in group) via WebRTC Audio Track — no external server.

---

## ✅ Prerequisites

- [ ] **Device Discovery complete** — need peer IP + signaling port
- [ ] Dependencies in `pubspec.yaml`:
  ```yaml
  flutter_webrtc: ^0.x.x
  web_socket_channel: ^3.x.x
  permission_handler: ^11.x.x
  ```
- [ ] Permissions:
  - Android: `RECORD_AUDIO` + `INTERNET`
  - Windows/Linux: microphone access

---

## 📝 User Stories

- [ ] As a user, I want to make a voice call to another device
- [ ] As a user, I want to mute/unmute my microphone
- [ ] As a user, I want to decline a call

---

## 🔧 Coding Checklist

### Step 1 — Data: Signaling Server
- [ ] Create `lib/features/call/data/signaling_server.dart`
  - Caller creates a local WebSocket Server on a random port
  - Broadcasts port via Discovery channel
  - Exchanges SDP Offer/Answer + ICE Candidates
  - Closes after P2P connection is established

### Step 2 — Data: WebRTC Service
- [ ] Create `lib/features/call/data/webrtc_service.dart`
  - `createPeerConnection()` with LAN-only ICE config
  - `addAudioTrack()` — get mic stream
  - `createOffer()` / `setRemoteDescription(sdp)`
  - `addIceCandidate(candidate)`
  - `muteAudio(bool)` / `unmuteAudio()`
  - `closeConnection()`

### Step 3 — Domain: Call State
- [ ] Create `lib/features/call/domain/call_state.dart`
  ```dart
  enum CallState { idle, outgoing, incoming, active, ended }
  ```

### Step 4 — Presentation
- [ ] `outgoing_call_screen.dart` — "Calling..."
- [ ] `incoming_call_screen.dart` — Accept / Decline
- [ ] `voice_call_screen.dart` — Timer + Controls (Glassmorphism pill)
  - Mic | Camera | Screen Share | Add | End Call

### Step 5 — Call Logic
- [ ] 3 declines → "Device busy" message
- [ ] Network disconnect → auto-end call

---

## 🧪 Acceptance Criteria

- [ ] Call connects in under 3 seconds
- [ ] Clear audio with no delay on LAN
- [ ] Mute / Unmute works
- [ ] 3 declines → "busy" message
- [ ] Network loss → auto-disconnect

---

## 📦 Required Packages

```yaml
flutter_webrtc: ^0.14.1
web_socket_channel: ^3.0.3
permission_handler: ^11.4.0
```
