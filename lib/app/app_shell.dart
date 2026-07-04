import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import '../core/models/api_models.dart';
import '../features/login/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/conversations/conversations_screen.dart';

class MessengerHome extends StatefulWidget {
  const MessengerHome({super.key});

  @override
  State<MessengerHome> createState() => _MessengerHomeState();
}

class _MessengerHomeState extends State<MessengerHome> {
  ConversationSummary? _selected;

  void _openChat(ConversationSummary conversation) {
    setState(() => _selected = conversation);
  }

  void _closeChat() {
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    if (isWide) {
      return Row(
        children: [
          SizedBox(
            width: 360,
            child: ConversationsScreen(
              selectedId: _selected?.id,
              onSelect: _openChat,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? const _EmptyChatPane()
                : ChatScreen(
                    key: ValueKey(_selected!.id),
                    conversation: _selected!,
                  ),
          ),
        ],
      );
    }

    if (_selected != null) {
      return ChatScreen(
        conversation: _selected!,
        onBack: _closeChat,
      );
    }

    return ConversationsScreen(onSelect: _openChat);
  }
}

class _EmptyChatPane extends StatelessWidget {
  const _EmptyChatPane();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Select a conversation to start messaging',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

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
        return const MessengerHome();
      },
    );
  }
}
