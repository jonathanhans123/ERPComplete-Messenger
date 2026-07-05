import 'package:flutter/foundation.dart';

import '../models/api_models.dart';

class IncomingCallInvite {
  IncomingCallInvite({required this.conversation, required this.message});

  final ConversationSummary conversation;
  final ChatMessage message;

  bool get isVideo => message.callMeta?.isVideo ?? false;
  String get callerName => message.senderName.isNotEmpty ? message.senderName : conversation.title;
}

/// Tracks a ringing call invite shown in the top banner (app-wide).
class IncomingCallController extends ChangeNotifier {
  IncomingCallInvite? _pending;
  final Set<int> _handledMessageIds = {};

  IncomingCallInvite? get pending => _pending;

  bool get hasPending => _pending != null;

  bool shouldNotifyForMessage(int messageId) => !_handledMessageIds.contains(messageId);

  void show(IncomingCallInvite invite) {
    if (_pending?.message.id == invite.message.id) return;
    if (_handledMessageIds.contains(invite.message.id)) return;
    _pending = invite;
    notifyListeners();
  }

  void clear({int? messageId, bool handled = false}) {
    if (messageId != null && handled) {
      _handledMessageIds.add(messageId);
    }
    if (_pending == null) return;
    if (messageId != null && _pending!.message.id != messageId) return;
    _pending = null;
    notifyListeners();
  }

  void resetHandled() {
    _handledMessageIds.clear();
    _pending = null;
    notifyListeners();
  }
}
