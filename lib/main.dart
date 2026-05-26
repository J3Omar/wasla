import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/chat/data/chat_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatDatabase.instance.open();
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
