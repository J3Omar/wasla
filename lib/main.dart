import 'dart:io';
import 'package:wasla/features/call/data/linux_audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wasla/features/call/data/call_manager.dart';
import 'package:wasla/features/file_sharing/data/file_transfer_service.dart';

bool hasActiveOperation() {
  return (CallManager.instance?.isInCall ?? false) ||
      FileTransferService.instance.hasActiveTransfers;
}

class AppWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (hasActiveOperation()) {
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Active call or transfer in progress"),
            content: const Text(
              "Closing the app now will end your call or interrupt a file transfer. Are you sure you want to exit?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  windowManager.destroy();
                },
                child: const Text("Exit anyway"),
              ),
            ],
          ),
        );
        return;
      }
    }
    // No active operation, or no context to show dialog: close immediately
    await windowManager.destroy();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    windowManager.addListener(AppWindowListener());
    await windowManager.setPreventClose(true);
  }

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
