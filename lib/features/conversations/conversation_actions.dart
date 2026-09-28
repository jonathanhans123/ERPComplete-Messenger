import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/cache/messenger_local_cache.dart';
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
    if (ok != true || !context.mounted) return;
    try {
      await repoOf(context).clearChat(c.id);
      onChanged?.call();
      if (context.mounted) _snack(context, 'Chat cleared');
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  /// Deletes the conversation. Returns true when deleted so
  /// callers inside an open chat can pop back to the list.
  ///
  /// NOTE: the server currently exposes no delete-conversation endpoint, so
  /// this tries a native DELETE first (in case the backend adds one) and
  /// otherwise falls back to: clear all messages + archive (removes it from
  /// the chat list) + purge local cache.
  static Future<bool> delete(BuildContext context, ConversationSummary c, {VoidCallback? onChanged}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          c.isGroup
              ? '“${c.title}” will be cleared and removed from your chat list. This cannot be undone.'
              : 'Your chat with “${c.title}” will be cleared and removed from your chat list. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MessengerPalette.danger),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    try {
      final repo = repoOf(context);
      // The server deletes the chat for this user only. The old clear + archive fallback wiped the
      // history for everyone and made the chat vanish from the list.
      await repo.deleteConversation(c.id);
      await MessengerLocalCache.instance.deleteMessages(c.id);
      onChanged?.call();
      if (context.mounted) _snack(context, 'Chat deleted');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, formatApiError(e));
      return false;
    }
  }

  /// Headless delete used by multi-select (no per-chat dialog).
  /// Returns true on success.
  static Future<bool> deleteQuiet(MessagingRepository repo, ConversationSummary c) async {
    try {
      await repo.deleteConversation(c.id);
      await MessengerLocalCache.instance.deleteMessages(c.id);
      return true;
    } catch (_) {
      return false;
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
    // open() prefers the app navigator; the context is only a fallback.
    unawaited(CallScreenNavigator.open(context.mounted ? context : null));
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

  /// Rejoin a live call from the chat call message or banner.
  static Future<void> rejoinCallFromChat(
    BuildContext context,
    ConversationSummary conversation,
    ChatMessage callMessage,
  ) async {
    final auth = context.read<AuthRepository>();
    final call = context.read<CallSessionController>();
    final repo = repoOf(context);
    final meta = callMessage.callMeta;

    if (!callMessage.isRejoinableCall) {
      _snack(context, 'This call is no longer active');
      return;
    }

    if (isAlreadyInCall(
      call: call,
      conversationId: conversation.id,
      callSessionId: meta?.callSessionId,
    )) {
      if (!CallScreenNavigator.isOpen) {
        unawaited(CallScreenNavigator.open(context));
      }
      return;
    }

    if (!CallScreenNavigator.isOpen) {
      unawaited(CallScreenNavigator.open(context));
    }

    try {
      await call.joinExistingCall(
        conv: conversation,
        messagingRepo: repo,
        callerName: auth.userName ?? 'User',
        callMessage: callMessage,
      );
      if (!call.active) {
        CallScreenNavigator.popIfOpen();
        if (context.mounted) _snack(context, call.error ?? 'Could not rejoin call');
      }
    } catch (e) {
      CallScreenNavigator.popIfOpen();
      if (context.mounted) _snack(context, formatApiError(e));
    }
  }

  static bool isAlreadyInCall({
    required CallSessionController call,
    required int conversationId,
    String? callSessionId,
  }) {
    if (!call.active || !call.connected || callSessionId == null || callSessionId.isEmpty) {
      return false;
    }
    return call.conversation?.id == conversationId && call.sessionId == callSessionId;
  }

  static ChatMessage? latestRejoinableCall(Iterable<ChatMessage> messages) {
    final list = messages is List<ChatMessage> ? messages : messages.toList();
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].isRejoinableCall) return list[i];
    }
    return null;
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
      ('info', Icons.info_outline, 'Contact / group info', false),
      (conversation.isPinned ? 'pin' : 'pin', conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin, conversation.isPinned ? 'Unpin' : 'Pin', false),
      (muted ? 'mute' : 'mute', muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, muted ? 'Unmute' : 'Mute', false),
      (conversation.isArchived ? 'archive' : 'archive', conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, conversation.isArchived ? 'Unarchive' : 'Archive', false),
      ('clear', Icons.delete_sweep_outlined, 'Clear chat', false),
      ('export', Icons.download_outlined, 'Export chat', false),
      ('delete', Icons.delete_outline, 'Delete chat', true),
    ];
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map(
                (e) => ListTile(
                  leading: Icon(e.$2, color: e.$4 ? MessengerPalette.danger : null),
                  title: Text(e.$3, style: TextStyle(color: e.$4 ? MessengerPalette.danger : null)),
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
      const PopupMenuItem(
        value: 'delete',
        child: _MenuRow(icon: Icons.delete_outline, label: 'Delete chat', destructive: true),
      ),
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
    VoidCallback? onDeleted,
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
      case 'delete':
        final deleted = await delete(context, conversation, onChanged: onChanged);
        if (deleted) onDeleted?.call();
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
  const _MenuRow({required this.icon, required this.label, this.destructive = false});
  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? MessengerPalette.danger : messengerExt(context).subtext;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: destructive ? MessengerPalette.danger : null)),
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
            leading: const CircleAvatar(backgroundColor: MessengerPalette.whatsAppGreen, child: Icon(Icons.person_add, color: Colors.white)),
            title: const Text('New chat'),
            onTap: () => Navigator.pop(ctx, 'direct'),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: MessengerPalette.accent, child: Icon(Icons.group_add, color: Colors.white)),
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

Future<ConversationSummary?> showNewDirectChatSheet(BuildContext context) async {
  // Phase 1: pick a person. The sheet closes IMMEDIATELY on tap so double
  // taps can't fire multiple creates (which caused duplicates + black screen
  // from double-popping the sheet route).
  final picked = await showModalBottomSheet<AccessibleUser>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DirectChatPicker(),
  );
  if (!context.mounted || picked == null) return null;

  // Phase 2: create outside the sheet with a blocking progress dialog so
  // only one create can ever be in flight.
  final repo = ConversationActions.repoOf(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final conv = await repo.createConversation(type: 'direct', participantIds: [picked.id]);
    // The create endpoint returns the raw model (name is null for directs),
    // which shows up as "Conversation" + "?". Resolve the display title via
    // the formatted detail, and revive the chat if a previous delete/archive
    // had hidden it — otherwise re-adding keeps returning an invisible chat.
    ConversationSummary summary = conv;
    try {
      await repo.toggleArchiveConversation(conv.id, false);
    } catch (_) {}
    try {
      summary = (await repo.fetchConversation(conv.id)).toSummary();
    } catch (_) {}
    if (context.mounted) Navigator.pop(context); // dismiss progress
    return summary;
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // dismiss progress
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
    return null;
  }
}

class _DirectChatPicker extends StatefulWidget {
  const _DirectChatPicker();
  @override
  State<_DirectChatPicker> createState() => _DirectChatPickerState();
}

class _DirectChatPickerState extends State<_DirectChatPicker> {
  late MessagingRepository _repo;
  final _search = TextEditingController();
  List<AccessibleUser> _allUsers = [];
  List<AccessibleUser> _users = [];
  bool _loading = true;
  String? _error;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    _load();
    // The server ignores the search query, so filter the fetched list
    // locally — instant results and zero extra API calls per keystroke.
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.removeListener(_applyFilter);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final users = await _repo.fetchAccessibleUsers();
      if (!mounted) return;
      setState(() {
        _allUsers = users;
        _error = null;
      });
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    if (!mounted) return;
    final q = _search.text.trim().toLowerCase();
    setState(() {
      _users = q.isEmpty
          ? _allUsers
          : _allUsers
              .where((u) => u.name.toLowerCase().contains(q) || (u.email?.toLowerCase().contains(q) ?? false))
              .toList();
    });
  }

  void _pick(AccessibleUser user) {
    if (_picked) return;
    _picked = true;
    // Close immediately — creation happens after the sheet is gone.
    Navigator.pop(context, user);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                const SizedBox(width: 48),
                const Expanded(
                  child: Text(
                    'New chat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(controller: _search, decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search))),
          ),
          Expanded(
            child: _loading && _allUsers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _allUsers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : _allUsers.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No people available.\nOnly users sharing your business units show up here.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _users.isEmpty
                            ? const Center(child: Text('No match for that search'))
                            : ListView.builder(
                        controller: sc,
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return ListTile(
                            leading: MessengerAvatar(label: u.initials, radius: 22),
                            title: Text(u.name),
                            subtitle: u.email != null ? Text(u.email!) : null,
                            enabled: !_picked,
                            onTap: () => _pick(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
