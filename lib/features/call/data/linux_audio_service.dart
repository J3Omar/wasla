import 'dart:io';
import 'package:flutter/foundation.dart';

class LinuxAudioService {
  static final LinuxAudioService _instance = LinuxAudioService._internal();
  factory LinuxAudioService() => _instance;
  LinuxAudioService._internal();

  String? _originalDefaultSource;
  static const _recoveryFile = '/tmp/wasla_audio_recovery.txt';

  Future<void> enableSystemAudioCapture() async {
    if (!Platform.isLinux) return;

    try {
      // 1. Save original physical mic (ensure we don't save a monitor by mistake)
      final result = await Process.run('pactl', ['get-default-source']);
      final original = result.stdout.toString().trim();

      if (!original.contains('.monitor')) {
        _originalDefaultSource = original;
        await File(_recoveryFile).writeAsString(original);
        debugPrint(
          '[LinuxAudioService] Saved original physical mic: $original',
        );
      }

      // 2. Find the actual hardware output (Speakers)
      final sinkResult = await Process.run('sh', [
        '-c',
        'pactl info | grep "Default Sink" | cut -d":" -f2',
      ]);
      final defaultSink = sinkResult.stdout.toString().trim();

      if (defaultSink.isNotEmpty) {
        final monitorSource = '$defaultSink.monitor';
        debugPrint(
          '[LinuxAudioService] Found hardware monitor: $monitorSource',
        );

        // 3. Set the speaker's monitor as the default input source
        await Process.run('pactl', ['set-default-source', monitorSource]);
        debugPrint(
          '[LinuxAudioService] System audio natively routed to input.',
        );
      }
    } catch (e) {
      debugPrint('[LinuxAudioService] Error: $e');
    }
  }

  Future<void> disableSystemAudioCapture() async {
    if (!Platform.isLinux) return;

    try {
      String? source = _originalDefaultSource;
      if (source == null || source.isEmpty) {
        final f = File(_recoveryFile);
        if (await f.exists()) {
          source = (await f.readAsString()).trim();
        }
      }
      if (source != null && source.isNotEmpty) {
        await Process.run('pactl', ['set-default-source', source]);
        debugPrint(
          '[LinuxAudioService] Restored original physical mic: $source',
        );
        _originalDefaultSource = null;
        final f = File(_recoveryFile);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[LinuxAudioService] Exception during cleanup: $e');
    }
  }

  /// Checks if the current default source is a monitor (broken state from crash).
  /// If so, restores from recovery file or resets to first physical mic found.
  Future<void> restoreIfBroken() async {
    try {
      final result = await Process.run('pactl', ['get-default-source']);
      final current = result.stdout.toString().trim();

      // If current source is a monitor, the mic is broken — fix it
      if (current.contains('.monitor')) {
        debugPrint(
          '[LinuxAudioService] Broken mic detected on call start: $current',
        );

        // Try recovery file first
        final f = File(_recoveryFile);
        if (await f.exists()) {
          final saved = (await f.readAsString()).trim();
          if (saved.isNotEmpty && !saved.contains('.monitor')) {
            await Process.run('pactl', ['set-default-source', saved]);
            await f.delete();
            _originalDefaultSource = null;
            debugPrint(
              '[LinuxAudioService] Auto-restored from recovery file: $saved',
            );
            return;
          }
        }

        // Fallback: find first physical mic from pactl list
        final list = await Process.run('pactl', ['list', 'short', 'sources']);
        final lines = list.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('alsa_input') && !line.contains('.monitor')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length > 1) {
              final micName = parts[1];
              await Process.run('pactl', ['set-default-source', micName]);
              debugPrint(
                '[LinuxAudioService] Auto-restored to physical mic: $micName',
              );
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LinuxAudioService] restoreIfBroken error: $e');
    }
  }
}
