import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_shell.dart';
import 'core/auth/auth_repository.dart';

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          useMaterial3: true,
        ),
        home: const AppShell(),
      ),
    );
  }
}
