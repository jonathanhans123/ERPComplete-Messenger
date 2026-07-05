import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../messaging/messaging_repository.dart';
import '../notifications/incoming_call_action_handler.dart';
import '../notifications/messenger_notification_service.dart';
import 'call_session_controller.dart';
import 'incoming_call_controller.dart';
import 'incoming_call_ringtone.dart';
import '../../features/calls/call_screen.dart';

/// Shared accept / decline handlers for banner, overlay, and notification actions.
class IncomingCallActions {
  IncomingCallActions._();

  static Future<void> decline(BuildContext context, IncomingCallInvite invite) async {
    unawaited(IncomingCallRingtone.stop());
    unawaited(MessengerNotificationService.instance.clearIncomingCallNotification());

    final incoming = context.read<IncomingCallController>();
    incoming.clear(messageId: invite.message.id, handled: true);

    try {
      final auth = context.read<AuthRepository>();
      final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
      await CallSessionController.declineCallInvite(
        repo: repo,
        conversationId: invite.conversation.id,
        callMessage: invite.message,
      );
    } catch (e) {
      _snack(context, formatApiError(e));
    }
  }

  static Future<void> accept(BuildContext context, IncomingCallInvite invite) async {
    unawaited(IncomingCallRingtone.stop());
    unawaited(MessengerNotificationService.instance.clearIncomingCallNotification());

    final incoming = context.read<IncomingCallController>();
    incoming.clear(messageId: invite.message.id, handled: true);

    final call = context.read<CallSessionController>();
    if (call.isActive) {
      await call.forceReset();
    }

    final auth = context.read<AuthRepository>();
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);

    try {
      await call.answerIncoming(
        conv: invite.conversation,
        messagingRepo: repo,
        callerName: invite.callerName,
        callMessage: invite.message,
        video: invite.isVideo,
      );
      if (!call.active) return;

      final nav = IncomingCallActionHandler.navigatorKey?.currentState;
      if (nav != null && nav.mounted) {
        await nav.push(MaterialPageRoute(builder: (_) => const CallScreen()));
        return;
      }
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
      }
    } catch (e) {
      await call.forceReset();
      _snack(context, formatApiError(e));
    }
  }

  static void _snack(BuildContext context, String message) {
    final nav = IncomingCallActionHandler.navigatorKey?.currentState;
    final ctx = (nav?.mounted == true) ? nav!.context : context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }
}
