import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../auth/auth_repository.dart';
import '../messaging/messaging_repository.dart';
import '../models/api_models.dart';
import '../notifications/messenger_notification_service.dart';
import 'call_session_controller.dart';
import 'incoming_call_controller.dart';
import 'incoming_call_ringtone.dart';

/// Polls for ringing incoming calls (bypasses API throttle backoff).
class IncomingCallWatcher {
  Timer? _timer;
  bool _busy = false;
  int? _lastNotifiedMessageId;

  void start(BuildContext context) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick(context));
    Future.microtask(() => _tick(context));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(BuildContext context) async {
    if (_busy || !context.mounted) return;

    final auth = context.read<AuthRepository>();
    if (!auth.isAuthenticated) return;

    final callSession = context.read<CallSessionController>();
    if (callSession.isActive || callSession.isRecovering) {
      if (callSession.isRecovering ||
          callSession.connecting ||
          callSession.needsRejoin ||
          callSession.connected ||
          callSession.liveKitRoom != null) {
        context.read<IncomingCallController>().clear(handled: false);
        await IncomingCallRingtone.stop();
        await MessengerNotificationService.instance.clearIncomingCallNotification();
        return;
      }
      await callSession.forceReset();
    }

    final incoming = context.read<IncomingCallController>();
    _busy = true;
    try {
      final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
      final conversations = await repo.fetchConversations(bypassThrottle: true);
      if (!context.mounted) return;

      final callConversations = conversations
          .where((c) => !c.isArchived && c.lastMessageType == 'call')
          .toList();
      final unreadConversations = conversations
          .where((c) => !c.isArchived && c.unreadCount > 0 && c.lastMessageType != 'call')
          .toList();

      IncomingCallInvite? ringing;
      for (final conv in [...callConversations, ...unreadConversations]) {
        final messages = await repo.fetchMessages(conv.id, bypassThrottle: true);
        for (final m in messages.take(8)) {
          if (!_isRingingIncoming(m)) continue;
          if (!incoming.shouldNotifyForMessage(m.id)) continue;
          ringing = IncomingCallInvite(conversation: conv, message: m);
          break;
        }
        if (ringing != null) break;
      }

      if (!context.mounted) return;

      if (ringing != null) {
        incoming.show(ringing);
        await IncomingCallRingtone.start();
        if (_lastNotifiedMessageId != ringing.message.id) {
          _lastNotifiedMessageId = ringing.message.id;
          await MessengerNotificationService.instance.showIncomingCallNotification(
            conversationId: ringing.conversation.id,
            messageId: ringing.message.id,
            callerName: ringing.callerName,
            isVideo: ringing.isVideo,
          );
        }
        return;
      }

      await _verifyAndClearRinging(context, incoming, repo);
    } catch (_) {
      // Keep any pending invite visible if poll fails (rate limit, network).
    } finally {
      _busy = false;
    }
  }

  Future<void> _verifyAndClearRinging(
    BuildContext context,
    IncomingCallController incoming,
    MessagingRepository repo,
  ) async {
    final pending = incoming.pending;
    if (pending == null) {
      _lastNotifiedMessageId = null;
      await IncomingCallRingtone.stop();
      await MessengerNotificationService.instance.clearIncomingCallNotification();
      return;
    }

    try {
      final messages = await repo.fetchMessages(pending.conversation.id, bypassThrottle: true);
      for (final m in messages) {
        if (m.id == pending.message.id && _isRingingIncoming(m)) {
          return;
        }
      }
    } catch (_) {
      return;
    }

    _lastNotifiedMessageId = null;
    await IncomingCallRingtone.stop();
    await MessengerNotificationService.instance.clearIncomingCallNotification();
    incoming.clear(messageId: pending.message.id, handled: true);
  }

  bool _isRingingIncoming(ChatMessage m) {
    if (m.type != 'call' || m.isSent) return false;
    final phase = m.callMeta?.phase;
    return phase == 'ringing' || phase == null;
  }
}
