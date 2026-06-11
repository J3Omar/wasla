# Feature Specification: P2P VoIP Engine

## 🎯 Objective
Deliver zero-latency, high-fidelity Peer-to-Peer audio calls across the LAN without relying on external STUN/TURN servers. Implement robust network degradation recovery to ensure VoIP connections survive WiFi toggles or subnet migrations.

## 🏗️ Architectural Specifications

### 1. Media Engine (`call_manager.dart`)
- **API:** `getUserMedia({ audio: true, video: false })`.
- **Filters:** OS-native Echo Cancellation and Noise Suppression are aggressively enabled to prevent feedback loops in close proximity.
- **Topology:** Full Mesh P2P. ICE server arrays are explicitly empty (`iceServers: []`) forcing direct Host Candidate resolution.

### 2. State & Discovery Signaling
- **Call Invite Port:** UDP Port `45680`.
- **Signaling Layer:** Ephemeral WebSockets dynamically bound between `46100–46200`.

### 3. Connection Healing & Session IDs (Critical Flow)
- **Initiation:** The Caller generates a Cryptographic `Session ID` upon dialing, embedding it into the UDP invite payload.
- **Degradation Detection:** `RTCPeerConnectionState.disconnected` triggers the `_iceEndCallTimer` (15-second doom timer).
- **UDP Resignaling:** If the WebSocket pipeline dies (e.g., router reboot, WiFi toggle), `_attemptReconnect()` binds a fresh local WS port and dispatches a healing UDP payload containing the *same* `Session ID`.
- **Resolution:** The remote peer intercepts the payload, matches the `Session ID`, bypasses the Ringing UI, and processes the new SDP Offer, rescuing the active call state before the 15-second timer expires.

## 🧪 Acceptance Criteria
- [x] Host Candidates resolve in `< 2.5 seconds`.
- [x] Call rejections (Declined) trigger appropriate UI alerts and gracefully tear down the WS server.
- [x] Disconnecting the LAN forcefully triggers the 15-second doom timer, automatically terminating the call if the subnet cannot be restored in time.
