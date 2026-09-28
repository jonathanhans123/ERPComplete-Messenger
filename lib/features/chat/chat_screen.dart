import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_throttle_guard.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/calls/call_session_controller.dart';
import '../../core/cache/messenger_local_cache.dart';
import '../../core/media/attachment_kind.dart';
import '../../core/messaging/messaging_broadcast_service.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/chat_composer.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/message_media_widgets.dart';
import '../../widgets/messenger_avatar.dart';
import '../conversations/conversation_actions.dart';
import '../conversations/conversation_info_screen.dart';
import 'chat_attachment_sheet.dart';
import 'chat_list_helpers.dart';
import 'chat_media_gallery_screen.dart';
import 'chat_search_screen.dart';
import 'message_actions.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation, this.onBack});

  final ConversationSummary conversation;
  final VoidCallback? onBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late MessagingRepository _repo;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];

  /// client_message_id -> id of the pending copy, so the real-time echo of one's own message replaces
  /// the pending copy instead of being added next to it.
  final Map<String, int> _pendingByClientId = {};
  List<ChatListEntry> _entries = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  ChatMessage? _replyTo;
  // Premium open: list is reverse:true so offset 0 IS the bottom — no
  // jump-to-bottom animation is ever needed on open. Fade the list in once
  // data is painted instead of visibly fast-scrolling through history.
  bool _listReady = false;
  int _page = 1;
  static const int _perPage = 50;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _unseenWhileUp = 0;
  StreamSubscription<MessagingBroadcastEvent>? _broadcastSub;
  Timer? _fallbackPollTimer;
  Timer? _typingTimer;
  bool _typingSent = false;
  final _recorderController = RecorderController();
  bool _recordingVoice = false;
  bool _recordingPaused = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _voiceRecordPath;
  MessagingBroadcastService? _broadcastService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRepo();
    _scroll.addListener(_onScroll);
    _load();
    _subscribeBroadcast();
    _input.addListener(_onInputChanged);
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore || _loading) return;
    // reverse:true → maxScrollExtent is the TOP (oldest). Load older when near it.
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 400) {
      unawaited(_loadMore());
    }
  }

  bool get _isNearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.offset < 120;
  }

  void _subscribeBroadcast() {
    final auth = context.read<AuthRepository>();
    final broadcast = context.read<MessagingBroadcastService>();
    _broadcastService = broadcast;
    broadcast.subscribeConversation(
      widget.conversation.id,
      title: widget.conversation.title,
    );
    _broadcastSub?.cancel();
    _broadcastSub = broadcast.events.listen(_onBroadcastEvent);
    broadcast.removeListener(_onBroadcastStateChanged);
    broadcast.addListener(_onBroadcastStateChanged);
    if (!broadcast.isConnected) {
      unawaited(broadcast.connect(auth));
    }
    _updateFallbackPoll();
  }

  void _onBroadcastStateChanged() {
    if (!mounted) return;
    final broadcast = context.read<MessagingBroadcastService>();
    if (broadcast.isConnected) {
      broadcast.subscribeConversation(
        widget.conversation.id,
        title: widget.conversation.title,
      );
    }
    _updateFallbackPoll();
  }

  void _updateFallbackPoll() {
    final connected = context.read<MessagingBroadcastService>().isConnected;
    if (connected) {
      _fallbackPollTimer?.cancel();
      _fallbackPollTimer = null;
      return;
    }
    // Fallback only when WebSocket is down. 15s interval + throttle respect
    // keeps an open chat from tripping rate limits on its own.
    _fallbackPollTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _loading || _sending) return;
      if (ApiThrottleGuard.instance.isBlocked) return;
      if (context.read<MessagingBroadcastService>().isConnected) {
        _updateFallbackPoll();
        return;
      }
      unawaited(_load(silent: true));
    });
  }

  void _onBroadcastEvent(MessagingBroadcastEvent event) {
    if (event.conversationId != widget.conversation.id || !mounted) return;
    final auth = context.read<AuthRepository>();
    final uid = auth.userId ?? 0;

    if (event.eventName == 'message.sent' || event.eventName == 'message.updated') {
      final msg = ChatMessage.fromJson(event.data, uid);
      if (msg.id == 0) return;

      var existingIndex = _messages.indexWhere((m) => m.id == msg.id);
      final pendingId = _pendingByClientId[event.data['client_message_id']];
      if (existingIndex < 0 && pendingId != null) {
        existingIndex = _messages.indexWhere((m) => m.id == pendingId);
      }
      final wasNearBottom = _isNearBottom;

      setState(() {
        if (existingIndex >= 0) {
          _messages = [..._messages]..[existingIndex] = msg;
        } else if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [..._messages, msg];
        }
        _rebuildEntries();
        // New incoming while reading history → pill instead of yanking scroll.
        if (existingIndex < 0 && event.eventName == 'message.sent' && !msg.isSent && !wasNearBottom) {
          _unseenWhileUp++;
        }
      });

      if (event.eventName == 'message.sent' && !msg.isSent) {
        unawaited(_repo.markRead(widget.conversation.id).catchError((_) {}));
      }
      // reverse:true list stays pinned at offset 0 on its own; only animate
      // when the user was already at the bottom (or it's an edit in view).
      if (wasNearBottom) {
        _scrollToBottom();
        if (mounted) setState(() => _unseenWhileUp = 0);
      }
      unawaited(MessengerLocalCache.instance.saveMessages(
        widget.conversation.id,
        _messages.reversed.toList(),
      ));
    }
  }

  void _onInputChanged() {
    _typingTimer?.cancel();
    final hasText = _input.text.trim().isNotEmpty;
    if (hasText && !_typingSent) {
      if (ApiThrottleGuard.instance.isBlocked) return;
      _typingSent = true;
      _repo.sendTyping(widget.conversation.id, true).catchError((_) {
        _typingSent = false;
      });
    }
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (_typingSent) {
        _typingSent = false;
        if (!ApiThrottleGuard.instance.isBlocked) {
          _repo.sendTyping(widget.conversation.id, false).catchError((_) {});
        }
      }
    });
  }

  void _initRepo() {
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final auth = context.read<AuthRepository>();
      final broadcast = context.read<MessagingBroadcastService>();
      unawaited(broadcast.connect(auth));
      unawaited(_load(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _broadcastSub?.cancel();
    _fallbackPollTimer?.cancel();
    _broadcastService?.removeListener(_onBroadcastStateChanged);
    _scroll.removeListener(_onScroll);
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _recorderController.dispose();
    _input.removeListener(_onInputChanged);
    if (_typingSent) {
      _repo.sendTyping(widget.conversation.id, false).catchError((_) {});
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildEntries() {
    final prefs = context.read<MessengerPreferences>();
    final starred = prefs.starredMessageIds(widget.conversation.id);
    _entries = buildChatListEntries(applyStarredAll(_messages, starred));
  }

  Future<void> _load({bool silent = false}) async {
    final auth = context.read<AuthRepository>();
    if (!silent) {
      final cached = await MessengerLocalCache.instance.loadMessages(
        widget.conversation.id,
        currentUserId: auth.userId,
      );
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _messages = cached.reversed.toList();
          _rebuildEntries();
          _loading = false;
          _page = 1;
          _hasMore = cached.length >= _perPage;
        });
        // No scroll jump: reverse list already sits at the bottom.
        // Fade in after first paint so open feels instant, not scrolled.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_listReady) setState(() => _listReady = true);
        });
      } else if (!silent) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    }
    if (ApiThrottleGuard.instance.isBlocked) {
      if (mounted && !silent && _messages.isEmpty) {
        setState(() {
          _error = ApiThrottleGuard.instance.userMessage;
          _loading = false;
        });
      }
      return;
    }
    try {
      final messages = await _repo.fetchMessages(widget.conversation.id, page: 1, perPage: _perPage);
      await MessengerLocalCache.instance.saveMessages(widget.conversation.id, messages);
      try {
        await _repo.markRead(widget.conversation.id);
      } catch (_) {}
      if (mounted) {
        final chronological = messages.reversed.toList();
        final changed = chatMessagesChanged(_messages, chronological);
        setState(() {
          // Smart merge: skip setState churn when server state is identical —
          // this is what caused the visible re-layout + re-scroll flicker.
          if (changed || _messages.isEmpty) {
            _messages = chronological;
            _rebuildEntries();
          }
          _page = 1;
          _hasMore = messages.length >= _perPage;
          if (!silent) _loading = false;
          _error = null;
        });
        // Pin to bottom only if the user was already there (or first open).
        // Never yank a user who scrolled up to read history.
        if (_isNearBottom) {
          _scrollToBottom(animated: false);
        }
        if (!_listReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _listReady = true);
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = _messages.isEmpty ? formatApiError(e) : null;
          _loading = false;
        });
      }
    }
  }

  /// Pagination: fetch the next older page and prepend without moving the
  /// visible viewport (reverse list keeps offset stable).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !mounted) return;
    _loadingMore = true;
    try {
      final next = _page + 1;
      final fetched = await _repo.fetchMessages(widget.conversation.id, page: next, perPage: _perPage);
      if (!mounted) return;
      if (fetched.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }
      final older = fetched.reversed.toList();
      final known = _messages.map((m) => m.id).toSet();
      final fresh = older.where((m) => !known.contains(m.id)).toList();
      setState(() {
        _messages = [...fresh, ..._messages];
        _rebuildEntries();
        _page = next;
        if (fetched.length < _perPage) _hasMore = false;
      });
    } catch (_) {
      // Silent: user can retry by scrolling again.
    } finally {
      _loadingMore = false;
    }
  }

  void _scrollToBottom({bool animated = true}) {
    // reverse:true → bottom IS offset 0, always valid, no retry loop needed.
    if (!_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients || !mounted) return;
        if (animated) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        } else {
          _scroll.jumpTo(0);
        }
      });
      return;
    }
    if (animated) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(0);
    }
    if (mounted && _unseenWhileUp != 0) setState(() => _unseenWhileUp = 0);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    final replyId = _replyTo?.id;
    final replyPreview = _replyTo?.body;
    final replySender = _replyTo?.senderName;
    setState(() => _replyTo = null);

    final auth = context.read<AuthRepository>();
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final clientMessageId = const Uuid().v4();
    _pendingByClientId[clientMessageId] = tempId;
    final now = DateTime.now();
    final pending = ChatMessage(
      id: tempId,
      body: text,
      senderName: auth.userName ?? 'You',
      senderId: auth.userId ?? 0,
      isSent: true,
      time: _formatTime(now),
      date: now.toIso8601String().substring(0, 10),
      status: 'sending',
      isPending: true,
      replyToId: replyId,
      replyPreview: replyPreview,
      replyToSender: replySender,
    );
    setState(() {
      _messages = [..._messages, pending];
      _rebuildEntries();
    });
    _scrollToBottom();

    try {
      final msg = await _repo.sendTextMessage(
        conversationId: widget.conversation.id,
        body: text,
        replyToMessageId: replyId,
        clientMessageId: clientMessageId,
      );
      if (mounted) {
        setState(() {
          // The real-time echo can arrive before this response and has already put the saved message
          // in the list: drop the pending copy instead of turning it into a second one.
          if (_messages.any((m) => m.id == msg.id)) {
            _messages = _messages.where((m) => m.id != tempId).toList();
          }
          _messages = _messages.map((m) => m.id == tempId ? msg.copyWith(replyPreview: replyPreview, replyToSender: replySender, replyToId: replyId) : m).toList();
          _rebuildEntries();
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages.where((m) => m.id != tempId).toList();
          _rebuildEntries();
        });
        // 401 triggers global auto-logout — don't restore the draft into a
        // session that is being signed out.
        if (e is ApiException && e.isUnauthorized) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
        _input.text = text;
      }
    } finally {
      _pendingByClientId.remove(clientMessageId);
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachFile() async {
    if (!mounted) return;
    await ChatAttachmentSheet.show(
      context,
      repo: _repo,
      conversationId: widget.conversation.id,
      onSent: (msg) {
        if (!mounted) return;
        setState(() {
          if (!_messages.any((m) => m.id == msg.id)) _messages = [..._messages, msg];
          _rebuildEntries();
        });
        _scrollToBottom();
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
        }
      },
    );
  }

  static String _formatVoiceDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecording() async {
    if (_sending || _recordingVoice) return;
    if (!await _recorderController.checkPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied')));
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _voiceRecordPath = path;
    await _recorderController.record(
      path: path,
      androidEncoder: AndroidEncoder.aac,
      androidOutputFormat: AndroidOutputFormat.mpeg4,
      iosEncoder: IosEncoder.kAudioFormatMPEG4AAC,
    );
    _recordingTimer?.cancel();
    setState(() {
      _recordingVoice = true;
      _recordingPaused = false;
      _recordingSeconds = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recordingPaused && mounted) {
        setState(() => _recordingSeconds++);
      }
    });
  }

  Future<void> _pauseVoiceRecording() async {
    if (!_recordingVoice || _recordingPaused) return;
    await _recorderController.pause();
    setState(() => _recordingPaused = true);
  }

  Future<void> _resumeVoiceRecording() async {
    if (!_recordingVoice || !_recordingPaused) return;
    await _recorderController.record(
      path: _voiceRecordPath,
      androidEncoder: AndroidEncoder.aac,
      androidOutputFormat: AndroidOutputFormat.mpeg4,
      iosEncoder: IosEncoder.kAudioFormatMPEG4AAC,
    );
    setState(() => _recordingPaused = false);
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recordingVoice) return;
    _recordingTimer?.cancel();
    await _recorderController.stop();
    final path = _voiceRecordPath;
    setState(() {
      _recordingVoice = false;
      _recordingPaused = false;
      _recordingSeconds = 0;
      _voiceRecordPath = null;
    });
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _sendVoiceRecording() async {
    if (!_recordingVoice || _sending) return;
    _recordingTimer?.cancel();
    final path = await _recorderController.stop();
    final duration = _recordingSeconds;
    final filePath = path ?? _voiceRecordPath;
    setState(() {
      _recordingVoice = false;
      _recordingPaused = false;
      _recordingSeconds = 0;
      _voiceRecordPath = null;
    });
    if (filePath == null || !File(filePath).existsSync() || duration < 1) {
      if (filePath != null) {
        try {
          await File(filePath).delete();
        } catch (_) {}
      }
      return;
    }

    setState(() => _sending = true);
    try {
      final msg = await _repo.sendAttachmentMessage(
        conversationId: widget.conversation.id,
        type: 'voice',
        file: File(filePath),
        attachments: [
          {'type': 'voice', 'duration': _formatVoiceDuration(duration)},
        ],
      );
      if (mounted) {
        setState(() {
          if (!_messages.any((m) => m.id == msg.id)) _messages = [..._messages, msg];
          _rebuildEntries();
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    } finally {
      if (filePath.isNotEmpty) {
        try {
          final f = File(filePath);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openMediaViewer(ChatMessage message, AttachmentInfo info) {
    final items = mediaViewerItemsFromMessages(_messages);
    if (items.isEmpty) return;
    final idx = items.indexWhere((i) => i.url == info.url);
    MediaViewerScreen.open(context, items: items, initialIndex: idx >= 0 ? idx : 0);
  }

  Future<void> _votePoll(ChatMessage msg, String optionId) async {
    try {
      final updated = await _repo.votePoll(msg.id, optionId);
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((x) => x.id == updated.id ? updated : x).toList();
        _rebuildEntries();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  void _openInfo() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationInfoScreen(conversation: widget.conversation)));
  }

  void _rejoinCall(ChatMessage callMessage) {
    unawaited(ConversationActions.rejoinCallFromChat(context, widget.conversation, callMessage));
  }

  Widget _buildLiveCallBanner() {
    final live = ConversationActions.latestRejoinableCall(_messages);
    if (live == null) return const SizedBox.shrink();

    final call = context.watch<CallSessionController>();
    final liveSid = live.callMeta?.callSessionId;
    if (ConversationActions.isAlreadyInCall(
      call: call,
      conversationId: widget.conversation.id,
      callSessionId: liveSid,
    )) {
      return const SizedBox.shrink();
    }

    final needsReturn = call.active &&
        call.sessionId == liveSid &&
        call.conversation?.id == widget.conversation.id &&
        call.minimized;

    final video = live.callMeta?.isVideo ?? false;
    return Material(
      color: const Color(0xFF1F2C34),
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(video ? Icons.videocam : Icons.call, color: MessengerPalette.whatsAppGreen, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  video ? 'Video call in progress' : 'Voice call in progress',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () => _rejoinCall(live),
                style: FilledButton.styleFrom(
                  backgroundColor: MessengerPalette.whatsAppGreen,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(needsReturn ? 'Return to call' : 'Rejoin'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final prefs = context.watch<MessengerPreferences>();
    final isGroup = widget.conversation.isGroup;
    final muted = prefs.isMuted(widget.conversation.id);
    final wallpaper = prefs.wallpaperColor(Theme.of(context).brightness);
    final bgColor = wallpaper == Colors.transparent ? ext.chatBackground : wallpaper;

    final scaffold = Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
        titleSpacing: widget.onBack != null ? 0 : null,
        title: InkWell(
          onTap: _openInfo,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              MessengerAvatar(label: widget.conversation.avatarInitials ?? '?', radius: 18, isGroup: isGroup, online: widget.conversation.online),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      widget.conversation.online == true ? 'online' : (isGroup ? '${widget.conversation.channelKind} group' : 'tap for info'),
                      style: TextStyle(fontSize: 12, color: ext.subtext, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            onPressed: () => ConversationActions.startCall(context, widget.conversation, video: false),
            icon: const Icon(Icons.call_outlined),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: () => ConversationActions.startCall(context, widget.conversation, video: true),
            icon: const Icon(Icons.videocam_rounded),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatSearchScreen(messages: _messages)),
            ),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'search') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatSearchScreen(messages: _messages)));
              } else if (v == 'media') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatMediaGalleryScreen(messages: _messages)));
              } else {
                await ConversationActions.handleMenuSelection(
                  context,
                  value: v,
                  conversation: widget.conversation,
                  onChanged: () {
                    if (v != 'delete' && mounted) _load();
                  },
                  muted: muted,
                  onDeleted: () {
                    // Chat is gone — go back to the list instead of showing a dead chat.
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else if (mounted && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                );
              }
            },
            itemBuilder: (_) => ConversationActions.chatMenuItems(widget.conversation, muted: muted),
          ),
        ],
      ),
      body: ChatWallpaperBackground(
        customImagePath: prefs.customWallpaperPath,
        fallbackColor: bgColor,
        child: Column(
        children: [
          _buildLiveCallBanner(),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: prefs.customWallpaperPath != null ? Colors.transparent : bgColor),
              child: _loading
                ? _ChatSkeleton(bgColor: bgColor)
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 40, color: ext.subtext),
                                const SizedBox(height: 12),
                                Text('Messages are end-to-end ready', style: TextStyle(color: ext.subtext)),
                                const SizedBox(height: 4),
                                Text('Say hello 👋', style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: _listReady ? 1.0 : 0.0,
                                child: ListView.builder(
                                  controller: _scroll,
                                  // Pinned-bottom: offset 0 is the newest message, so the
                                  // list OPENS at the bottom with zero scroll animation.
                                  reverse: true,
                                  scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _entries.length + (_hasMore ? 1 : 0),
                                  findChildIndexCallback: (key) {
                                    final v = (key as ValueKey?)?.value;
                                    if (v is int) {
                                      final i = _entries.indexWhere((e) =>
                                          e is ChatMessageEntry && e.message.id == v);
                                      if (i >= 0) return _entries.length - 1 - i;
                                    }
                                    return null;
                                  },
                                  itemBuilder: (context, index) {
                                    // Top slot (oldest side) shows history loader.
                                    if (_hasMore && index == _entries.length) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      );
                                    }
                                    // Reverse mapping: builder 0 = newest at bottom.
                                    final entry = _entries[_entries.length - 1 - index];
                                    if (entry is ChatDateDividerEntry) {
                                      return DateDivider(label: entry.label);
                                    }
                                    final msg = (entry as ChatMessageEntry).message;
                                    final uid = context.read<AuthRepository>().userId;
                                    final callCtrl = context.read<CallSessionController>();
                                    final canRejoin = msg.isRejoinableCall &&
                                        !ConversationActions.isAlreadyInCall(
                                          call: callCtrl,
                                          conversationId: widget.conversation.id,
                                          callSessionId: msg.callMeta?.callSessionId,
                                        );
                                    return RepaintBoundary(
                                      child: MessageBubble(
                                        key: ValueKey(msg.id),
                                        message: msg,
                                        showSender: isGroup,
                                        currentUserId: uid,
                                        onMediaOpen: _openMediaViewer,
                                        onCallRejoin: canRejoin ? _rejoinCall : null,
                                        onPollVote: msg.pollAttachment != null ? (opt) => _votePoll(msg, opt) : null,
                                        onLongPress: () => showMessageActions(
                                          context,
                                          message: msg,
                                          repo: _repo,
                                          conversationId: widget.conversation.id,
                                          onUpdated: (m) {
                                            if (m == null) {
                                              setState(() {
                                                _messages = _messages.where((x) => x.id != msg.id).toList();
                                                _rebuildEntries();
                                              });
                                            } else {
                                              setState(() {
                                                _messages = _messages.map((x) => x.id == m.id ? m : x).toList();
                                                _rebuildEntries();
                                              });
                                            }
                                          },
                                          onReply: (m) => setState(() => _replyTo = m),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (_unseenWhileUp > 0)
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Material(
                                      color: MessengerPalette.whatsAppGreen,
                                      borderRadius: BorderRadius.circular(20),
                                      elevation: 4,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => _scrollToBottom(),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.arrow_downward, size: 16, color: Colors.white),
                                              const SizedBox(width: 6),
                                              Text(
                                                _unseenWhileUp == 1 ? '1 new message' : '$_unseenWhileUp new messages',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
            ),
          ),
          ChatComposer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            onAttach: _attachFile,
            onStartVoiceRecord: _startVoiceRecording,
            voiceRecording: _recordingVoice
                ? VoiceRecordingState(
                    durationSeconds: _recordingSeconds,
                    paused: _recordingPaused,
                    recorderController: _recorderController,
                  )
                : null,
            onCancelVoiceRecording: _cancelVoiceRecording,
            onPauseVoiceRecording: _pauseVoiceRecording,
            onResumeVoiceRecording: _resumeVoiceRecording,
            onSendVoiceRecording: _sendVoiceRecording,
            replyPreview: _replyTo != null ? '${_replyTo!.senderName}: ${_replyTo!.body}' : null,
            onCancelReply: () => setState(() => _replyTo = null),
          ),
        ],
        ),
      ),
    );

    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack!();
        },
        child: scaffold,
      );
    }

    return scaffold;
  }
}

/// Static shimmer-style placeholders shown while history loads, so opening
/// a chat feels instant instead of spinner → visible fast-scroll.
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton({required this.bgColor});
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmer = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    Widget bubble({required bool sent, required double width, double height = 44}) {
      return Padding(
        padding: EdgeInsets.only(left: sent ? 60 : 12, right: sent ? 12 : 60, top: 5, bottom: 5),
        child: Row(
          mainAxisAlignment: sent ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: (sent ? ext.sentBubble : ext.receivedBubble).withValues(alpha: 0.7),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(sent ? 12 : 2),
                  bottomRight: Radius.circular(sent ? 2 : 12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: width * 0.85,
                      height: 10,
                      decoration: BoxDecoration(color: shimmer, borderRadius: BorderRadius.circular(5)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: width * 0.55,
                      height: 10,
                      decoration: BoxDecoration(color: shimmer, borderRadius: BorderRadius.circular(5)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        bubble(sent: true, width: 210),
        bubble(sent: false, width: 240, height: 58),
        bubble(sent: false, width: 160),
        bubble(sent: true, width: 190, height: 58),
        bubble(sent: false, width: 220),
        bubble(sent: true, width: 150),
      ],
    );
  }
}
