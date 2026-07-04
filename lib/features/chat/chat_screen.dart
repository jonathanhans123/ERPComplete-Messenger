import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';
import '../calls/video_call_screen.dart';
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
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initRepo();
    _load();
  }

  void _initRepo() {
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await _repo.fetchMessages(widget.conversation.id);
      await _repo.markRead(widget.conversation.id);
      if (mounted) setState(() => _messages = messages.reversed.toList());
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    try {
      final msg = await _repo.sendTextMessage(conversationId: widget.conversation.id, body: text);
      if (mounted) {
        setState(() => _messages = [..._messages, msg]);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        _input.text = text;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startVideoCall() {
    final auth = context.read<AuthRepository>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          conversation: widget.conversation,
          repo: MessagingRepository(() => auth.client(), currentUserId: auth.userId),
          displayName: auth.userName ?? 'User',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.isGroup;
    return Scaffold(
      backgroundColor: MessengerColors.bgSecondary,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: MessengerColors.primary,
              child: Text(widget.conversation.avatarInitials ?? '?', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (widget.conversation.online == true)
                    Text('Online', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: MessengerColors.success)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Video call', onPressed: _startVideoCall, icon: const Icon(Icons.videocam_rounded)),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? const Center(child: Text('No messages yet — say hello'))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              return MessageBubble(message: msg, showSender: isGroup);
                            },
                          ),
          ),
          Material(
            elevation: 8,
            color: MessengerColors.bgPrimary,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message…',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                        backgroundColor: MessengerColors.primary,
                      ),
                      child: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
