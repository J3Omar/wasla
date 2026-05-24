# Feature: Onboarding

---

## 🎯 Goal
First launch: user enters a device display name → app generates a UUID → navigates to Home Screen.  
On subsequent launches: skip onboarding, go straight to Home.

---

## ✅ Prerequisites

- [ ] Dependencies in `pubspec.yaml`:
  ```yaml
  flutter_secure_storage: ^9.x.x
  go_router: ^14.x.x
  uuid: ^4.x.x
  ```
- [ ] Theme set up in `lib/core/theme/`
- [ ] Router set up in `lib/core/router/app_router.dart`

---

## 📝 User Stories

- [ ] As a new user, I want to enter just my name and start immediately — no account creation
- [ ] As an app, I must generate a unique UUID per device and store it securely
- [ ] As a returning user, I should skip onboarding automatically

---

## 🔧 Coding Checklist

### Step 1 — Data Layer
- [ ] Create `lib/features/onboarding/data/device_storage.dart`
  - `saveDeviceName(String name)`
  - `getDeviceName()` → `String?`
  - `getOrCreateUUID()` → generates UUID if not found, stores it
  - `isOnboardingDone()` → `bool`

### Step 2 — Domain Layer
- [ ] Create `lib/features/onboarding/domain/device_info.dart`
  ```dart
  class DeviceInfo {
    final String uuid;
    final String displayName;
  }
  ```

### Step 3 — Splash Screen
- [ ] Create `lib/features/onboarding/presentation/splash_screen.dart`
  - Background `#121416` + glow effects
  - Wasla logo centered
  - Progress bar gradient (Cyan → Purple)
  - After 2–3s: check onboarding status → route to Home or Onboarding

### Step 4 — Onboarding Screen
- [ ] Create `lib/features/onboarding/presentation/onboarding_screen.dart`
  - TextField for device name (validation: 2–30 characters)
  - "Start" button → saves name + UUID → navigates to Home

### Step 5 — Router
- [ ] Wire routes:
  ```
  / → SplashScreen
  /onboarding → OnboardingScreen
  /home → HomeScreen
  ```

---

## 🧪 Acceptance Criteria

- [ ] Onboarding screen only appears on first launch
- [ ] Name must be 2–30 characters
- [ ] UUID is generated and stored securely
- [ ] Subsequent launches skip onboarding
- [ ] Works on Android, Windows, and Linux

---

## 📦 Required Packages

```yaml
flutter_secure_storage: ^9.2.4
go_router: ^14.6.2
uuid: ^4.5.1
```
