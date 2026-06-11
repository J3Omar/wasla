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

    debugPrint(
      '[LinuxAudioService] Attempting to load virtual sink module-null-sink...',
    );

    try {
      final result = await Process.run('pactl', [
        'load-module',
        'module-null-sink',
        'sink_name=WaslaAudio',
        'sink_properties=device.description="Wasla_System_Audio"',
      ]);

      if (result.exitCode != 0 || result.stderr.toString().isNotEmpty) {
        debugPrint(
          '[LinuxAudioService] Failed to load virtual sink. Exit Code: ${result.exitCode}',
        );
        debugPrint('[LinuxAudioService] Stderr: ${result.stderr}');
        return;
      }

      // The pactl command returns the loaded module ID as a string on stdout
      final output = result.stdout.toString().trim();

      if (output.isNotEmpty) {
        _nullSinkId = output;
        debugPrint(
          '[LinuxAudioService] Successfully loaded virtual sink. Module ID: $_nullSinkId',
        );
      } else {
        debugPrint(
          '[LinuxAudioService] Command succeeded but returned an empty Module ID.',
        );
      }
    } catch (e) {
      debugPrint(
        '[LinuxAudioService] Exception occurred while loading virtual sink: $e',
      );
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

    debugPrint(
      '[LinuxAudioService] Attempting to unload virtual sink with Module ID: $_nullSinkId',
    );

    try {
      final result = await Process.run('pactl', [
        'unload-module',
        _nullSinkId!,
      ]);

      if (result.exitCode != 0 || result.stderr.toString().isNotEmpty) {
        debugPrint(
          '[LinuxAudioService] Failed to unload virtual sink. Exit Code: ${result.exitCode}',
        );
        debugPrint('[LinuxAudioService] Stderr: ${result.stderr}');
        // We do not clear _nullSinkId here so that retry logic could potentially be implemented,
        // or we at least acknowledge it failed to unload.
        return;
      }

      debugPrint(
        '[LinuxAudioService] Successfully unloaded virtual sink Module ID: $_nullSinkId',
      );
      _nullSinkId = null;
    } catch (e) {
      debugPrint(
        '[LinuxAudioService] Exception occurred while unloading virtual sink: $e',
      );
    }
  }
}
