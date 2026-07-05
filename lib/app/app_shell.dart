import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import '../core/notifications/messenger_notification_service.dart';
import '../core/calls/call_session_controller.dart';
import '../core/calls/incoming_call_watcher.dart';
import '../core/models/api_models.dart';
import '../core/notifications/messenger_background_watcher.dart';
import '../widgets/incoming_call_banner.dart';
import '../widgets/incoming_call_overlay.dart';
import '../features/login/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/conversations/conversations_screen.dart';
import '../features/calls/call_screen.dart';
import '../widgets/minimized_call_bar.dart';

class MessengerHome extends StatefulWidget {
  const MessengerHome({super.key});

  @override
  State<MessengerHome> createState() => _MessengerHomeState();
}

class _MessengerHomeState extends State<MessengerHome> {
  ConversationSummary? _selected;
  final _backgroundWatcher = MessengerBackgroundWatcher();
  final _incomingCallWatcher = IncomingCallWatcher();
  bool _recovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverCallState());
  }

  Future<void> _recoverCallState() async {
    if (_recovered || !mounted) return;
    _recovered = true;
    await MessengerNotificationService.instance.clearAllCallNotifications();
    await context.read<CallSessionController>().recoverAfterLaunch();
  }

  void _openChat(ConversationSummary conversation) {
    setState(() => _selected = conversation);
  }

  void _closeChat() {
    setState(() => _selected = null);
  }

  void _expandCall() {
    final call = context.read<CallSessionController>();
    call.expand();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CallScreen()));
  }

  @override
  void dispose() {
    _backgroundWatcher.stop();
    _incomingCallWatcher.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _backgroundWatcher.start(context);
    _incomingCallWatcher.start(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    Widget body;
    if (isWide) {
      body = Row(
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
    } else if (_selected != null) {
      body = ChatScreen(
        conversation: _selected!,
        onBack: _closeChat,
      );
    } else {
      body = ConversationsScreen(onSelect: _openChat);
    }

    return PopScope(
      canPop: _selected == null || isWide,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected != null && !isWide) _closeChat();
      },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(child: body),
              MinimizedCallBar(onExpand: _expandCall),
            ],
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IncomingCallBanner(),
          ),
          const Positioned.fill(
            child: IncomingCallOverlay(),
          ),
        ],
      ),
    );
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AuthRepository>().refreshSession(logoutOnFailure: true);
      unawaited(MessengerNotificationService.instance.clearAllCallNotifications());
      unawaited(context.read<CallSessionController>().recoverAfterLaunch());
    }
  }

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
