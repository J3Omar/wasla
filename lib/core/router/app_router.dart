import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:wasla/features/setup/presentation/splash_screen.dart';
import 'package:wasla/features/setup/presentation/setup_name_screen.dart';
import 'package:wasla/features/shell/presentation/main_shell.dart';
import 'package:wasla/features/chat/presentation/chat_screen.dart';

/// Route name constants — use these instead of raw strings
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String chat = '/chat/:deviceId';
  static const String settings = '/settings';
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
        // peerName and isOnline passed as extras from push callers
        final extra = state.extra as Map<String, dynamic>?;
        final peerName = extra?['peerName'] as String? ?? deviceId;
        final isOnline = extra?['isOnline'] as bool? ?? false;
        return ChatScreen(
          peerUuid: deviceId,
          peerName: peerName,
          isOnline: isOnline,
        );
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
