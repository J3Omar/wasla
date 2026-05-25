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
        return _PlaceholderScreen(label: 'Chat — $deviceId');
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
