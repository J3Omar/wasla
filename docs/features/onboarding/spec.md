# Feature: Onboarding

---

## 🎯 Goal

First launch: user enters a device display name → app generates a UUID → navigates to Home Screen.
On subsequent launches: skip onboarding, go straight to Home.

---

## ✅ Prerequisites

- [x] Dependencies in `pubspec.yaml`:
  ```yaml
  flutter_secure_storage: ^9.2.4
  go_router: ^14.6.2
  uuid: ^4.5.1
  flutter_riverpod: ^2.6.1
  google_fonts: ^6.2.1
  ```
- [x] Theme set up in `lib/core/theme/`
- [x] Router set up in `lib/core/router/app_router.dart`

---

## 📝 User Stories

- [x] As a new user, I want to enter just my name and start immediately — no account creation
- [x] As an app, I must generate a unique UUID per device and store it securely
- [x] As a returning user, I should skip onboarding automatically

---

## 🔧 Coding Checklist

### Step 1 — Data Layer
- [x] `lib/features/onboarding/data/device_storage_repository.dart`
  - `saveDeviceName(String name)`
  - `getDeviceName()` → `String?`
  - `getOrCreateUUID()` → generates UUID v4 if not found, stores it securely
  - `setOnboardingDone()` → marks first run complete
  - `isOnboardingDone()` → `bool`

### Step 2 — Domain Layer
- [x] `lib/features/onboarding/domain/device_info_provider.dart`
  - `DeviceInfoState` holds `deviceId`, `deviceName`, `isOnboardingDone`
  - `DeviceInfoNotifier extends AsyncNotifier<DeviceInfoState>`
  - `completeOnboarding(String name)` → saves name, sets flag, updates state
  - Providers: `secureStorageProvider`, `deviceStorageProvider`, `deviceInfoProvider`

### Step 3 — Splash Screen
- [x] `lib/features/onboarding/presentation/splash_screen.dart`
  - Background `#121416` + animated radial cyan/purple glow
  - Glassmorphic logo card (200×200) with `CustomPainter` Wasla logo
  - Gradient progress bar + `ESTABLISHING MESH...` caps label
  - After 2.6s: reads `deviceInfoProvider` → routes to `/home` or `/onboarding`

### Step 4 — Onboarding Screen
- [x] `lib/features/onboarding/presentation/onboarding_screen.dart`
  - Gradient "وصلة Wasla" heading with `ShaderMask`
  - Dual radial glow background (cyan top-left, purple bottom-right)
  - TextField: device name, validation 2–30 characters
  - Full-width gradient CTA button with loading spinner
  - On submit → `completeOnboarding()` → navigate to `/home`

### Step 5 — Router
- [x] `lib/core/router/app_router.dart` wired:
  ```
  /           → SplashScreen
  /onboarding → OnboardingScreen
  /home       → HomeScreen (Discovery feature)
  ```

### Step 6 — App Icons
- [x] Android icons generated via `flutter_launcher_icons`
- [x] Windows `.ico` generated via `flutter_launcher_icons`
- [x] Web icons generated via `flutter_launcher_icons`
- [x] Linux icon set programmatically in `linux/runner/my_application.cc`

---

## 🧪 Acceptance Criteria

- [x] Splash screen appears on every launch
- [x] Onboarding screen only shows on first launch
- [x] Name validated: must be 2–30 characters
- [x] UUID is generated and stored securely via `flutter_secure_storage`
- [x] Subsequent launches skip directly to Home
- [x] Tested on Android
- [x] Tested on Linux

---

## 📦 Required Packages

```yaml
flutter_secure_storage: ^9.2.4
go_router: ^14.6.2
uuid: ^4.5.1
flutter_riverpod: ^2.6.1
google_fonts: ^6.2.1
flutter_launcher_icons: ^0.13.1   # dev_dependency
```

---

## 🎨 Design Notes

- All colors from `AppColors` (Kinetic Ether system)
- All text styles from `AppTypography` (Hanken Grotesk headings, Inter body, Space Grotesk labels)
- Splash: `RadialGradient` glow, glassmorphic card, `LinearProgressIndicator` with cyan fill
- Onboarding: `ShaderMask` with `primaryGradient` on heading, full-width gradient CTA with cyan shadow
