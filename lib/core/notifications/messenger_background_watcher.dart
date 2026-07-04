import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../auth/auth_repository.dart';
import '../messaging/messaging_repository.dart';
import '../notifications/messenger_notification_service.dart';
import '../preferences/messenger_preferences.dart';

/// Polls for new messages when app is backgrounded; shows local notifications (mobile only).
class MessengerBackgroundWatcher {
  Timer? _timer;
  final Map<int, int> _lastMessageIdByConversation = {};

  void start(BuildContext context) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick(context));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(BuildContext context) async {
    if (!context.mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.paused && lifecycle != AppLifecycleState.inactive) return;

    final auth = context.read<AuthRepository>();
    if (!auth.isAuthenticated) return;
    final prefs = context.read<MessengerPreferences>();
    if (!prefs.pushNotificationsEnabled) return;

    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    try {
      final conversations = await repo.fetchConversations();
      for (final c in conversations) {
        if (!prefs.shouldNotifyForConversation(c.id)) continue;
        if (c.unreadCount <= 0) continue;
        final messages = await repo.fetchMessages(c.id);
        if (messages.isEmpty) continue;
        final latest = messages.first;
        final prev = _lastMessageIdByConversation[c.id];
        if (prev != null && latest.id <= prev) continue;
        _lastMessageIdByConversation[c.id] = latest.id;
        if (prev == null) continue;
        final preview = latest.body.isNotEmpty ? latest.body : '[${latest.type}]';
        await MessengerNotificationService.instance.showMessageNotification(
          id: c.id,
          title: c.title,
          body: preview,
        );
      }
    } catch (_) {}
  }

  void seedFromMessages(int conversationId, int messageId) {
    final prev = _lastMessageIdByConversation[conversationId];
    if (prev == null || messageId > prev) {
      _lastMessageIdByConversation[conversationId] = messageId;
    }
  }
}
