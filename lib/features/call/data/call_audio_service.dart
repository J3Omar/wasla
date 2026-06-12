import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Singleton audio service for all call and notification sounds.
///
/// Correct OS audio streams per sound:
///   • Ringtone  → [AndroidUsageType.notificationRingtone]
///                 Respects system ring volume AND silent/vibrate mode.
///   • Ringback  → [AndroidUsageType.voiceCommunication]
///                 Uses voice call volume — appropriate for outgoing tone.
///   • End sound → [AndroidUsageType.voiceCommunication]
///                 Short chime on the same voice stream so volume is consistent.
///   • Notification → [AndroidUsageType.notification]
///                 Respects notification volume independently of ring volume.
///
/// Two separate [AudioPlayer] instances are kept:
///   [_callPlayer]  — handles ringtone / ringback / end-chime (sequential,
///                    never overlapping).
///   [_notifPlayer] — handles general app notification sounds (may fire
///                    while a call is active without interrupting it).
class CallAudioService {
  CallAudioService._();

  /// Singleton instance — safe to access from any isolate-free context.
  static final instance = CallAudioService._();

  final AudioPlayer _callPlayer = AudioPlayer();
  final AudioPlayer _notifPlayer = AudioPlayer();
  final AudioPlayer _reconnectPlayer = AudioPlayer();
  Timer? _reconnectTimer;

  // ── AudioContext helpers ───────────────────────────────────────────────────

  /// Build a platform-aware [AudioContext] for the given Android usage type.
  AudioContext _ctx(AndroidUsageType androidUsage) => AudioContext(
    android: AudioContextAndroid(
      usageType: androidUsage,
      // contentType: speech for voice streams, music for ringtone/notif
      contentType: (androidUsage == AndroidUsageType.voiceCommunication)
          ? AndroidContentType.speech
          : AndroidContentType.music,
      audioFocus: androidUsage == AndroidUsageType.voiceCommunication
          ? AndroidAudioFocus.gain
          : AndroidAudioFocus.none,
      stayAwake: false,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
  );

  // ── Public API ────────────────────────────────────────────────────────────

  // Set to false to bypass all audio (used during WebRTC crash isolation testing)
  final bool _isAudioEnabled = true;

  /// Loop the incoming ringtone.
  /// Uses [AndroidUsageType.notificationRingtone] → respects silent/vibrate.
  Future<void> playRingtone() async {
    if (!_isAudioEnabled) return;
    debugPrint('[CallAudioService] playRingtone invoked');
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _callPlayer.setAudioContext(
          _ctx(AndroidUsageType.notificationRingtone),
        );
      }
      await _callPlayer.setReleaseMode(ReleaseMode.loop);
      debugPrint(
        '[CallAudioService] playRingtone: context and release mode set, playing asset...',
      );
      await _callPlayer.play(AssetSource('audio/ringtone.mp3'));
      debugPrint('[CallAudioService] playRingtone: playback started');
    } catch (e, stack) {
      debugPrint('[CallAudioService] playRingtone error: $e\n$stack');
    }
  }

  /// Loop the outgoing ringback tone.
  /// Uses [AndroidUsageType.voiceCommunication] → voice call volume stream.
  Future<void> playRingback() async {
    if (!_isAudioEnabled) return;
    debugPrint('[CallAudioService] playRingback invoked');
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _callPlayer.setAudioContext(
          _ctx(AndroidUsageType.voiceCommunication),
        );
      }
      await _callPlayer.setReleaseMode(ReleaseMode.loop);
      debugPrint(
        '[CallAudioService] playRingback: context and release mode set, playing asset...',
      );
      await _callPlayer.play(AssetSource('audio/ringback.mp3'));
      debugPrint('[CallAudioService] playRingback: playback started');
    } catch (e, stack) {
      debugPrint('[CallAudioService] playRingback error: $e\n$stack');
    }
  }

  void playReconnecting() {
    debugPrint('[CallAudio] playReconnecting invoked');
    if (!_isAudioEnabled) return;
    _reconnectTimer?.cancel();
    _reconnectPlayer.stop();

    Future<void> playOnce() async {
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          await _reconnectPlayer.setAudioContext(
            _ctx(AndroidUsageType.voiceCommunication),
          );
        }
        await _reconnectPlayer.setReleaseMode(ReleaseMode.release);
        await _reconnectPlayer.play(AssetSource('audio/reconnecting.mp3'));
      } catch (e) {
        debugPrint('[CallAudio] playReconnecting error: $e');
      }
    }

    playOnce();
    _reconnectPlayer.onPlayerComplete.listen((_) {
      _reconnectTimer = Timer(const Duration(milliseconds: 600), playOnce);
    });
  }

  /// Stop all looping call audio immediately.
  /// Idempotent — safe to call multiple times.
  void stopReconnecting() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectPlayer.stop();
  }

  /// Stop all looping call audio immediately.
  /// Idempotent — safe to call multiple times.
  Future<void> stopAll() async {
    if (!_isAudioEnabled) return;
    try {
      await _callPlayer.stop();
    } catch (_) {}
  }

  /// Release the AudioPlayer's audio focus so WebRTC can take full
  /// control of the Android AudioManager without a routing collision.
  /// Must be awaited BEFORE calling getUserMedia().
  Future<void> releaseAudioFocus() async {
    try {
      await _callPlayer.stop();
      await _callPlayer.release();
    } catch (_) {}
  }

  /// Play the short call-ended chime (non-looping).
  /// Always call [stopAll] first to clear any looping sound.
  Future<void> playEndSound() async {
    if (!_isAudioEnabled) return;
    debugPrint('[CallAudioService] playEndSound invoked');
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _callPlayer.setAudioContext(
          _ctx(AndroidUsageType.voiceCommunication),
        );
      }
      // ReleaseMode.release — player releases resources after playback naturally
      // completes, so the chime is never truncated mid-play.
      await _callPlayer.setReleaseMode(ReleaseMode.release);
      debugPrint(
        '[CallAudioService] playEndSound: context and release mode set, playing asset...',
      );
      await _callPlayer.play(AssetSource('audio/call_end.mp3'));
      debugPrint('[CallAudioService] playEndSound: playback started');
    } catch (e, stack) {
      debugPrint('[CallAudioService] playEndSound error: $e\n$stack');
    }
  }

  /// Play a one-shot general notification sound.
  /// Uses [AndroidUsageType.notification] → notification volume stream.
  /// Uses a separate player so it never interrupts call audio.
  Future<void> playNotification() async {
    if (!_isAudioEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _notifPlayer.setAudioContext(_ctx(AndroidUsageType.notification));
      }
      await _notifPlayer.setReleaseMode(ReleaseMode.stop);
      await _notifPlayer.stop();
      await _notifPlayer.play(AssetSource('audio/notification.mp3'));
    } catch (e) {
      debugPrint('[CallAudio] playNotification error: $e');
    }
  }

  /// Play a short sound when the user successfully sends a chat message.
  /// Uses [AndroidUsageType.notification] → respects notification volume.
  Future<void> playMessageSent() async {
    if (!_isAudioEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _notifPlayer.setAudioContext(_ctx(AndroidUsageType.notification));
      }
      await _notifPlayer.setReleaseMode(ReleaseMode.stop);
      await _notifPlayer.stop(); // Clean cut off for rapid fire
      await _notifPlayer.play(AssetSource('audio/sent.mp3'));
    } catch (e) {
      debugPrint('[CallAudio] playMessageSent error: $e');
    }
  }

  /// Play a short sound when a new chat message is received while in-app.
  /// Uses [AndroidUsageType.notification] → respects notification volume.
  Future<void> playMessageReceived() async {
    if (!_isAudioEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _notifPlayer.setAudioContext(_ctx(AndroidUsageType.notification));
      }
      await _notifPlayer.setReleaseMode(ReleaseMode.stop);
      await _notifPlayer.stop(); // Clean cut off for rapid fire
      await _notifPlayer.play(AssetSource('audio/received.mp3'));
    } catch (e) {
      debugPrint('[CallAudio] playMessageReceived error: $e');
    }
  }

  /// Release both players. Call only on app exit.
  Future<void> dispose() async {
    await _callPlayer.dispose();
    await _notifPlayer.dispose();
    await _reconnectPlayer.dispose();
  }
}
