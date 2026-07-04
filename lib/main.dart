import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_shell.dart';
import 'core/auth/auth_repository.dart';
import 'theme/messenger_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ErpMessengerApp());
}

class ErpMessengerApp extends StatelessWidget {
  const ErpMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthRepository()..bootstrap(),
      child: MaterialApp(
        title: 'ERPComplete Messenger',
        theme: buildMessengerTheme(),
        darkTheme: buildMessengerTheme(brightness: Brightness.dark),
        themeMode: ThemeMode.system,
        home: const AppShell(),
      ),
    );
  }
}
