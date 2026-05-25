# Feature: Device Discovery

---

## 🎯 Goal
Every device running the app announces itself on the LAN. Other devices discover it within 5 seconds.

---

## ✅ Prerequisites

- [x] **Onboarding complete** — `uuid` and `displayName` stored in `FlutterSecureStorage`
- [x] Dependencies in `pubspec.yaml`:
  ```yaml
  multicast_dns: ^0.3.2+3
  network_info_plus: ^6.1.4
  ```
- [x] Android Manifest permissions:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
  ```

---

## 📝 User Stories

- [x] As a user, I want to see all devices running the app on my network
- [x] As a user, I want to see each device's name and status (available / in call / busy)
- [x] As a user, I want the list to update automatically
- [x] As a user, my own device shows a "THIS DEVICE" badge

---

## 🔧 Coding Checklist

### Step 1 — Domain: Device Model
- [x] `lib/features/discovery/domain/device_model.dart`
  - `Device` class with `uuid`, `displayName`, `localIp`, `port`, `status`, `lastSeen`, `isSelf`
  - `DeviceStatus` enum: `available`, `inCall`, `busy`, `offline`
  - `toJson()` / `fromJson()` for UDP payload

### Step 2 — Data: Device Registry
- [x] `lib/features/discovery/data/device_registry.dart`
  - `Map<String, Device>` indexed by UUID
  - `StreamController` emitting map on every change
  - Eviction timer removes devices with `lastSeen > 10s`

### Step 3 — Data: UDP Broadcast Service (Primary)
- [x] `lib/features/discovery/data/udp_broadcast_service.dart`
  - Binds to port **45678** with `broadcastEnabled = true`
  - Sends JSON announce every 5 seconds to `255.255.255.255`
  - Listens for incoming announcements and upserts into registry

### Step 4 — Data: mDNS Service (Secondary)
- [x] `lib/features/discovery/data/mdns_service.dart`
  - Uses `MDnsClient` for passive discovery on `_wasla._tcp.local`
  - Falls back gracefully — UDP is the primary channel
  - Note: `multicast_dns` has no server-side registration API yet

### Step 5 — Data: Discovery Service (Riverpod)
- [x] `lib/features/discovery/data/discovery_service.dart`
  - `AsyncNotifier<Map<String, Device>>` — `discoveryServiceProvider`
  - Loads `uuid` + `displayName` from `FlutterSecureStorage`
  - Gets local IP from `NetworkInfo.getWifiIP()`
  - Starts `DeviceRegistry`, `UdpBroadcastService`, `MdnsService`
  - Auto-disposes on ref.onDispose

### Step 6 — Presentation: Home Screen
- [x] `lib/features/discovery/presentation/home_screen.dart`
  - `StreamBuilder` via `ref.watch(discoveryServiceProvider)`
  - `_DeviceCard`: avatar, name, IP, status chip, call/video action buttons
  - "THIS DEVICE" badge on self
  - Pulsing "Scanning" indicator in AppBar
  - Empty state, loading (rotating gradient), error view
  - FAB with cyan→purple gradient

### Step 7 — Router
- [x] `lib/core/router/app_router.dart`
  - Splash (`/`) redirects to Home (`/home`)
  - Home route uses `HomeScreen()`

---

## 🧪 Acceptance Criteria

- [x] Own device appears immediately with "THIS DEVICE" badge
- [x] Other devices appear within 5 seconds of launch
- [x] Devices disappear within 10 seconds of closing the app
- [x] Device status is displayed correctly
- [x] Works without internet (LAN only)
- [ ] Test: Android → Android on same subnet
- [x] Test: Linux → Android on same subnet

---

## 📦 Required Packages

```yaml
multicast_dns: ^0.3.2+3
network_info_plus: ^6.1.4
flutter_secure_storage: ^9.2.4
uuid: ^4.5.1
flutter_riverpod: ^2.6.1
```

---

## 🏗️ Architecture Notes

- **Primary transport:** UDP Broadcast on port 45678
- **Secondary transport:** mDNS (`_wasla._tcp.local`) — discovery only
- **Announcement interval:** 5 seconds
- **Eviction timeout:** 10 seconds after `lastSeen`
- **State management:** Riverpod `AsyncNotifier` — single source of truth
- **Self device** is always pinned at the top of the list
