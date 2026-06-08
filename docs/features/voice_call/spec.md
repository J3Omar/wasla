# Feature: Voice Call

---

## 🎯 Goal
P2P voice call between two devices (up to 4 in group — future iteration) via WebRTC Audio Track — no external server.

---

## ✅ Prerequisites

- [x] **Device Discovery complete** — peer IP available via `discoveryServiceProvider`
- [x] Dependencies in `pubspec.yaml` (already present):
  ```yaml
  flutter_webrtc: ^0.14.1
  web_socket_channel: ^3.0.3
  permission_handler: ^11.4.0
  ```
- [x] Permissions:
  - Android: `RECORD_AUDIO` + `INTERNET` — declared in `AndroidManifest.xml`
  - Linux/Windows: microphone access via `permission_handler`

---

## 📝 User Stories

- [x] As a user, I want to make a voice call to another device
- [x] As a user, I want to mute/unmute my microphone
- [x] As a user, I want to decline a call
- [x] As a user, I want to see the call duration timer
- [x] Network disconnect → auto-end call after 30 s when no response (wired via `RTCPeerConnectionState`)

---

## 🔧 Coding Checklist

### Step 1 — Domain: Call State
- [x] `lib/features/call/domain/call_state.dart`
  - `enum CallState { idle, outgoing, incoming, connecting, active, ended }`
  - `enum CallEndReason { normal, declined, missed, networkLoss, busy }`
  - `class CallSession` with copyWith

### Step 2 — Data: CallManager (WebRTC)
- [x] `lib/features/call/data/call_manager.dart`
  - `startCall()` — caller creates local WS signaling server, sends UDP invite
  - `acceptCall()` — callee connects to caller's WS server
  - `declineCall()` — sends decline signal
  - `_initiateOffer()` — creates PeerConnection, adds audio track, SDP offer
  - `_handleSignal()` — handles offer/answer/ICE/declined/ended
  - `toggleMute()` / `toggleSpeaker()`
  - `dispose()`

### Step 3 — Domain: CallNotifier (Riverpod)
- [x] `lib/features/call/domain/call_provider.dart`
  - `callProvider` — `AsyncNotifierProvider<CallNotifier, CallSession>`
  - UDP listener on port **45680** for incoming call invites
  - `onIncomingCall` callback hooked in `main_shell.dart`

### Step 4 — Presentation
- [x] `outgoing_call_screen.dart` — pulsing avatar, "Calling...", End button
- [x] `incoming_call_screen.dart` — ripple ring avatar, Accept / Decline
- [x] `voice_call_screen.dart` — timer, peer name, glassmorphism controls pill
  - Mute | Speaker | End Call

### Step 5 — Routing
- [x] `/call/outgoing` → `OutgoingCallScreen`
- [x] `/call/incoming` → `IncomingCallScreen` (extra: callerId, callerName, callerIp, signalingPort)
- [x] `/call/active` → `VoiceCallScreen`

### Step 6 — Integration
- [x] `main_shell.dart` — reads `callProvider` at startup, hooks `onIncomingCall` → pushes `/call/incoming`
- [x] `home_screen.dart` — **Call** button on device card calls `callProvider.notifier.startCall()` then pushes `/call/outgoing`
- [x] `chat_screen.dart` — **Phone** icon in AppBar wired to same flow

### Step 7 — Call Logic
- [x] Network disconnect → auto-end after 30 s when no response (partially wired via `onConnectionState`)

---

## 🧪 Acceptance Criteria

- [x] Call connects in under 3 seconds on LAN
- [x] Clear audio with no delay
- [x] Mute / Unmute works
- [x] Network loss → auto-disconnect

---

## 📦 Required Packages (all already in pubspec.yaml)

```yaml
flutter_webrtc: ^0.14.1
web_socket_channel: ^3.0.3
permission_handler: ^11.4.0
```

---

## 🏗️ Architecture Notes

- **UDP port 45680** — call invites (discovery=45678, chat=45679)
- **Signaling**: local `HttpServer` WebSocket on random port 46100–46200 — same pattern as chat
- **Audio only** — `getUserMedia({ audio: true, video: false })` with echo cancellation + noise suppression
- **No STUN/TURN** — 100% LAN, `iceServers: []`
