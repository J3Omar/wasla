# ROADMAP — Native Hardware Integrations

> Strategic planning for future Wasla updates, focusing on OS-level hardware optimizations.

---

## 1. Linux Audio Routing & Virtual Loopback
**Target Architecture:** Linux (PulseAudio / PipeWire)

Currently, Linux display servers (specifically Wayland) often reject strict audio constraints during WebRTC `getDisplayMedia` calls. Our current mitigation is a graceful `audio: false` fallback. The roadmap plan involves intercepting system audio directly via the OS sound daemon.

### Implementation Strategy
- Use Dart's `Process.run()` to execute system-level audio commands.
- **PulseAudio/PipeWire Commands:**
  - Create a virtual audio sink: `pactl load-module module-null-sink sink_name=wasla_loopback`
  - Mix the system audio monitor and the microphone input into this virtual sink.
  - Instruct `flutter_webrtc` to capture from the `wasla_loopback.monitor` interface instead of the default microphone.
- **Teardown:** Ensure the `module-null-sink` is cleanly unloaded when the application exits or the screen share stops.

---

## 2. Android Native Audio Capture
**Target Architecture:** Android 10+ (API 29+)

Android restricts internal audio capture (loopback) due to DRM and privacy concerns. Standard WebRTC `getDisplayMedia` on Android captures the screen but not the internal device audio cleanly without root.

### Implementation Strategy
- **AudioPlaybackCapture API:** Implement Android's native `AudioPlaybackCaptureConfiguration` in Kotlin/Java.
- **MethodChannel Integration:** Create a bidirectional Flutter `MethodChannel` (`com.wasla/audio_capture`).
- **PCM Byte Streaming:** The Kotlin backend will continuously read raw PCM audio bytes from the system bus and stream them over the `EventChannel` to Dart.
- **WebRTC Custom Track:** Feed the incoming PCM bytes into a custom WebRTC `AudioTrack` source to multiplex with the video stream.

---

## 3. Secure Vault Database
**Target Architecture:** Cross-Platform

Presently, Chat histories and peer identities are secured, but we want to elevate the security to enterprise-grade cold storage for long-term persistence across app re-installs.

### Implementation Strategy
- **AES-256 Encryption:** Implement a localized vault using AES-256-GCM.
- **Hardware Keystore:** Store the master decryption key in the OS hardware element (Android Keystore / Apple Secure Enclave / Windows TPM).
- **Biometric Authentication:** Introduce `local_auth` to require fingerprint or face unlock before the SQLite database decrypts and mounts into memory, ensuring physical device theft does not compromise chat history.
