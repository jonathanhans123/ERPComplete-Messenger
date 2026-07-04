import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import 'conversations/conversations_screen.dart';
import 'login/login_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthRepository>(
      builder: (context, auth, _) {
        if (!auth.isReady) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }
        return const ConversationsScreen();
      },
    );
  }
}
