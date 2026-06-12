import 'dart:io';
import 'package:flutter/foundation.dart';

/// A singleton service responsible for managing Linux system audio routing.
///
/// This service interfaces with PulseAudio/PipeWire via the `pactl` CLI utility
/// to create and destroy virtual audio sinks (module-null-sink). This allows
/// the application to capture system audio on Linux environments during screen sharing
/// by providing a dedicated loopback monitor interface.
class LinuxAudioService {
  // Singleton pattern implementation
  static final LinuxAudioService _instance = LinuxAudioService._internal();
  factory LinuxAudioService() => _instance;
  LinuxAudioService._internal();

  /// Stores the Module ID returned by PulseAudio when the virtual sink is loaded.
  /// Used to uniquely identify and destroy the sink when the stream ends.
  String? _nullSinkId;
  String? _loopbackId;
  String? _micLoopbackId;
  String? _originalDefaultSource;

  /// Retrieves the current loaded sink ID. Null if no sink is active.
  String? get currentSinkId => _nullSinkId;

  /// Attempts to load a virtual audio sink using `pactl`.
  ///
  /// The sink is named `WaslaAudio` with the description `Wasla_System_Audio`.
  /// If successful, the module ID is parsed from stdout and stored in `_nullSinkId`.
  Future<void> enableSystemAudioCapture() async {
    if (!Platform.isLinux) {
      debugPrint('[LinuxAudioService] Aborting: OS is not Linux.');
      return;
    }

    if (_nullSinkId != null) {
      debugPrint(
        '[LinuxAudioService] Virtual sink already loaded with ID: $_nullSinkId',
      );
      return;
    }

    try {
      final defaultSourceResult = await Process.run('sh', [
        '-c',
        'pactl info | grep "Default Source" | cut -d":" -f2',
      ]);
      final currentSource = defaultSourceResult.stdout.toString().trim();

      // CRITICAL: NEVER save our own virtual sink as the original source.
      // If it's already WaslaAudio.monitor, we ignore it to preserve the REAL physical mic saved earlier.
      if (!currentSource.contains('WaslaAudio')) {
        _originalDefaultSource = currentSource;
        debugPrint(
          '[LinuxAudioService] Saved original default source: $_originalDefaultSource',
        );
      } else {
        debugPrint(
          '[LinuxAudioService] Warning: Default source is already WaslaAudio. Keeping previous backup.',
        );
      }

      debugPrint(
        '[LinuxAudioService] Attempting to load virtual sink module-null-sink...',
      );

      // 1. Create the Null Sink with STRICT WebRTC compatible formatting (s16le, 48kHz, stereo)
      final sinkResult = await Process.run('pactl', [
        'load-module',
        'module-null-sink',
        'sink_name=WaslaAudio',
        'format=s16le', // Strict 16-bit encoding to stop crackle
        'rate=48000',
        'channels=2',
        'sink_properties=device.description="Wasla_System_Audio"',
      ]);
      _nullSinkId = sinkResult.stdout.toString().trim();
      debugPrint(
        '[LinuxAudioService] Loaded virtual sink. Module ID: $_nullSinkId',
      );

      // 2. Route default system output to WaslaAudio with strict latency
      final loopbackResult = await Process.run('pactl', [
        'load-module',
        'module-loopback',
        'sink=WaslaAudio',
        'latency_msec=30', // Buffer padding to prevent underrun crackles
      ]);
      _loopbackId = loopbackResult.stdout.toString().trim();
      debugPrint(
        '[LinuxAudioService] Loaded system audio loopback. Module ID: $_loopbackId',
      );

      // 3. Route the microphone to WaslaAudio
      final micLoopbackResult = await Process.run('pactl', [
        'load-module',
        'module-loopback',
        'sink=WaslaAudio',
        'latency_msec=30',
      ]);
      _micLoopbackId = micLoopbackResult.stdout.toString().trim();
      debugPrint(
        '[LinuxAudioService] Loaded microphone loopback. Module ID: $_micLoopbackId',
      );
    } catch (e) {
      debugPrint('[LinuxAudioService] Error enabling system audio capture: $e');
    }
  }

  /// Unloads the virtual audio sink if it was previously created.
  ///
  /// Uses the stored `_nullSinkId` to cleanly destroy the module via `pactl`.
  Future<void> disableSystemAudioCapture() async {
    if (!Platform.isLinux) {
      return;
    }

    if (_nullSinkId == null) {
      debugPrint('[LinuxAudioService] No active virtual sink to unload.');
      return;
    }

    try {
      if (_micLoopbackId != null) {
        await Process.run('pactl', ['unload-module', _micLoopbackId!]);
        debugPrint(
          '[LinuxAudioService] Unloaded mic loopback: $_micLoopbackId',
        );
        _micLoopbackId = null;
      }

      if (_loopbackId != null) {
        await Process.run('pactl', ['unload-module', _loopbackId!]);
        debugPrint(
          '[LinuxAudioService] Unloaded system loopback: $_loopbackId',
        );
        _loopbackId = null;
      }

      await Process.run('pactl', ['unload-module', _nullSinkId!]);
      debugPrint('[LinuxAudioService] Unloaded virtual sink: $_nullSinkId');
      _nullSinkId = null;

      if (_originalDefaultSource != null &&
          _originalDefaultSource!.isNotEmpty &&
          !_originalDefaultSource!.contains('WaslaAudio')) {
        await Process.run('pactl', [
          'set-default-source',
          _originalDefaultSource!,
        ]);
        debugPrint(
          '[LinuxAudioService] Restored original default source: $_originalDefaultSource',
        );
        _originalDefaultSource = null;
      }
    } catch (e) {
      debugPrint(
        '[LinuxAudioService] Exception occurred while unloading audio modules: $e',
      );
    }
  }
}
