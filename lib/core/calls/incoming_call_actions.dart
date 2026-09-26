import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../messaging/messaging_repository.dart';
import '../notifications/incoming_call_action_handler.dart';
import '../notifications/messenger_notification_service.dart';
import 'call_screen_navigator.dart';
import 'call_session_controller.dart';
import 'incoming_call_controller.dart';
import 'incoming_call_ringtone.dart';

/// Shared accept / decline handlers for banner, overlay, and notification actions.
class IncomingCallActions {
  IncomingCallActions._();

  static Future<void> decline(BuildContext context, IncomingCallInvite invite) async {
    unawaited(IncomingCallRingtone.stop());
    unawaited(MessengerNotificationService.instance.clearIncomingCallNotification());

    // Resolve everything from [context] up front: clearing the invite removes the banner
    // that usually owns it, so it may be unmounted once the awaits below return.
    final incoming = context.read<IncomingCallController>();
    final auth = context.read<AuthRepository>();
    final messenger = _messengerFor(context);
    incoming.clear(messageId: invite.message.id, handled: true);

    try {
      final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
      await CallSessionController.declineCallInvite(
        repo: repo,
        conversationId: invite.conversation.id,
        callMessage: invite.message,
      );
    } catch (e) {
      _snack(messenger, formatApiError(e));
    }
  }

  static Future<void> accept(BuildContext context, IncomingCallInvite invite) async {
    unawaited(IncomingCallRingtone.stop());
    unawaited(MessengerNotificationService.instance.clearIncomingCallNotification());

    // Resolve everything from [context] up front (see [decline]).
    final incoming = context.read<IncomingCallController>();
    final call = context.read<CallSessionController>();
    final auth = context.read<AuthRepository>();
    final messenger = _messengerFor(context);
    incoming.clear(messageId: invite.message.id, handled: true);

    if (call.isActive && CallScreenNavigator.isOpen) {
      return;
    }
    if (call.isActive) {
      await call.forceReset();
    }

    // Show call UI immediately; connect in the background (do not await push — it lasts until hang up).
    if (!CallScreenNavigator.isOpen) {
      // open() prefers the app navigator; the context is only a fallback.
      unawaited(CallScreenNavigator.open(context.mounted ? context : null));
    }

    if (!auth.isAuthenticated) {
      CallScreenNavigator.popIfOpen();
      return;
    }
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);

    try {
      await call.answerIncoming(
        conv: invite.conversation,
        messagingRepo: repo,
        callerName: invite.callerName,
        callMessage: invite.message,
        video: invite.isVideo,
      );
      if (!call.active) {
        CallScreenNavigator.popIfOpen();
      }
    } catch (e) {
      await call.forceReset();
      CallScreenNavigator.popIfOpen();
      _snack(messenger, formatApiError(e));
    }
  }

  /// The app-level messenger when available, otherwise the caller's — resolved before any await.
  static ScaffoldMessengerState? _messengerFor(BuildContext context) {
    final nav = IncomingCallActionHandler.navigatorKey?.currentState;
    final ctx = (nav?.mounted == true) ? nav!.context : context;
    return ScaffoldMessenger.maybeOf(ctx);
  }

  static void _snack(ScaffoldMessengerState? messenger, String message) {
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
