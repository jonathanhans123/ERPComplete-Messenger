import 'package:flutter/foundation.dart';

import '../messaging/messaging_repository.dart';
import '../models/api_models.dart';
import '../../features/conversations/conversation_actions.dart';

/// Keeps an active call alive while user navigates chat (minimized bar).
class CallSessionController extends ChangeNotifier {
  ConversationSummary? conversation;
  MessagingRepository? repo;
  String displayName = 'User';
  bool isVideo = false;
  bool active = false;
  bool minimized = false;
  bool connecting = false;
  bool connected = false;
  String? error;
  bool muted = false;
  bool cameraOff = false;
  LiveCallToken? token;
  String? room;
  String? sessionId;

  bool get isActive => active;

  Future<void> start({
    required ConversationSummary conv,
    required MessagingRepository messagingRepo,
    required String callerName,
    required bool video,
  }) async {
    conversation = conv;
    repo = messagingRepo;
    displayName = callerName;
    isVideo = video;
    active = true;
    minimized = false;
    connecting = true;
    connected = false;
    error = null;
    muted = false;
    cameraOff = false;
    token = null;
    sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    room = ConversationActions.callRoomName(conv.id);
    notifyListeners();
    await _connect();
  }

  Future<void> retryConnection() => _connect();

  Future<void> _connect() async {
    final r = repo;
    final conv = conversation;
    final callRoom = room;
    final sid = sessionId;
    if (r == null || conv == null || callRoom == null || sid == null) return;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final t = await r.liveCallToken(room: callRoom, displayName: displayName);
      await r.sendCallSignal(
        conversationId: conv.id,
        action: 'active',
        callSessionId: sid,
        roomName: callRoom,
      );
      token = t;
      connected = true;
    } catch (e) {
      error = e.toString();
      connected = false;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void minimize() {
    if (!active) return;
    minimized = true;
    notifyListeners();
  }

  void expand() {
    minimized = false;
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    notifyListeners();
  }

  Future<void> end() async {
    final r = repo;
    final conv = conversation;
    final callRoom = room;
    final sid = sessionId;
    if (r != null && conv != null && callRoom != null && sid != null) {
      try {
        await r.sendCallSignal(
          conversationId: conv.id,
          action: 'ended',
          callSessionId: sid,
          roomName: callRoom,
        );
      } catch (_) {}
    }
    active = false;
    minimized = false;
    connecting = false;
    connected = false;
    conversation = null;
    repo = null;
    token = null;
    room = null;
    sessionId = null;
    error = null;
    notifyListeners();
  }
}
