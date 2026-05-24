# ARCHITECTURE — وصلة (Wasla)

> التصميم التقني الكامل للتطبيق | مايو 2026

---

## نظرة عامة

وصلة هو تطبيق P2P كامل يعمل على الـ LAN فقط — **بدون أي خروج للإنترنت**.

---

## 🏗️ البنية الكاملة

```
┌──────────────────────────────────────────────────────┐
│                    Wasla App (Flutter)                │
├──────────────────────────────────────────────────────┤
│                                                      │
│   ┌─────────────┐    ┌─────────────┐                │
│   │  Discovery  │    │  Signaling  │                │
│   │   (mDNS /   │    │  (Local WS  │                │
│   │   UDP BC)   │    │   Server)   │                │
│   └──────┬──────┘    └──────┬──────┘                │
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
│   │   Chat History + Device Registry   │            │
│   └─────────────────────────────────────┘            │
└──────────────────────────────────────────────────────┘
```

---

## 🔍 Device Discovery

**البروتوكول:** mDNS (Multicast DNS) + UDP Broadcast fallback

```
كل جهاز يعلن عن نفسه كل 5 ثواني:
{
  "uuid": "unique-device-id",
  "name": "اسم الجهاز",
  "status": "available | in_call | busy",
  "ip": "192.168.1.x",
  "port": 8765  ← WebSocket Signaling Port
}
```

- **اكتشاف:** خلال 5 ثواني من الفتح
- **اختفاء:** بعد 10 ثواني من الإغلاق
- **يشتغل على:** نفس الـ Subnet بدون إنترنت

---

## 📡 Signaling (محلي 100%)

**الـ Caller** ينشئ WebSocket Server مؤقت على بورت عشوائي.

```
Caller (WS Server)  ←→  Callee (WS Client)
        │                       │
        │    SDP Offer           │
        │──────────────────────►│
        │    SDP Answer          │
        │◄──────────────────────│
        │    ICE Candidates      │
        │◄─────────────────────►│
        │                       │
        │   WebRTC P2P Connected │
        │◄═════════════════════►│
```

بعد الاتصال، الـ WebSocket Server بيتقفل — P2P مباشر.

---

## 🎥 WebRTC Tracks

| النوع | الاستخدام |
|-------|-----------|
| Audio Track | المكالمة الصوتية |
| Video Track | مكالمة الفيديو (720p/30fps) |
| Screen Track | Screen Share |
| Data Channel | Chat + File Transfer |

---

## 💬 Chat & Storage

- **Database:** Drift (SQLite wrapper — actively maintained)
- **Encryption:** Android Keystore / Windows DPAPI
- **Transport:** WebRTC Data Channel
- **مسار الحفظ:**
  ```
  Android → /storage/emulated/0/Wasla/
  Windows → C:\Users\[name]\Documents\Wasla\
  Linux   → ~/Wasla/
  ```

---

## 📁 هيكل الـ Code

```
lib/
├── core/
│   ├── config/
│   │   └── app_config.dart       ← Constants, ports
│   ├── theme/
│   │   ├── app_colors.dart       ← Color palette
│   │   ├── app_typography.dart   ← Text styles
│   │   └── app_theme.dart        ← ThemeData
│   ├── router/
│   │   └── app_router.dart       ← go_router
│   └── utils/
│       ├── logger.dart
│       └── formatters.dart
│
└── features/
    ├── onboarding/
    │   ├── data/
    │   │   └── device_storage.dart  ← uuid + name in secure storage
    │   └── presentation/
    │       └── onboarding_screen.dart
    │
    ├── discovery/
    │   ├── data/
    │   │   ├── mdns_service.dart
    │   │   └── udp_broadcast.dart
    │   ├── domain/
    │   │   └── device_model.dart
    │   └── presentation/
    │       └── home_screen.dart
    │
    ├── chat/
    │   ├── data/
    │   │   ├── chat_repository.dart
    │   │   └── chat_database.dart
    │   ├── domain/
    │   │   └── message_model.dart
    │   └── presentation/
    │       └── chat_screen.dart
    │
    ├── call/
    │   ├── data/
    │   │   ├── webrtc_service.dart
    │   │   └── signaling_server.dart
    │   ├── domain/
    │   │   └── call_state.dart
    │   └── presentation/
    │       ├── outgoing_call_screen.dart
    │       ├── incoming_call_screen.dart
    │       ├── voice_call_screen.dart
    │       └── video_call_screen.dart
    │
    ├── file_sharing/
    │   ├── data/
    │   │   └── file_transfer_service.dart
    │   └── presentation/
    │       └── file_progress_widget.dart
    │
    └── screen_share/
        ├── data/
        │   └── screen_capture_service.dart
        └── presentation/
            └── screen_share_overlay.dart
```

---

## 📦 Dependencies

```yaml
dependencies:
  flutter_webrtc: ^0.14.1         # WebRTC
  drift: ^2.25.0                  # SQLite DB
  sqlite3_flutter_libs: ^0.5.30   # SQLite native libs
  flutter_secure_storage: ^9.2.4  # UUID + Keys
  go_router: ^14.6.2              # Navigation
  multicast_dns: ^0.3.2+3         # mDNS discovery
  network_info_plus: ^6.1.4       # Local IP
  web_socket_channel: ^3.0.3      # Signaling
  path_provider: ^2.1.5           # File paths
  permission_handler: ^11.4.0     # Permissions
  file_picker: ^8.3.7             # File selection
  flutter_riverpod: ^2.6.1        # State management
  uuid: ^4.5.1                    # UUID generation

dev_dependencies:
  drift_dev: ^2.25.0              # Drift codegen
  build_runner: ^2.4.15           # Code generation
```

---

## 🔐 الأمان

| الطبقة | التقنية |
|--------|---------|
| WebRTC Media | DTLS-SRTP (automatic encryption) |
| Chat Storage | Drift + SQLite (local, encrypted) |
| Device Keys | Android Keystore / Windows DPAPI |
| Signaling | 100% local — never leaves the LAN |

---

## 🎯 Performance Targets

| المقياس | الهدف |
|---------|-------|
| Call Setup Time | < 3 ثواني |
| Audio Latency | < 150ms على LAN |
| Video Quality | 720p / 30fps |
| Device Discovery | < 5 ثواني |
| Device Timeout | < 10 ثواني |
| Message Delivery | < 500ms |
