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
}
