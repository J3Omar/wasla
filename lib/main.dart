import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/chat/data/chat_database.dart';

import 'features/file_sharing/data/file_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ChatDatabase.instance.open();
    await FileStorageService.instance.requestStoragePermission();
  } catch (e) {
    debugPrint('CRITICAL: Failed to open ChatDatabase or request permissions: $e');
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
