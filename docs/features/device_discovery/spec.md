# Feature Specification: Device Discovery Engine

## 🎯 Objective
Autonomously broadcast device presence across the local subnet and maintain an active registry of all reachable peers running the application, ensuring discovery under 5 seconds.

## 🏗️ Architectural Specifications

### 1. Transport Mechanisms
- **Primary:** UDP Broadcast (`255.255.255.255`) on port `45678`.
- **Secondary (Fallback):** mDNS (Multicast DNS) utilizing `_wasla._tcp.local`.

### 2. State Machine & Persistence (`DeviceRegistry`)
- Maintains an in-memory hash map of peers indexed by `uuid`.
- **Heartbeat Interval:** Devices dispatch JSON payloads every 5 seconds.
- **Eviction Policy:** Devices missing 2 consecutive heartbeats (last seen > 10s) are automatically dropped from the active state.

### 3. Payload Serialization
```json
{
  "uuid": "unique-uuid",
  "name": "Display Name",
  "status": "available",
  "ip": "192.168.1.5",
  "port": 8765
}
```

### 4. Application Integration
- Hooked to `discoveryServiceProvider` (Riverpod `AsyncNotifier`).
- Automatically resolves the interface IP via `network_info_plus`.

## 🧪 Acceptance Criteria
- [x] Own device renders instantaneously with a local badge.
- [x] External peers render `< 5s` post-launch.
- [x] Eviction occurs gracefully `< 10s` post-disconnect.
- [x] Real-time reflection of peer availability (`Busy` vs `In Call`).
