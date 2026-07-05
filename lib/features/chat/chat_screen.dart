import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_throttle_guard.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/cache/messenger_local_cache.dart';
import '../../core/media/attachment_kind.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  late MessagingRepository _repo;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  List<ChatListEntry> _entries = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  ChatMessage? _replyTo;
  Timer? _pollTimer;
  Timer? _typingTimer;
  bool _typingSent = false;
  final _recorderController = RecorderController();
  bool _recordingVoice = false;
  bool _recordingPaused = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _voiceRecordPath;
  bool _showingCachedData = false;

  @override
  void initState() {
    super.initState();
    _initRepo();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) => _pollMessages());
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    _typingTimer?.cancel();
    final hasText = _input.text.trim().isNotEmpty;
    if (hasText && !_typingSent) {
      _typingSent = true;
      _repo.sendTyping(widget.conversation.id, true).catchError((_) {});
    }
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_typingSent) {
        _typingSent = false;
        _repo.sendTyping(widget.conversation.id, false).catchError((_) {});
      }
    });
  }

  void _initRepo() {
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
          _showingCachedData = true;
        });
        _scrollToBottom(animated: false);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) _scrollToBottom(animated: false);
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
      final messages = await _repo.fetchMessages(widget.conversation.id);
      await MessengerLocalCache.instance.saveMessages(widget.conversation.id, messages);
      try {
        await _repo.markRead(widget.conversation.id);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _rebuildEntries();
          if (!silent) _loading = false;
          _showingCachedData = false;
          _error = null;
        });
        if (!silent) {
          _scrollToBottom(animated: false);
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _scrollToBottom(animated: false);
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = _messages.isEmpty ? formatApiError(e) : null;
          _loading = false;
          _showingCachedData = _messages.isNotEmpty;
        });
      }
    }
  }

  Future<void> _pollMessages() async {
    if (_loading || _sending || ApiThrottleGuard.instance.isBlocked) return;
    try {
      final messages = await _repo.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      final reversed = messages.reversed.toList();
      await MessengerLocalCache.instance.saveMessages(widget.conversation.id, messages);
      if (chatMessagesChanged(_messages.where((m) => !m.isPending).toList(), reversed)) {
        final nearBottom = _scroll.hasClients &&
            (_scroll.position.maxScrollExtent - _scroll.offset) < 120;
        setState(() {
          _messages = reversed;
          _rebuildEntries();
        });
        if (nearBottom) _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom({bool animated = true, int attempts = 8}) {
    void schedule(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) {
          if (remaining > 0) schedule(remaining - 1);
          return;
        }
        final max = _scroll.position.maxScrollExtent;
        if (max <= 0 && remaining > 0) {
          schedule(remaining - 1);
          return;
        }
        if (animated) {
          _scroll.animateTo(max, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        } else {
          _scroll.jumpTo(max);
        }
      });
    }
    schedule(attempts);
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
      );
      if (mounted) {
        setState(() {
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
        _input.text = text;
      }
    } finally {
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
        setState(() {
          _messages = [..._messages, msg];
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
          _messages = [..._messages, msg];
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
                  onChanged: () => _load(),
                  muted: muted,
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
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: prefs.customWallpaperPath != null ? Colors.transparent : bgColor),
              child: _loading
                ? const Center(child: CircularProgressIndicator())
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
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _entries.length,
                            itemBuilder: (context, index) {
                              final entry = _entries[index];
                              if (entry is ChatDateDividerEntry) {
                                return DateDivider(label: entry.label);
                              }
                              final msg = (entry as ChatMessageEntry).message;
                              final uid = context.read<AuthRepository>().userId;
                              return MessageBubble(
                                message: msg,
                                showSender: isGroup,
                                currentUserId: uid,
                                onMediaOpen: _openMediaViewer,
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
                              );
                            },
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
