/// Wasla — App Configuration Constants
abstract final class AppConfig {
  // ── App Info ───────────────────────────────────────────────────────────────
  static const String appName = 'Wasla';
  static const String appVersion = '0.1.0';

  // ── Secure Storage Keys ────────────────────────────────────────────────────
  static const String keyDeviceUUID = 'device_uuid';
  static const String keyDeviceName = 'device_name';
  static const String keyOnboardingDone = 'onboarding_done';

  // ── Device Discovery ───────────────────────────────────────────────────────
  static const String mdnsServiceType = '_wasla._tcp';
  static const int udpBroadcastPort = 45678;
  static const Duration announcementInterval = Duration(seconds: 5);
  static const Duration deviceTimeout = Duration(seconds: 10);

  // ── Signaling ─────────────────────────────────────────────────────────────
  /// Port range for the local WebSocket signaling server (caller picks one)
  static const int signalingPortMin = 8760;
  static const int signalingPortMax = 8780;

  // ── WebRTC ────────────────────────────────────────────────────────────────
  static const Map<String, dynamic> rtcConfiguration = {
    'iceServers': [], // LAN only — no STUN/TURN needed
    'iceCandidatePoolSize': 5,
  };

  static const Map<String, dynamic> videoConstraints = {
    'video': {
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
      'frameRate': {'ideal': 30},
    },
  };

  static const Map<String, dynamic> audioConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
  };

  // ── File Transfer ─────────────────────────────────────────────────────────
  /// WebRTC Data Channel max chunk size
  static const int fileChunkSize = 16 * 1024; // 16 KB
  static const String filesSaveFolder = 'Wasla';

  // ── Call Behaviour ────────────────────────────────────────────────────────
  static const int maxDeclineCount = 3;
  static const Duration callSetupTimeout = Duration(seconds: 15);

  // ── Onboarding ────────────────────────────────────────────────────────────
  static const int deviceNameMinLength = 2;
  static const int deviceNameMaxLength = 30;
}
