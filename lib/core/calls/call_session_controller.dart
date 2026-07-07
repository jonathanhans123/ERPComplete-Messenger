import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' hide ChatMessage;
import 'package:uuid/uuid.dart';

import '../messaging/messaging_repository.dart';
import '../models/api_models.dart';
import 'call_session_storage.dart';

/// Keeps an active call alive while user navigates chat (minimized bar).
class CallSessionController extends ChangeNotifier {
  static const ringTimeoutSeconds = 45;

  ConversationSummary? conversation;
  MessagingRepository? repo;
  String displayName = 'User';
  bool isVideo = false;
  bool active = false;
  bool minimized = false;
  bool connecting = false;
  bool connected = false;
  String? error;
  String? statusMessage;
  bool muted = false;
  bool cameraOff = false;
  /// `false` = earpiece (normal/phone-to-ear), `true` = loudspeaker.
  bool loudspeakerOn = false;
  LiveCallToken? token;
  String? room;
  String? sessionId;
  int? messageId;
  Room? _room;
  DateTime? _connectedAt;
  bool _remoteEverConnected = false;
  bool _activeSignalSent = false;
  bool _isOutgoing = false;
  bool _callWasAnswered = false;
  bool _ringTimeoutTriggered = false;
  bool _ending = false;
  bool _autoEnding = false;
  bool _recovering = false;
  DateTime? _rejoinGraceUntil;
  int _connectEpoch = 0;
  Timer? _roomTeardownTimer;
  CameraPosition _cameraPosition = CameraPosition.front;
  EventsListener<RoomEvent>? _roomListener;
  Future<void>? _recoveryFuture;
  Timer? _trackNotifyDebounce;

  bool get isActive => active;
  bool get isEnding => _ending;
  bool get isRecovering => _recovering;
  Room? get liveKitRoom => _room;
  CameraPosition get cameraPosition => _cameraPosition;
  bool get isOutgoing => _isOutgoing;
  bool get canToggleSpeaker => Hardware.instance.canSwitchSpeakerphone;

  static String generateSessionId() => const Uuid().v4().substring(0, 8);

  static String buildRoomName(int conversationId, String sessionId) =>
      'messaging-call-$conversationId-$sessionId';

  /// Drop zombie call state (e.g. after ANR) without sending server signals.
  Future<void> forceReset() async {
    _connectEpoch++;
    _cancelRingTimeout();
    _cancelRoomTeardown();
    _trackNotifyDebounce?.cancel();
    _trackNotifyDebounce = null;
    _ending = false;
    _autoEnding = false;
    _detachRoomImmediate();
    _tearDownLocalState(cancelTeardown: false);
    notifyListeners();
  }

  /// Called on app launch — rejoin calls after process death; keep in-memory calls on resume.
  Future<void> recoverAfterLaunch({
    MessagingRepository? messagingRepo,
    String callerName = 'User',
    bool coldStart = false,
  }) async {
    if (_recoveryFuture != null) {
      await _recoveryFuture;
      return;
    }
    _recoveryFuture = _recoverAfterLaunchImpl(
      messagingRepo: messagingRepo,
      callerName: callerName,
      coldStart: coldStart,
    );
    try {
      await _recoveryFuture;
    } finally {
      _recoveryFuture = null;
    }
  }

  Future<void> _recoverAfterLaunchImpl({
    MessagingRepository? messagingRepo,
    String callerName = 'User',
    bool coldStart = false,
  }) async {
    if (active) {
      if (needsRejoin) {
        await rejoinCall();
      } else if (_room != null && !connected && !connecting) {
        await retryConnection();
      }
      return;
    }

    final snap = await CallSessionStorage.read();
    if (snap == null || messagingRepo == null) return;

    _recovering = true;
    _rejoinGraceUntil = DateTime.now().add(const Duration(seconds: 12));
    notifyListeners();

    try {
      final messages = await messagingRepo.fetchMessages(
        snap.conversationId,
        page: 1,
        perPage: 100,
        bypassThrottle: true,
      );
      ChatMessage? callMsg;
      for (final m in messages) {
        if (m.id == snap.messageId) {
          callMsg = m;
          break;
        }
      }
      if (callMsg == null) {
        for (final m in messages) {
          final meta = m.callMeta;
          if (m.type == 'call' && meta != null && meta.callSessionId == snap.sessionId) {
            callMsg = m;
            break;
          }
        }
      }

      final meta = callMsg?.callMeta;
      final phase = (meta?.phase ?? '').toLowerCase();
      if (phase == 'declined' || phase == 'ended') {
        await CallSessionStorage.clear();
        return;
      }

      final canRejoin = snap.callWasAnswered ||
          snap.isOutgoing ||
          phase == 'live' ||
          phase == 'ringing';
      if (!canRejoin) {
        await CallSessionStorage.clear();
        return;
      }

      ConversationSummary conv;
      try {
        final detail = await messagingRepo.fetchConversation(snap.conversationId);
        conv = detail.toSummary();
      } catch (_) {
        final list = await messagingRepo.fetchConversations(bypassThrottle: true);
        conv = list.firstWhere((c) => c.id == snap.conversationId);
      }

      displayName = snap.displayName.isNotEmpty ? snap.displayName : callerName;
      await _rejoinFromSnapshot(
        snap: snap,
        conv: conv,
        messagingRepo: messagingRepo,
        callMessage: callMsg,
      );
    } catch (_) {
      await CallSessionStorage.clear();
    } finally {
      _recovering = false;
      notifyListeners();
    }
  }

  Future<void> persistIfActive() async {
    if (!active) return;
    if (!connected && !_callWasAnswered && !_remoteEverConnected) return;
    await _persistActiveCall();
  }

  Future<void> _rejoinFromSnapshot({
    required CallSessionSnapshot snap,
    required ConversationSummary conv,
    required MessagingRepository messagingRepo,
    ChatMessage? callMessage,
  }) async {
    if (active || connecting) {
      await forceReset();
    }

    final meta = callMessage?.callMeta;
    final epoch = ++_connectEpoch;
    conversation = conv;
    repo = messagingRepo;
    isVideo = snap.isVideo || (meta?.isVideo ?? false);
    active = true;
    minimized = conv.isGroup || snap.isGroupLike;
    connecting = true;
    connected = false;
    error = null;
    statusMessage = null;
    muted = false;
    cameraOff = false;
    loudspeakerOn = isVideo;
    token = null;
    messageId = snap.messageId;
    sessionId = snap.sessionId;
    room = snap.room;
    _isOutgoing = snap.isOutgoing;
    _callWasAnswered = snap.callWasAnswered || !snap.isOutgoing;
    _ending = false;
    _autoEnding = false;
    _remoteEverConnected = snap.callWasAnswered;
    _activeSignalSent = (meta?.phase ?? '') == 'live';
    _ringTimeoutTriggered = false;
    _connectedAt = snap.callWasAnswered ? DateTime.now() : null;
    _cancelRingTimeout();
    _roomListener?.dispose();
    _roomListener = null;
    notifyListeners();
    await _connect(outgoing: false, epoch: epoch);
  }

  Future<void> _persistActiveCall() async {
    final conv = conversation;
    final mid = messageId;
    final sid = sessionId;
    final callRoom = room;
    if (conv == null || mid == null || sid == null || callRoom == null) return;
    if (!connected && !_callWasAnswered && !_remoteEverConnected) return;
    final remoteCount = _room?.remoteParticipants.length ?? 0;
    final multiParty = conv.isGroup || remoteCount >= 2;
    await CallSessionStorage.save(
      CallSessionSnapshot(
        conversationId: conv.id,
        messageId: mid,
        sessionId: sid,
        room: callRoom,
        displayName: displayName,
        isVideo: isVideo,
        isGroup: conv.isGroup || multiParty,
        callWasAnswered: _callWasAnswered,
        isOutgoing: _isOutgoing,
        isMultiParty: multiParty,
        remoteParticipantCount: remoteCount,
      ),
    );
  }

  Future<void> rejoinCall() async {
    if (!active || connecting) return;
    if (connected && _room != null) return;
    final epoch = ++_connectEpoch;
    await _connect(outgoing: false, epoch: epoch);
  }

  /// Join or rejoin a call from a live/ringing call message in chat.
  Future<void> joinExistingCall({
    required ConversationSummary conv,
    required MessagingRepository messagingRepo,
    required String callerName,
    required ChatMessage callMessage,
  }) async {
    final meta = callMessage.callMeta;
    if (meta == null || meta.roomName.isEmpty || meta.callSessionId.isEmpty) {
      error = 'Invalid call invite';
      notifyListeners();
      return;
    }

    if (active &&
        sessionId == meta.callSessionId &&
        room == meta.roomName &&
        conversation?.id == conv.id) {
      if (connected && _room != null) {
        return;
      }
      if (needsRejoin || (!connected && !connecting)) {
        await rejoinCall();
      }
      return;
    }

    final phase = meta.phase.toLowerCase();
    if (phase == 'declined' || phase == 'ended') {
      error = 'This call has already ended';
      notifyListeners();
      return;
    }

    final snap = CallSessionSnapshot(
      conversationId: conv.id,
      messageId: callMessage.id,
      sessionId: meta.callSessionId,
      room: meta.roomName,
      displayName: callerName,
      isVideo: meta.isVideo,
      isGroup: conv.isGroup,
      callWasAnswered: phase == 'live' || meta.callConnected || !callMessage.isSent,
      isOutgoing: callMessage.isSent,
    );

    await _rejoinFromSnapshot(
      snap: snap,
      conv: conv,
      messagingRepo: messagingRepo,
      callMessage: callMessage,
    );
  }

  bool get needsRejoin => active && !connected && !connecting && room != null;

  bool get isGroupLikeCall {
    final conv = conversation;
    final remoteCount = _room?.remoteParticipants.length ?? 0;
    return (conv?.isGroup ?? false) || remoteCount >= 2;
  }

  Future<void> start({
    required ConversationSummary conv,
    required MessagingRepository messagingRepo,
    required String callerName,
    required bool video,
  }) async {
    if (active || connecting) {
      await forceReset();
    }

    final epoch = ++_connectEpoch;
    conversation = conv;
    repo = messagingRepo;
    displayName = callerName;
    isVideo = video;
    active = true;
    minimized = false;
    connecting = true;
    connected = false;
    error = null;
    statusMessage = null;
    muted = false;
    cameraOff = false;
    loudspeakerOn = video;
    token = null;
    messageId = null;
    sessionId = generateSessionId();
    room = buildRoomName(conv.id, sessionId!);
    _isOutgoing = true;
    _callWasAnswered = false;
    _ending = false;
    _autoEnding = false;
    _resetCallTracking();
    _startRingTimeout();
    notifyListeners();
    await _connect(outgoing: true, epoch: epoch);
  }

  Future<void> answerIncoming({
    required ConversationSummary conv,
    required MessagingRepository messagingRepo,
    required String callerName,
    required ChatMessage callMessage,
    required bool video,
  }) async {
    final meta = callMessage.callMeta;
    if (meta == null || meta.roomName.isEmpty || meta.callSessionId.isEmpty) {
      error = 'Invalid call invite';
      notifyListeners();
      return;
    }

    if (active || connecting) {
      await forceReset();
    }

    final epoch = ++_connectEpoch;
    conversation = conv;
    repo = messagingRepo;
    displayName = callerName;
    isVideo = video || meta.isVideo;
    active = true;
    minimized = false;
    connecting = true;
    connected = false;
    error = null;
    statusMessage = null;
    muted = false;
    cameraOff = false;
    loudspeakerOn = isVideo;
    token = null;
    messageId = callMessage.id;
    sessionId = meta.callSessionId;
    room = meta.roomName;
    _isOutgoing = false;
    _callWasAnswered = true;
    _ending = false;
    _autoEnding = false;
    _resetCallTracking();
    notifyListeners();
    await _connect(outgoing: false, epoch: epoch);
  }

  void _resetCallTracking() {
    _remoteEverConnected = false;
    _activeSignalSent = false;
    _ringTimeoutTriggered = false;
    _connectedAt = null;
    _cancelRingTimeout();
    _roomListener?.dispose();
    _roomListener = null;
  }

  Timer? _ringTimeoutTimer;

  void _startRingTimeout() {
    _cancelRingTimeout();
    _ringTimeoutTimer = Timer(const Duration(seconds: ringTimeoutSeconds), () {
      if (!active || _remoteEverConnected || _callWasAnswered) return;
      _ringTimeoutTriggered = true;
      statusMessage = 'No answer — took too long to respond';
      unawaited(end());
    });
  }

  void _cancelRingTimeout() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
  }

  Future<void> _retryAfterRoomDrop() async {
    if (!active || _ending || connecting) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!active || _ending || connected) return;
    await retryConnection();
  }

  Future<void> retryConnection() {
    final epoch = ++_connectEpoch;
    return _connect(outgoing: _isOutgoing && messageId == null, epoch: epoch);
  }

  bool _shouldEndAsCompleted() {
    return _remoteEverConnected || _activeSignalSent || _callWasAnswered;
  }

  bool _hadEstablishedCall() {
    return _remoteEverConnected || _activeSignalSent || _callWasAnswered;
  }

  bool _connectStillValid(int epoch) => epoch == _connectEpoch && active && !_ending;

  Future<void> _sendActiveIfNeeded() async {
    final r = repo;
    final conv = conversation;
    final callRoom = room;
    final sid = sessionId;
    final mid = messageId;
    if (r == null || conv == null || callRoom == null || sid == null || mid == null) return;
    if (_activeSignalSent) return;
    _activeSignalSent = true;
    try {
      await r.sendCallSignal(
        conversationId: conv.id,
        action: 'active',
        callSessionId: sid,
        roomName: callRoom,
        messageId: mid,
      );
    } catch (_) {}
  }

  void _markRemoteJoined() {
    _remoteEverConnected = true;
    _connectedAt ??= DateTime.now();
    _rejoinGraceUntil = null;
    _cancelRingTimeout();
    unawaited(_sendActiveIfNeeded());
    unawaited(_persistActiveCall());
    notifyListeners();
  }

  void _notifyTrackChange() {
    _trackNotifyDebounce?.cancel();
    _trackNotifyDebounce = Timer(const Duration(milliseconds: 120), () {
      if (active && !_ending) notifyListeners();
    });
  }

  void _attachRoomListeners(Room lkRoom) {
    _roomListener?.dispose();
    _roomListener = lkRoom.createListener();
    _roomListener!
      ..on<ParticipantConnectedEvent>((event) {
        if (!_connectStillValid(_connectEpoch)) return;
        final localId = lkRoom.localParticipant?.identity;
        if (localId != null && event.participant.identity != localId) {
          _markRemoteJoined();
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (!_connectStillValid(_connectEpoch)) return;
        final localId = lkRoom.localParticipant?.identity;
        if (localId == null || event.participant.identity == localId) return;
        if (_rejoinGraceUntil != null && DateTime.now().isBefore(_rejoinGraceUntil!)) {
          return;
        }
        if (!_autoEnding && lkRoom.remoteParticipants.isEmpty && _remoteEverConnected) {
          _autoEnding = true;
          statusMessage = 'Call ended';
          scheduleMicrotask(() => unawaited(end()));
        }
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (_ending || !active) return;
        if (_rejoinGraceUntil != null && DateTime.now().isBefore(_rejoinGraceUntil!)) {
          unawaited(_retryAfterRoomDrop());
          return;
        }
        _autoEnding = true;
        statusMessage = 'Call ended';
        scheduleMicrotask(() => unawaited(end()));
      })
      ..on<TrackSubscribedEvent>((_) {
        if (_connectStillValid(_connectEpoch)) _notifyTrackChange();
      })
      ..on<TrackUnsubscribedEvent>((_) {
        if (_connectStillValid(_connectEpoch)) _notifyTrackChange();
      })
      ..on<LocalTrackPublishedEvent>((_) {
        if (_connectStillValid(_connectEpoch)) _notifyTrackChange();
      })
      ..on<LocalTrackUnpublishedEvent>((_) {
        if (_connectStillValid(_connectEpoch)) _notifyTrackChange();
      });

    if (lkRoom.remoteParticipants.isNotEmpty) {
      _markRemoteJoined();
    }
  }

  Future<void> _connect({required bool outgoing, required int epoch}) async {
    final r = repo;
    final conv = conversation;
    final callRoom = room;
    final sid = sessionId;
    if (r == null || conv == null || callRoom == null || sid == null) return;
    if (!_connectStillValid(epoch)) return;

    connecting = true;
    error = null;
    notifyListeners();

    Room? lkRoom;
    try {
      if (outgoing) {
        final msg = await r.sendCallMessage(
          conversationId: conv.id,
          sessionId: sid,
          roomName: callRoom,
          video: isVideo,
        );
        if (!_connectStillValid(epoch)) return;
        messageId = msg.id;
      }

      final t = await r.liveCallToken(room: callRoom, displayName: displayName);
      if (!_connectStillValid(epoch)) return;

      await _detachRoomImmediate();
      lkRoom = Room();
      await lkRoom.connect(t.url, t.token);
      if (!_connectStillValid(epoch)) {
        _scheduleRoomTeardown(lkRoom);
        return;
      }

      await lkRoom.localParticipant?.setMicrophoneEnabled(!muted);
      if (isVideo) {
        await lkRoom.localParticipant?.setCameraEnabled(!cameraOff);
      }

      _room = lkRoom;
      _attachRoomListeners(lkRoom);
      token = t;
      connected = true;
      await _applyAudioRoute();
      if (_callWasAnswered || lkRoom.remoteParticipants.isNotEmpty) {
        if (lkRoom.remoteParticipants.isNotEmpty) _markRemoteJoined();
        _cancelRingTimeout();
        await _sendActiveIfNeeded();
      }
      await _persistActiveCall();
    } catch (e) {
      if (!_connectStillValid(epoch)) return;
      error = e.toString();
      connected = false;
      if (lkRoom != null) {
        _scheduleRoomTeardown(lkRoom);
      } else {
        _detachRoomImmediate();
      }
    } finally {
      if (epoch == _connectEpoch) {
        connecting = false;
        notifyListeners();
      }
    }
  }

  void _cancelRoomTeardown() {
    _roomTeardownTimer?.cancel();
    _roomTeardownTimer = null;
  }

  void _scheduleRoomTeardown(Room lkRoom) {
    _cancelRoomTeardown();
    _roomTeardownTimer = Timer(const Duration(milliseconds: 700), () {
      _roomTeardownTimer = null;
      _disposeRoomSafe(lkRoom);
    });
  }

  void _disposeRoomSafe(Room lkRoom) {
    try {
      final local = lkRoom.localParticipant;
      if (local != null) {
        local.setMicrophoneEnabled(false).ignore();
        local.setCameraEnabled(false).ignore();
      }
    } catch (_) {}
    try {
      lkRoom.disconnect().ignore();
    } catch (_) {}
  }

  Future<void> _detachRoomImmediate() async {
    _cancelRoomTeardown();
    _roomListener?.dispose();
    _roomListener = null;
    final lkRoom = _room;
    _room = null;
    if (lkRoom == null) return;
    _disposeRoomSafe(lkRoom);
  }

  void _forceUiTeardown() {
    if (!active && !connecting && _room == null) return;
    active = false;
    minimized = false;
    connecting = false;
    connected = false;
    notifyListeners();
    final lkRoom = _room;
    _room = null;
    _roomListener?.dispose();
    _roomListener = null;
    if (lkRoom != null) {
      _scheduleRoomTeardown(lkRoom);
    }
  }

  void _tearDownLocalState({bool cancelTeardown = true}) {
    if (cancelTeardown) {
      _cancelRoomTeardown();
    }
    _roomListener?.dispose();
    _roomListener = null;

    final lkRoom = _room;
    _room = null;

    active = false;
    minimized = false;
    connecting = false;
    connected = false;
    conversation = null;
    repo = null;
    token = null;
    room = null;
    sessionId = null;
    messageId = null;
    _isOutgoing = false;
    _callWasAnswered = false;
    _autoEnding = false;
    _remoteEverConnected = false;
    _activeSignalSent = false;
    _ringTimeoutTriggered = false;
    _connectedAt = null;
    error = null;
    loudspeakerOn = false;

    if (lkRoom != null) {
      _scheduleRoomTeardown(lkRoom);
    }
    unawaited(CallSessionStorage.clear());
  }

  void minimize() {
    if (!active) return;
    minimized = true;
    unawaited(_persistActiveCall());
    notifyListeners();
  }

  void expand() {
    minimized = false;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraOff = !cameraOff;
    await _room?.localParticipant?.setCameraEnabled(!cameraOff);
    notifyListeners();
  }

  Future<void> upgradeToVideo() async {
    if (isVideo) return;
    isVideo = true;
    cameraOff = false;
    loudspeakerOn = true;
    await _room?.localParticipant?.setCameraEnabled(true);
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> toggleLoudspeaker() async {
    await setLoudspeaker(!loudspeakerOn);
  }

  Future<void> setLoudspeaker(bool on) async {
    if (!canToggleSpeaker || loudspeakerOn == on) return;
    loudspeakerOn = on;
    await _applyAudioRoute();
    notifyListeners();
  }

  Future<void> _applyAudioRoute() async {
    final lkRoom = _room;
    if (lkRoom == null || !canToggleSpeaker) return;
    try {
      await lkRoom.setSpeakerOn(loudspeakerOn);
    } catch (_) {}
  }

  Future<void> flipCamera() async {
    LocalVideoTrack? track;
    for (final pub in _room?.localParticipant?.videoTrackPublications ?? const []) {
      if (pub.source == TrackSource.camera && pub.track is LocalVideoTrack) {
        track = pub.track as LocalVideoTrack;
        break;
      }
    }
    if (track == null) return;
    final next = _cameraPosition.switched();
    try {
      await track.setCameraPosition(next);
      _cameraPosition = next;
      notifyListeners();
    } catch (_) {}
  }

  Future<List<MediaDevice>> listAudioInputs() async {
    final devices = await Hardware.instance.enumerateDevices();
    return devices.where((d) => d.kind == 'audioinput').toList();
  }

  Future<List<MediaDevice>> listVideoInputs() async {
    final devices = await Hardware.instance.enumerateDevices();
    return devices.where((d) => d.kind == 'videoinput').toList();
  }

  Future<void> selectAudioInput(MediaDevice device) async {
    final lkRoom = _room;
    if (lkRoom == null) return;
    await lkRoom.setAudioInputDevice(device);
    notifyListeners();
  }

  Future<void> selectVideoInput(MediaDevice device) async {
    final lkRoom = _room;
    if (lkRoom == null) return;
    await lkRoom.setVideoInputDevice(device);
    notifyListeners();
  }

  VideoTrack? get remoteVideoTrack {
    if (!active || !connected || _ending) return null;
    final lkRoom = _room;
    if (lkRoom == null) return null;
    for (final participant in lkRoom.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.source != TrackSource.camera || pub.track == null || pub.muted) continue;
        return pub.track as VideoTrack;
      }
    }
    return null;
  }

  VideoTrack? get localVideoTrack {
    if (!active || !connected || _ending) return null;
    final pubs = _room?.localParticipant?.videoTrackPublications;
    if (pubs == null) return null;
    for (final pub in pubs) {
      if (pub.source != TrackSource.camera || pub.track == null || pub.muted) continue;
      return pub.track as VideoTrack;
    }
    return null;
  }

  Future<void> end() async {
    if (_ending) {
      _forceUiTeardown();
      return;
    }
    if (!active && !connecting) return;

    _connectEpoch++;
    _ending = true;
    _cancelRingTimeout();

    final snapshot = _EndSnapshot(
      repo: repo,
      conversation: conversation,
      room: room,
      sessionId: sessionId,
      messageId: messageId,
      isOutgoing: _isOutgoing,
      ringTimeoutTriggered: _ringTimeoutTriggered,
      shouldComplete: _shouldEndAsCompleted(),
      hadEstablishedCall: _hadEstablishedCall(),
      duration: _connectedAt != null && _shouldEndAsCompleted()
          ? DateTime.now().difference(_connectedAt!).inSeconds
          : 0,
      needsActive: _shouldEndAsCompleted() && !_activeSignalSent,
    );

    _tearDownLocalState();
    notifyListeners();

    unawaited(_finishEnd(snapshot));
  }

  Future<void> _finishEnd(_EndSnapshot snapshot) async {
    final r = snapshot.repo;
    final conv = snapshot.conversation;
    final callRoom = snapshot.room;
    final sid = snapshot.sessionId;
    final mid = snapshot.messageId;

    if (r != null && conv != null && callRoom != null && sid != null) {
      try {
        if (snapshot.shouldComplete) {
          if (snapshot.needsActive && mid != null) {
            try {
              await r.sendCallSignal(
                conversationId: conv.id,
                action: 'active',
                callSessionId: sid,
                roomName: callRoom,
                messageId: mid,
              );
            } catch (_) {}
          }
          await r.sendCallSignal(
            conversationId: conv.id,
            action: 'ended',
            callSessionId: sid,
            roomName: callRoom,
            messageId: mid,
            durationSeconds: snapshot.duration > 0 ? snapshot.duration : 1,
            callOutcome: 'completed',
          );
        } else if (snapshot.isOutgoing) {
          if (snapshot.hadEstablishedCall) {
            await r.sendCallSignal(
              conversationId: conv.id,
              action: 'ended',
              callSessionId: sid,
              roomName: callRoom,
              messageId: mid,
              durationSeconds: snapshot.duration > 0 ? snapshot.duration : 1,
              callOutcome: 'completed',
            );
          } else {
            final outcome = snapshot.ringTimeoutTriggered ? 'missed' : 'cancelled';
            await r.sendCallSignal(
              conversationId: conv.id,
              action: 'declined',
              callSessionId: sid,
              roomName: callRoom,
              messageId: mid,
              callOutcome: outcome,
            );
          }
        } else if (snapshot.hadEstablishedCall) {
          await r.sendCallSignal(
            conversationId: conv.id,
            action: 'ended',
            callSessionId: sid,
            roomName: callRoom,
            messageId: mid,
            durationSeconds: snapshot.duration > 0 ? snapshot.duration : 1,
            callOutcome: 'completed',
          );
        } else {
          await r.sendCallSignal(
            conversationId: conv.id,
            action: 'declined',
            callSessionId: sid,
            roomName: callRoom,
            messageId: mid,
            callOutcome: 'rejected',
          );
        }
      } catch (_) {}
    }
    _ending = false;
  }

  static Future<void> declineCallInvite({
    required MessagingRepository repo,
    required int conversationId,
    required ChatMessage callMessage,
  }) async {
    final meta = callMessage.callMeta;
    if (meta == null) return;
    await repo.sendCallSignal(
      conversationId: conversationId,
      action: 'declined',
      callSessionId: meta.callSessionId,
      roomName: meta.roomName,
      messageId: callMessage.id,
      callOutcome: 'rejected',
    );
  }
}

class _EndSnapshot {
  _EndSnapshot({
    required this.repo,
    required this.conversation,
    required this.room,
    required this.sessionId,
    required this.messageId,
    required this.isOutgoing,
    required this.ringTimeoutTriggered,
    required this.shouldComplete,
    required this.hadEstablishedCall,
    required this.duration,
    required this.needsActive,
  });

  final MessagingRepository? repo;
  final ConversationSummary? conversation;
  final String? room;
  final String? sessionId;
  final int? messageId;
  final bool isOutgoing;
  final bool ringTimeoutTriggered;
  final bool shouldComplete;
  final bool hadEstablishedCall;
  final int duration;
  final bool needsActive;
}
