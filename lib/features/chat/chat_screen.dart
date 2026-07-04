import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/chat_composer.dart';
import '../../widgets/messenger_avatar.dart';
import '../conversations/conversation_actions.dart';
import '../conversations/conversation_info_screen.dart';
import 'chat_list_helpers.dart';
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

  @override
  void initState() {
    super.initState();
    _initRepo();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollMessages());
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
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final messages = await _repo.fetchMessages(widget.conversation.id);
      await _repo.markRead(widget.conversation.id);
      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _rebuildEntries();
        });
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted && !silent) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _pollMessages() async {
    if (_loading || _sending) return;
    try {
      final messages = await _repo.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      final reversed = messages.reversed.toList();
      if (chatMessagesChanged(_messages.where((m) => !m.isPending).toList(), reversed)) {
        setState(() {
          _messages = reversed;
          _rebuildEntries();
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
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
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo / file'),
              subtitle: const Text('Use web messenger for attachments (mobile picker coming soon)'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.business_center_outlined),
              title: const Text('Share ERP card'),
              subtitle: const Text('Search records from web app for now'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
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

    return Scaffold(
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
          PopupMenuButton<String>(
            onSelected: (v) => ConversationActions.handleMenuSelection(
              context,
              value: v,
              conversation: widget.conversation,
              onChanged: () => _load(),
              muted: muted,
            ),
            itemBuilder: (_) => ConversationActions.chatMenuItems(widget.conversation, muted: muted),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(color: bgColor),
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
                              return MessageBubble(
                                message: msg,
                                showSender: isGroup,
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
            replyPreview: _replyTo != null ? '${_replyTo!.senderName}: ${_replyTo!.body}' : null,
            onCancelReply: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }
}
