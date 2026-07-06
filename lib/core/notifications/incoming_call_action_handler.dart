import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../calls/call_screen_navigator.dart';
import '../calls/incoming_call_actions.dart';
import '../auth/auth_repository.dart';
import '../calls/call_session_controller.dart';
import '../calls/incoming_call_controller.dart';
import '../messaging/messaging_repository.dart';
import '../models/api_models.dart';
import 'messenger_notification_service.dart';

/// Handles accept / decline from system incoming-call notifications.
class IncomingCallActionHandler {
  IncomingCallActionHandler._();

  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> handlePayload({
    required String? actionId,
    required String? payload,
  }) async {
    if (payload == null || payload.isEmpty) return;
    final data = MessengerNotificationService.decodeIncomingCallPayload(payload);
    if (data == null) return;

    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    final context = nav.context;
    if (!context.mounted) return;

    final auth = context.read<AuthRepository>();
    if (!auth.isAuthenticated) return;

    final conversationId = data['conversation_id'] as int?;
    final messageId = data['message_id'] as int?;
    if (conversationId == null || messageId == null) return;

    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);

    ConversationSummary? conv;
    ChatMessage? msg;
    try {
      final conversations = await repo.fetchConversations(bypassThrottle: true);
      for (final c in conversations) {
        if (c.id == conversationId) {
          conv = c;
          break;
        }
      }
      final messages = await repo.fetchMessages(conversationId, bypassThrottle: true);
      for (final m in messages) {
        if (m.id == messageId) {
          msg = m;
          break;
        }
      }
    } catch (_) {
      return;
    }

    if (conv == null || msg == null) return;
    if (!context.mounted) return;

    final invite = IncomingCallInvite(conversation: conv, message: msg);
    final resolvedAction = actionId ?? MessengerNotificationService.actionAccept;

    if (resolvedAction == MessengerNotificationService.actionDecline) {
      await IncomingCallActions.decline(context, invite);
      return;
    }

    if (resolvedAction == MessengerNotificationService.actionAccept) {
      await IncomingCallActions.accept(context, invite);
    }
  }

  /// Re-open call UI when user taps the ongoing-call notification.
  static Future<void> handleOngoingCallTap() async {
    final nav = navigatorKey?.currentState;
    if (nav == null || !nav.mounted) return;
    final context = nav.context;
    final call = context.read<CallSessionController>();
    if (!call.isActive || call.conversation == null) {
      await MessengerNotificationService.instance.clearAllCallNotifications();
      await call.forceReset();
      return;
    }
    call.expand();
    await CallScreenNavigator.open();
  }
}
