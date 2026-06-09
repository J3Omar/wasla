import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:wasla/features/setup/presentation/splash_screen.dart';
import 'package:wasla/features/setup/presentation/setup_name_screen.dart';
import 'package:wasla/features/setup/presentation/battery_prompt_screen.dart';
import 'package:wasla/features/shell/presentation/main_shell.dart';
import 'package:wasla/features/chat/presentation/chat_screen.dart';
import 'package:wasla/features/discovery/domain/device_model.dart';
import 'package:wasla/features/call/presentation/incoming_call_screen.dart';
import 'package:wasla/features/call/presentation/outgoing_call_screen.dart';
import 'package:wasla/features/call/presentation/call_screen.dart';

/// Route name constants — use these instead of raw strings
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String batteryPrompt = '/battery-prompt';
  static const String home = '/home';
  static const String chat = '/chat/:deviceId';
  static const String settings = '/settings';
  static const String callOutgoing = '/call/outgoing';
  static const String callIncoming = '/call/incoming';
  static const String callActive = '/call/active';
}

/// App router — screens are added as features are implemented
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  routes: [
    // ── Splash ──────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),

    // ── Setup / Onboarding ──────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const SetupNameScreen(),
    ),
    GoRoute(
      path: AppRoutes.batteryPrompt,
      name: 'batteryPrompt',
      builder: (context, state) => const BatteryPromptScreen(),
    ),

    // ── Main shell (Devices / Chats / Profile) ───────────────────────────
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const MainShell(),
    ),

    // ── Chat screen ───────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.chat,
      name: 'chat',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        final device = state.extra as Device?;
        return ChatScreen(deviceId: deviceId, device: device);
      },
    ),

    // ── Voice Call screens ───────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.callOutgoing,
      name: 'callOutgoing',
      builder: (context, state) => const OutgoingCallScreen(),
    ),
    GoRoute(
      path: AppRoutes.callIncoming,
      name: 'callIncoming',
      builder: (context, state) {
        Map<String, dynamic> extra = {};
        if (state.extra is Map<String, dynamic>) {
          extra = state.extra as Map<String, dynamic>;
        } else if (state.extra is String) {
          try {
            extra = jsonDecode(state.extra as String) as Map<String, dynamic>;
          } catch (_) {}
        }

        return IncomingCallScreen(
          callerId: (extra['callerId'] as String?) ?? '',
          callerName: (extra['callerName'] as String?) ?? 'Unknown',
          callerIp: (extra['callerIp'] as String?) ?? '',
          signalingPort: (extra['signalingPort'] as int?) ?? 0,
          isVideo: (extra['isVideo'] as bool?) ?? false,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.callActive,
      name: 'callActive',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final peerName = extra?['peerName'] as String? ?? '';
        return CallScreen(peerName: peerName);
      },
    ),

    // ── Settings placeholder ──────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const _PlaceholderScreen(label: 'Settings'),
    ),
  ],
);

/// Temporary placeholder — replaced as each screen is built
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(label, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}
