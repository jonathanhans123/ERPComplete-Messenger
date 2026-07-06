import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/calls/call_session_controller.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/notifications/messenger_notification_service.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/messenger_avatar.dart';
import '../../core/calls/call_screen_navigator.dart';
import '../settings/settings_screen.dart';
import 'conversation_info_screen.dart';
import 'create_group_screen.dart';

/// Shared ellipsis actions for chat list + chat screen.
class ConversationActions {
  static MessagingRepository repoOf(BuildContext context) {
    final auth = context.read<AuthRepository>();
    return MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  static Future<void> pin(BuildContext context, ConversationSummary c, {required VoidCallback onChanged}) async {
    try {
      await repoOf(context).togglePinConversation(c.id, !c.isPinned);
      onChanged();
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  static Future<void> archive(BuildContext context, ConversationSummary c, {required VoidCallback onChanged}) async {
    try {
      await repoOf(context).toggleArchiveConversation(c.id, !c.isArchived);
      onChanged();
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  static Future<void> clear(BuildContext context, ConversationSummary c, {VoidCallback? onChanged}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('Messages will be cleared for everyone in this chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repoOf(context).clearChat(c.id);
      onChanged?.call();
      if (context.mounted) _snack(context, 'Chat cleared');
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  static Future<void> exportChat(BuildContext context, ConversationSummary c) async {
    try {
      await repoOf(context).exportChat(c.id);
      if (context.mounted) _snack(context, 'Export ready — full download on web messenger');
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  static Future<void> startCall(BuildContext context, ConversationSummary c, {required bool video}) async {
    final auth = context.read<AuthRepository>();
    final call = context.read<CallSessionController>();
    final repo = repoOf(context);
    if (call.isActive) {
      await call.end();
      await MessengerNotificationService.instance.clearAllCallNotifications();
    }
    unawaited(CallScreenNavigator.open(context));
    await call.start(
      conv: c,
      messagingRepo: repo,
      callerName: auth.userName ?? 'User',
      video: video,
    );
    if (!call.active) {
      CallScreenNavigator.popIfOpen();
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<void> showListMenuSheet(
    BuildContext context, {
    required ConversationSummary conversation,
    required VoidCallback onChanged,
    required bool muted,
  }) async {
    final items = [
      ('info', Icons.info_outline, 'Contact / group info'),
      (conversation.isPinned ? 'pin' : 'pin', conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin, conversation.isPinned ? 'Unpin' : 'Pin'),
      (muted ? 'mute' : 'mute', muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, muted ? 'Unmute' : 'Mute'),
      (conversation.isArchived ? 'archive' : 'archive', conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, conversation.isArchived ? 'Unarchive' : 'Archive'),
      ('clear', Icons.delete_sweep_outlined, 'Clear chat'),
      ('export', Icons.download_outlined, 'Export chat'),
    ];
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map(
                (e) => ListTile(
                  leading: Icon(e.$2),
                  title: Text(e.$3),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await handleMenuSelection(context, value: e.$1, conversation: conversation, onChanged: onChanged, muted: muted);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  static List<PopupMenuEntry<String>> listMenuItems(ConversationSummary c, {bool muted = false}) {
    return [
      const PopupMenuItem(value: 'info', child: _MenuRow(icon: Icons.info_outline, label: 'Contact / group info')),
      PopupMenuItem(value: 'pin', child: _MenuRow(icon: c.isPinned ? Icons.push_pin_outlined : Icons.push_pin, label: c.isPinned ? 'Unpin' : 'Pin')),
      PopupMenuItem(value: 'mute', child: _MenuRow(icon: muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, label: muted ? 'Unmute (mobile)' : 'Mute (mobile)')),
      PopupMenuItem(value: 'archive', child: _MenuRow(icon: c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, label: c.isArchived ? 'Unarchive' : 'Archive')),
      const PopupMenuItem(value: 'clear', child: _MenuRow(icon: Icons.delete_sweep_outlined, label: 'Clear chat')),
      const PopupMenuItem(value: 'export', child: _MenuRow(icon: Icons.download_outlined, label: 'Export chat')),
    ];
  }

  static List<PopupMenuEntry<String>> chatMenuItems(ConversationSummary c, {bool muted = false}) {
    return [
      const PopupMenuItem(value: 'search', child: _MenuRow(icon: Icons.search, label: 'Search in chat')),
      const PopupMenuItem(value: 'media', child: _MenuRow(icon: Icons.photo_library_outlined, label: 'Media, files & links')),
      const PopupMenuItem(value: 'wallpaper', child: _MenuRow(icon: Icons.wallpaper_outlined, label: 'Wallpaper')),
      const PopupMenuItem(value: 'voice', child: _MenuRow(icon: Icons.call_outlined, label: 'Voice call')),
      const PopupMenuItem(value: 'video', child: _MenuRow(icon: Icons.videocam_outlined, label: 'Video call')),
      const PopupMenuDivider(),
      ...listMenuItems(c, muted: muted),
    ];
  }

  static String callRoomName(int conversationId) {
    return 'messaging-call-$conversationId-${const Uuid().v4().substring(0, 8)}';
  }

  static Future<void> handleMenuSelection(
    BuildContext context, {
    required String value,
    required ConversationSummary conversation,
    required VoidCallback onChanged,
    required bool muted,
  }) async {
    switch (value) {
      case 'info':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationInfoScreen(conversation: conversation)));
      case 'pin':
        await pin(context, conversation, onChanged: onChanged);
      case 'mute':
        await context.read<MessengerPreferences>().toggleMute(conversation.id);
        onChanged();
      case 'archive':
        await archive(context, conversation, onChanged: onChanged);
      case 'clear':
        await clear(context, conversation, onChanged: onChanged);
      case 'export':
        await exportChat(context, conversation);
      case 'wallpaper':
        if (context.mounted) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPickerScreen()));
        }
      case 'voice':
        startCall(context, conversation, video: false);
      case 'video':
        startCall(context, conversation, video: true);
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: messengerExt(context).subtext),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

Future<ConversationSummary?> showNewChatFlow(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(backgroundColor: MessengerPalette.whatsAppGreen, child: const Icon(Icons.person_add, color: Colors.white)),
            title: const Text('New chat'),
            onTap: () => Navigator.pop(ctx, 'direct'),
          ),
          ListTile(
            leading: CircleAvatar(backgroundColor: MessengerPalette.accent, child: const Icon(Icons.group_add, color: Colors.white)),
            title: const Text('New group'),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return null;
  if (choice == 'direct') return showNewDirectChatSheet(context);
  return Navigator.push<ConversationSummary>(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
}

Future<ConversationSummary?> showNewDirectChatSheet(BuildContext context) {
  return showModalBottomSheet<ConversationSummary>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DirectChatPicker(),
  );
}

class _DirectChatPicker extends StatefulWidget {
  const _DirectChatPicker();
  @override
  State<_DirectChatPicker> createState() => _DirectChatPickerState();
}

class _DirectChatPickerState extends State<_DirectChatPicker> {
  late MessagingRepository _repo;
  final _search = TextEditingController();
  List<AccessibleUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    _load();
    _search.addListener(() => _load(_search.text.trim()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String? q]) async {
    setState(() => _loading = true);
    try {
      final users = await _repo.fetchAccessibleUsers(search: q?.isEmpty == true ? null : q);
      if (mounted) setState(() => _users = users);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, sc) => Column(
        children: [
          AppBar(title: const Text('New chat'), automaticallyImplyLeading: false, actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: _search, decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search))),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: sc,
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      return ListTile(
                        leading: MessengerAvatar(label: u.initials, radius: 22),
                        title: Text(u.name),
                        subtitle: u.email != null ? Text(u.email!) : null,
                        onTap: () async {
                          try {
                            final c = await _repo.createConversation(type: 'direct', participantIds: [u.id]);
                            if (mounted) Navigator.pop(context, c);
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
