import 'dart:io';
import 'package:wasla/features/call/data/linux_audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Failsafe: Ensure Linux audio is cleaned up if the app is force-killed
  if (Platform.isLinux) {
    try {
      final recoveryFile = File('/tmp/wasla_audio_recovery.txt');
      if (await recoveryFile.exists()) {
        final savedSource = (await recoveryFile.readAsString()).trim();
        if (savedSource.isNotEmpty) {
          await Process.run('pactl', ['set-default-source', savedSource]);
          await recoveryFile.delete();
          debugPrint(
            '[LinuxAudio] Startup recovery: restored mic to $savedSource',
          );
        }
      }
    } catch (_) {}
    ProcessSignal.sigint.watch().listen((signal) async {
      debugPrint('[Main] SIGINT received. Cleaning up Linux Audio...');
      await LinuxAudioService().disableSystemAudioCapture();
      exit(0);
    });
    ProcessSignal.sigterm.watch().listen((signal) async {
      debugPrint('[Main] SIGTERM received. Cleaning up Linux Audio...');
      await LinuxAudioService().disableSystemAudioCapture();
      exit(0);
    });
  }

  runApp(const ProviderScope(child: WaslaApp()));
}

class WaslaApp extends StatelessWidget {
  const WaslaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Wasla',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
