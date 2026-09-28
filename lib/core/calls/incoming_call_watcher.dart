import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../api/api_throttle_guard.dart';
import '../auth/auth_repository.dart';
import '../messaging/messaging_broadcast_service.dart';
import '../messaging/messaging_repository.dart';
import '../models/api_models.dart';
import '../notifications/incoming_call_action_handler.dart';
import '../notifications/messenger_notification_service.dart';
import 'call_session_controller.dart';
import 'incoming_call_controller.dart';
import 'incoming_call_ringtone.dart';

/// Incoming calls via Reverb; light polling only when WebSocket is down.
class IncomingCallWatcher {
  StreamSubscription<MessagingBroadcastEvent>? _broadcastSub;
  Timer? _fallbackTimer;
  bool _busy = false;
  int? _lastNotifiedMessageId;
  bool _started = false;

  void start(BuildContext context) {
    if (_started) return;
    _started = true;

    final auth = context.read<AuthRepository>();
    final broadcast = context.read<MessagingBroadcastService>();
    unawaited(broadcast.connect(auth));

    _broadcastSub?.cancel();
    _broadcastSub = broadcast.events.listen(_onBroadcastEvent);

    _fallbackTimer?.cancel();
    // Poll only when the WebSocket is down. 15s (not 4s) + throttle-guard
    // respect keeps light usage from tripping server rate limits.
    _fallbackTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fallbackPoll());
    Future.microtask(_fallbackPoll);
  }

  void stop() {
    _started = false;
    _broadcastSub?.cancel();
    _broadcastSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  BuildContext? get _context => IncomingCallActionHandler.navigatorKey?.currentContext;

  Future<void> _onBroadcastEvent(MessagingBroadcastEvent event) async {
    final context = _context;
    if (context == null || !context.mounted) return;

    if (event.eventName == 'messaging.call') {
      await _handleCallSignal(context, event);
      return;
    }

    if (event.eventName == 'message.sent' || event.eventName == 'message.updated') {
      final data = event.data;
      if ((data['type'] as String?) != 'call') return;
      final auth = context.read<AuthRepository>();
      final uid = auth.userId ?? 0;
      final message = ChatMessage.fromJson(data, uid);
      await _handleRingingMessage(context, event.conversationId, message);
    }
  }

  Future<void> _fallbackPoll() async {
    final context = _context;
    if (context == null || !context.mounted || _busy) return;
    if (ApiThrottleGuard.instance.isBlocked) return;

    final broadcast = context.read<MessagingBroadcastService>();
    if (broadcast.isConnected) return;

    final auth = context.read<AuthRepository>();
    if (!auth.isAuthenticated) return;

    _busy = true;
    try {
      await _scanForRingingCalls(context);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> _scanForRingingCalls(BuildContext context) async {
    final auth = context.read<AuthRepository>();
    final callSession = context.read<CallSessionController>();
    if (callSession.isActive && callSession.connected) return;

    final incoming = context.read<IncomingCallController>();
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    final conversations = await repo.fetchConversations();
    if (!context.mounted) return;

    context.read<MessagingBroadcastService>().syncConversations(conversations);

    final callConversations = conversations
        .where((c) => !c.isArchived && c.lastMessageType == 'call')
        .take(3)
        .toList();

    IncomingCallInvite? ringing;
    for (final conv in callConversations) {
      final messages = await repo.fetchMessages(conv.id);
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
      _presentInviteSync(context, ringing);
      return;
    }

    await _verifyAndClearRinging(context, incoming, repo);
  }

  Future<void> _handleCallSignal(BuildContext context, MessagingBroadcastEvent event) async {
    final action = event.data['action'] as String? ?? '';
    final auth = context.read<AuthRepository>();
    final fromUserId = event.data['from_user_id'] as int? ?? event.data['caller_id'] as int?;
    final callSession = context.read<CallSessionController>();
    final incoming = context.read<IncomingCallController>();
    final sessionId = event.data['call_session_id'] as String? ?? '';

    if (action == 'ended' || action == 'declined' || action == 'cancelled' || action == 'rejected') {
      if (sessionId.isNotEmpty &&
          callSession.isActive &&
          callSession.sessionId == sessionId) {
        await callSession.applyRemoteEnded(
          durationSeconds: event.data['duration_seconds'] as int?,
        );
      }
      final messageId = event.data['message_id'] as int?;
      if (messageId != null && incoming.pending?.message.id == messageId) {
        _lastNotifiedMessageId = null;
        await IncomingCallRingtone.stop();
        await MessengerNotificationService.instance.clearIncomingCallNotification();
        incoming.clear(messageId: messageId, handled: true);
      }
      return;
    }

    if (action == 'answered' || action == 'active') {
      // Answered on another device of the same user (e.g. the web): stop ringing here.
      final messageId = event.data['message_id'] as int?;
      final answeredHere = callSession.isActive && callSession.sessionId == sessionId;
      if (action == 'answered' &&
          fromUserId != null &&
          fromUserId == auth.userId &&
          !answeredHere &&
          messageId != null &&
          incoming.pending?.message.id == messageId) {
        _lastNotifiedMessageId = null;
        await IncomingCallRingtone.stop();
        await MessengerNotificationService.instance.clearIncomingCallNotification();
        incoming.clear(messageId: messageId, handled: true);
      }
      return;
    }

    if (action != 'invite' && action != 'ringing') return;
    if (fromUserId != null && fromUserId == auth.userId) return;

    final messageId = event.data['message_id'] as int?;
    if (messageId == null) return;

    if (sessionId.isNotEmpty) {
      await callSession.prepareForIncomingInvite(sessionId);
    }
    if (!context.mounted) return;
    if (callSession.isActive && callSession.connected) return;

    final callKind = event.data['call_kind'] as String? ??
        ((event.data['body'] as String? ?? '').toLowerCase().contains('video') ? 'video' : 'voice');

    final message = ChatMessage(
      id: messageId,
      body: event.data['body'] as String? ?? (callKind == 'video' ? 'Video call' : 'Voice call'),
      senderName: event.data['from_user_name'] as String? ??
          event.data['caller_name'] as String? ??
          'Caller',
      senderId: fromUserId ?? 0,
      isSent: false,
      type: 'call',
      attachments: [
        if (sessionId.isNotEmpty)
          {
            'call_session_id': sessionId,
            'room_name': event.data['room_name'],
            'phase': 'ringing',
            'call_kind': callKind,
          },
      ],
    );
    if (!_isRingingIncoming(message)) return;

    final title = context.read<MessagingBroadcastService>().conversationTitle(event.conversationId) ??
        message.senderName;
    _presentInviteSync(
      context,
      IncomingCallInvite(
        conversation: ConversationSummary(id: event.conversationId, title: title),
        message: message,
      ),
    );
  }

  Future<void> _handleRingingMessage(
    BuildContext context,
    int conversationId,
    ChatMessage message,
  ) async {
    if (!_isRingingIncoming(message)) {
      await _verifyClearIfNeeded(context, conversationId, message);
      return;
    }

    final callSession = context.read<CallSessionController>();
    final sessionId = message.callMeta?.callSessionId ?? '';
    if (sessionId.isNotEmpty) {
      await callSession.prepareForIncomingInvite(sessionId);
    }
    if (!context.mounted) return;
    if (callSession.isActive && callSession.connected) return;

    final title = context.read<MessagingBroadcastService>().conversationTitle(conversationId) ??
        message.senderName;
    _presentInviteSync(
      context,
      IncomingCallInvite(
        conversation: ConversationSummary(
          id: conversationId,
          title: title.isNotEmpty ? title : 'Call',
        ),
        message: message,
      ),
    );
  }

  void _presentInviteSync(BuildContext context, IncomingCallInvite invite) {
    final incoming = context.read<IncomingCallController>();
    if (!incoming.shouldNotifyForMessage(invite.message.id)) return;

    incoming.show(invite);
    unawaited(IncomingCallRingtone.start());
    if (_lastNotifiedMessageId != invite.message.id) {
      _lastNotifiedMessageId = invite.message.id;
      unawaited(
        MessengerNotificationService.instance.showIncomingCallNotification(
          conversationId: invite.conversation.id,
          messageId: invite.message.id,
          callerName: invite.callerName,
          isVideo: invite.isVideo,
        ),
      );
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
      final messages = await repo.fetchMessages(pending.conversation.id);
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

  Future<void> _verifyClearIfNeeded(
    BuildContext context,
    int conversationId,
    ChatMessage message,
  ) async {
    final incoming = context.read<IncomingCallController>();
    final pending = incoming.pending;
    if (pending == null || pending.message.id != message.id) return;
    if (_isRingingIncoming(message)) return;

    _lastNotifiedMessageId = null;
    await IncomingCallRingtone.stop();
    await MessengerNotificationService.instance.clearIncomingCallNotification();
    incoming.clear(messageId: message.id, handled: true);
  }

  bool _isRingingIncoming(ChatMessage m) {
    if (m.type != 'call' || m.isSent) return false;
    final phase = m.callMeta?.phase;
    return phase == 'ringing' || phase == null;
  }
}
