import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import '../core/messaging/messaging_repository.dart';
import '../core/notifications/messenger_notification_service.dart';
import '../core/calls/call_screen_navigator.dart';
import '../core/calls/call_session_controller.dart';
import '../core/calls/incoming_call_watcher.dart';
import '../core/models/api_models.dart';
import '../core/notifications/messenger_background_watcher.dart';
import '../widgets/background_reliability_prompt.dart';
import '../widgets/incoming_call_banner.dart';
import '../widgets/incoming_call_overlay.dart';
import '../features/login/login_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/conversations/conversations_screen.dart';
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
    final auth = context.read<AuthRepository>();
    await auth.refreshSession(logoutOnFailure: false);
    if (!mounted || !auth.isAuthenticated) return;
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    final name = auth.userName ?? 'User';
    await context.read<CallSessionController>().recoverAfterLaunch(
          messagingRepo: repo,
          callerName: name,
          coldStart: true,
        );
    final call = context.read<CallSessionController>();
    if (!mounted || !call.active || call.conversation == null) return;
    if (call.connected || call.connecting || call.needsRejoin) {
      await CallScreenNavigator.open(context);
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) BackgroundReliabilityPrompt.maybeShow(context);
      });
    }
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
    unawaited(CallScreenNavigator.open(context));
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
    if (!mounted) return;
    final call = context.read<CallSessionController>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(call.persistIfActive());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    if (!mounted) return;
    final auth = context.read<AuthRepository>();
    await auth.refreshSession(logoutOnFailure: false);
    if (!mounted || !auth.isAuthenticated) return;
    unawaited(MessengerNotificationService.instance.clearAllCallNotifications());
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    await context.read<CallSessionController>().recoverAfterLaunch(
          messagingRepo: repo,
          callerName: auth.userName ?? 'User',
          coldStart: false,
        );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BackgroundReliabilityPrompt.maybeShow(context);
    });
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
