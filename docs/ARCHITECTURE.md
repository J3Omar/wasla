# SYSTEM ARCHITECTURE — Wasla

> Technical Systems Design & Architecture | June 2026

---

## 1. Executive Summary

Wasla is a fully decentralized, Peer-to-Peer (P2P) communication application engineered exclusively for Local Area Networks (LAN). It operates with **zero internet egress**, ensuring that all signaling, media, and data channels remain physically bound to the local subnet.

---

## 2. High-Level Topology

```text
┌──────────────────────────────────────────────────────┐
│                    Wasla App (Flutter)               │
├──────────────────────────────────────────────────────┤
│                                                      │
│   ┌─────────────┐    ┌─────────────┐                 │
│   │  Discovery  │    │  Signaling  │                 │
│   │   (mDNS /   │    │  (Local WS  │                 │
│   │   UDP BC)   │    │   Server)   │                 │
│   └──────┬──────┘    └──────┬──────┘                 │
│          │                  │                        │
│          └────────┬─────────┘                        │
│                   │ LAN Only                         │
│          ┌────────▼─────────┐                        │
│          │   WebRTC P2P     │                        │
│          │  Audio + Video   │                        │
│          │  Data Channels   │                        │
│          └──────────────────┘                        │
│                                                      │
│   ┌─────────────────────────────────────┐            │
│   │     Local Storage (Drift/SQLite)    │            │
│   │   Chat History + Device Registry    │            │
│   └─────────────────────────────────────┘            │
└──────────────────────────────────────────────────────┘
```

---

## 3. Core Subsystems

### 3.1 Device Discovery
**Protocols:** mDNS (Multicast DNS) + UDP Broadcast fallback

Nodes advertise their presence via UDP broadcast on port `45678` (or configured port). The broadcast payload is emitted every 5 seconds:
```json
{
  "uuid": "unique-device-id",
  "name": "Display Name",
  "status": "available | in_call | busy",
  "ip": "192.168.1.x",
  "port": 8765
}
```

- **Discovery:** Achieved within 5 seconds of the application opening.
- **Eviction:** Disconnected peers disappear after 10 seconds of missing heartbeats.
- **Network Scope:** Operates exclusively on the local Subnet without internet access.

---

## 4. Signaling (100% Localized)

The **Caller** dynamically instantiates an ephemeral WebSocket Server on a randomized port.

```text
Caller (WS Server)  ←→  Callee (WS Client)
        │                       │
        │    SDP Offer          │
        │──────────────────────►│
        │    SDP Answer         │
        │◄──────────────────────│
        │    ICE Candidates     │
        │◄─────────────────────►│
        │                       │
        │   WebRTC P2P Linked   │
        │◄═════════════════════►│
```

Following the successful exchange of SDP offers and ICE host candidates, the WebSocket Server is terminated. The remaining connection is a direct P2P socket.

---

## 5. WebRTC Tracks

| Track Type | Usage & Specifications |
|---|---|
| **Audio Track** | Voice calling (Hardware Echo Cancellation enabled) |
| **Video Track** | Video calling (Aggressive 60 FPS constraint / 1-2.5 Mbps target) |
| **Screen Track** | Screen sharing (Includes graceful Linux `audio: false` fallback) |
| **Data Channel** | SCTP overlay for Chat & binary File Transfers |

---

## 6. Chat & Storage Persistence

- **Database:** Drift (SQLite wrapper).
- **Encryption:** Payload encryption via Android Keystore / Windows DPAPI.
- **Transport:** WebRTC SCTP Data Channel.
- **Storage Paths:**
  - Android: `/storage/emulated/0/Wasla/`
  - Windows: `C:\Users\[name]\Documents\Wasla\`
  - Linux: `~/Wasla/`

---

## 7. Codebase Directory Architecture

The repository adheres strictly to feature-first layer isolation:

```text
lib/
├── core/
│   ├── config/              ← Environment constants, port configurations
│   ├── network/             ← Base network utilities, IP resolvers
│   ├── router/              ← AppRouter (go_router definitions)
│   ├── theme/               ← AppColors, AppTypography, ThemeData
│   └── utils/               ← Shared loggers, formatters
│
└── features/
    ├── call/                ← Unified Media (Voice/Video/Signaling)
    │   ├── data/
    │   ├── domain/
    │   └── presentation/
    │
    ├── chat/                ← SQLite storage + Data Channels
    │   ├── data/
    │   ├── domain/
    │   └── presentation/
    │
    ├── discovery/           ← mDNS & UDP broadcast engines
    │   ├── data/
    │   ├── domain/
    │   └── presentation/
    │
    ├── file_sharing/        ← Chunked binary TCP/SCTP transfers
    │   ├── data/
    │   ├── domain/
    │   └── presentation/
    │
    ├── profile/             ← Profile viewing / Local configurations
    │   └── presentation/
    │
    ├── screen_share/        ← Native OS capture APIs
    │   ├── data/
    │   ├── domain/
    │   └── presentation/
    │
    ├── setup/               ← First-time Onboarding & Identity Generation
    │   └── presentation/
    │
    └── shell/               ← Application layout root (Home, Navigation)
        └── presentation/
```

---

## 8. Dependencies Ecosystem

```yaml
dependencies:
  flutter_webrtc: ^0.14.1         # Native WebRTC bindings
  drift: ^2.25.0                  # Persistent SQLite Datastore
  sqlite3_flutter_libs: ^0.5.30   # Platform SQLite binaries
  flutter_secure_storage: ^9.2.4  # Hardware-backed UUID / Keys
  go_router: ^14.6.2              # Declarative routing
  multicast_dns: ^0.3.2+3         # Zero-conf networking (mDNS)
  network_info_plus: ^6.1.4       # Active Subnet IP resolution
  web_socket_channel: ^3.0.3      # Handshake signaling 
  path_provider: ^2.1.5           # Directory path resolutions
  permission_handler: ^11.4.0     # Hardware permission grants
  file_picker: ^8.3.7             # OS Native file selection
  flutter_riverpod: ^2.6.1        # Reactive state management
  uuid: ^4.5.1                    # V4 Identity Generation
```

---

## 9. Security Posture

| Layer | Implementation |
|---|---|
| **Media Transport** | DTLS-SRTP (Datagram Transport Layer Security / Secure Real-Time Transport Protocol) is enforced natively by WebRTC for all media tracks. |
| **Data Channels** | Encrypted via WebRTC SCTP overlay. |
| **Signaling** | Ephemeral, LAN-bound local WebSocket channels. Packets are physically restricted by router NAT from public internet exposure. |
| **Identity Storage** | Peer UUIDs and Cryptographic keys reside in hardware-backed secure storage. |

---

## 10. Performance & SLA Targets

| Metric | Threshold |
|---|---|
| **Call Setup Latency** | `< 2.5 seconds` |
| **Audio Jitter/Latency** | `< 150ms` (Subnet constrained) |
| **Video Encoding** | `720p @ 60 FPS` (Hardware Accelerated) |
| **Discovery TTL** | `5 seconds` |
| **Data Delivery** | `< 500ms` |
