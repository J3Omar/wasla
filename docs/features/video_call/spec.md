# Feature Specification: P2P Hardware Video Calling

## 🎯 Objective
Establish robust, zero-latency WebRTC Video tracking leveraging aggressive hardware-accelerated encodings over LAN. Introduce a resilient UDP connection healing architecture to dynamically recover shattered TCP/WebSocket layers without dropping the active call.

## 🏗️ Architectural Specifications

### 1. Media Encoding Constraints (`call_manager.dart`)
- **Aggressive Framerate Lock:** The engine uses `navigator.mediaDevices.getUserMedia` with strict constraints (`frameRate: {'ideal': 60, 'max': 60}`) to ensure fluid 60 FPS captures.
- **Bitrate Enforcement:** To counteract default WebRTC auto-degradation over volatile LAN networks, the engine intercepts the `RTCRtpSender` via `addTransceiver` prior to SDP negotiation. It explicitly sets the `RTCRtpEncoding` properties to:
  - `minBitrate`: 1,000,000 (1 Mbps)
  - `maxBitrate`: 2,500,000 (2.5 Mbps)

### 2. Session ID & UDP Connection Healing (Crucial Mechanism)
- **Problem:** If a user toggles their WiFi or physically roams, the underlying TCP/WebSocket signaling socket breaks. Legacy ICE restarts fail if the signaling channel is dead.
- **Session Identity:** Upon `startCall`, a unique Cryptographic `Session ID` is dynamically generated and stored in the `CallSession` state. This ID is serialized into the initial JSON UDP `call_invite` payload.
- **State Machine Timers:**
  1. **5s Grace Period:** If the `onConnectionState` event fires `RTCPeerConnectionStateDisconnected`, a 5-second timer starts. If the connection naturally recovers, the timer cancels. If not, it triggers `restartIce()`.
  2. **15s Kill Timer:** Simultaneously, a 15-second doom timer begins. If ICE negotiation fails to recover within this window, the active call is NOT ended.
- **`_attemptReconnect` Subroutine:** 
  - The engine spins up a fresh local WebSocket server on a newly generated dynamic port.
  - It dispatches a *New* UDP `call_invite` to the known Peer IP.
  - **Crucially:** This payload injects the *existing* `Session ID`. 
  - The remote peer's UDP listener parses the payload, recognizes the active `Session ID`, bypasses the "Incoming Call" UI, and silently executes `setRemoteDescription` with the new WS Port, gracefully healing the connection.

### 3. Presentation Layer (`call_screen.dart`)
- Renders the remote peer via `RTCVideoView` in `object-fit: cover`.
- Local preview overlaps as a `Draggable` PiP window.
- Smooth transitions during camera hardware `facingMode` toggling.

## 🧪 Acceptance Criteria
- [x] Transceivers accurately enforce the 1-2.5Mbps bitrate floor.
- [x] Hardware correctly outputs `60 FPS` streaming.
- [x] Dropping the WiFi network and reconnecting successfully triggers `_attemptReconnect` and heals the active session within 15 seconds without user intervention.
