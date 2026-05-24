# Feature: Device Discovery

---

## 🎯 Goal
Every device running the app announces itself on the LAN. Other devices discover it within 5 seconds.

---

## ✅ Prerequisites

- [ ] **Onboarding complete** — `uuid` and `displayName` must be stored
- [ ] Dependencies in `pubspec.yaml`:
  ```yaml
  multicast_dns: ^0.3.x
  network_info_plus: ^6.x.x
  ```
- [ ] Android Manifest permissions:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
  ```

---

## 📝 User Stories

- [ ] As a user, I want to see all devices running the app on my network
- [ ] As a user, I want to see each device's name and status (available / in call)
- [ ] As a user, I want the list to update automatically

---

## 🔧 Coding Checklist

### Step 1 — Domain: Device Model
- [ ] Create `lib/features/discovery/domain/device_model.dart`
  ```dart
  class Device {
    final String uuid;
    final String displayName;
    final String localIp;
    final DeviceStatus status;
    final DateTime lastSeen;
  }
  enum DeviceStatus { available, inCall, busy }
  ```

### Step 2 — Data: mDNS Service
- [ ] Create `lib/features/discovery/data/mdns_service.dart`
  - `startAnnouncing()` — broadcast every 5 seconds
  - `startDiscovery()` — listen for other devices
  - `stopAll()`

### Step 3 — Data: UDP Broadcast (Fallback)
- [ ] Create `lib/features/discovery/data/udp_broadcast_service.dart`
  - Fallback if mDNS fails — sends UDP broadcast on port 45678

### Step 4 — Data: Device Registry
- [ ] Create `lib/features/discovery/data/device_registry.dart`
  - `Map<String, Device>` — active devices indexed by UUID
  - Timer removes devices with `lastSeen > 10s`

### Step 5 — Presentation: Home Screen
- [ ] Create `lib/features/discovery/presentation/home_screen.dart`
  - `StreamBuilder` displaying device list
  - `DeviceCard` component with 4 states: Active Self / Busy / Idle / Offline
  - Bottom Nav Bar (4 tabs)
  - FAB (Cyan → Purple gradient)

---

## 🧪 Acceptance Criteria

- [ ] Devices appear within 5 seconds of launch
- [ ] Devices disappear within 10 seconds of closing the app
- [ ] Device status is displayed correctly
- [ ] Own device shows "THIS DEVICE" badge
- [ ] Works without internet

---

## 📦 Required Packages

```yaml
multicast_dns: ^0.3.2+3
network_info_plus: ^6.1.4
```
