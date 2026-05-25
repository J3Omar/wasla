import 'package:go_router/go_router.dart';
import 'package:wasla/features/discovery/presentation/home_screen.dart';

import 'package:flutter/material.dart';

/// Route name constants — use these instead of raw strings
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String chat = '/chat/:deviceId';
  static const String incomingCall = '/call/incoming';
  static const String outgoingCall = '/call/outgoing';
  static const String voiceCall = '/call/voice/:deviceId';
  static const String videoCall = '/call/video/:deviceId';
  static const String settings = '/settings';
}

/// App router — screens are added as features are implemented
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      redirect: (context, state) => AppRoutes.home,
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) =>
          const _PlaceholderScreen(label: 'Onboarding'),
    ),
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.chat,
      name: 'chat',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        return _ChatPlaceholder(deviceId: deviceId);
      },
    ),
    GoRoute(
      path: AppRoutes.incomingCall,
      name: 'incoming-call',
      builder: (context, state) =>
          const _PlaceholderScreen(label: 'Incoming Call'),
    ),
    GoRoute(
      path: AppRoutes.outgoingCall,
      name: 'outgoing-call',
      builder: (context, state) =>
          const _PlaceholderScreen(label: 'Outgoing Call'),
    ),
    GoRoute(
      path: AppRoutes.voiceCall,
      name: 'voice-call',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        return _PlaceholderScreen(label: 'Voice Call — $deviceId');
      },
    ),
    GoRoute(
      path: AppRoutes.videoCall,
      name: 'video-call',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        return _PlaceholderScreen(label: 'Video Call — $deviceId');
      },
    ),
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

/// Chat placeholder — shows device ID and a "coming soon" state
class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2022),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFFE2E2E5)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat',
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE2E2E5),
              ),
            ),
            Text(
              deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                color: const Color(0xFF00DBE7),
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: const Color(0xFF849495).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Chat Page',
              style: TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE2E2E5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon — this feature\nis under development',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: const Color(0xFFB9CACB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

