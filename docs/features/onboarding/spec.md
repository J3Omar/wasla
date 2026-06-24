# Feature Specification: Cryptographic Onboarding & Identity

## 🎯 Objective
Bootstrap the application instance by securely generating a unique cryptographic identity (`UUID v4`) bound to a user-defined Display Name, ensuring zero-setup peer-to-peer routing without cloud registration.

## 🏗️ Architectural Specifications

### 1. Identity Generation & Persistence (`DeviceStorageRepository`)
- **Generation:** Utilizes `uuid` package to generate a collision-resistant v4 UUID upon first launch.
- **Storage Strategy:** Hardware-backed secure persistence via `flutter_secure_storage`.
  - Android: `EncryptedSharedPreferences` / `Android Keystore`
  - Windows: `DPAPI`
  - Linux: `libsecret`
- **State Properties:**
  - `deviceId` (UUID string)
  - `deviceName` (String: 2–30 chars)
  - `isOnboardingDone` (Boolean flag)

### 2. State Management (`DeviceInfoProvider`)
- Centralized via Riverpod `AsyncNotifier<DeviceInfoState>`.
- The `SplashScreen` acts as an interceptor. It awaits the resolution of the `deviceInfoProvider`.
  - If `isOnboardingDone == true` -> Routes to `/home`.
  - If `isOnboardingDone == false` -> Routes to `/onboarding`.

### 3. Application Assets
- Desktop icons compiled directly via OS-native pipelines (`linux/runner/my_application.cc` for GTK, `.ico` for Windows).

## 🧪 Acceptance Criteria
- [x] Initial boot triggers the asynchronous identity generation workflow.
- [x] Name constraints strictly enforced (2-30 bounds) to prevent UDP packet overflow during Discovery broadcasts.
- [x] Subsequent launches immediately bootstrap to the Discovery Engine without rendering the onboarding UI.
