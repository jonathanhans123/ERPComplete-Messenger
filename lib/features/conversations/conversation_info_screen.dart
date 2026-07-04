import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/member_picker_sheet.dart';
import '../../widgets/messenger_avatar.dart';
import '../settings/settings_screen.dart';
import 'conversation_actions.dart';

class ConversationInfoScreen extends StatefulWidget {
  const ConversationInfoScreen({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  State<ConversationInfoScreen> createState() => _ConversationInfoScreenState();
}

class _ConversationInfoScreenState extends State<ConversationInfoScreen> {
  ConversationDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthRepository>();
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    try {
      final d = await repo.fetchConversation(widget.conversation.id);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  MessagingRepository _repo() {
    final auth = context.read<AuthRepository>();
    return MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final d = _detail;
    final c = widget.conversation;
    final prefs = context.watch<MessengerPreferences>();
    final muted = prefs.isMuted(c.id);

    return Scaffold(
      appBar: AppBar(title: Text(c.isGroup ? 'Group info' : 'Contact info')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          MessengerAvatar(label: c.avatarInitials ?? '?', radius: 48, isGroup: c.isGroup, online: c.online),
                          const SizedBox(height: 12),
                          Text(d?.title ?? c.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                          if (d?.description != null && d!.description!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(d.description!, textAlign: TextAlign.center, style: TextStyle(color: ext.subtext)),
                          ],
                          if (!c.isGroup && c.online == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('online', style: TextStyle(color: MessengerPalette.whatsAppGreen, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _QuickActions(
                      conversation: c,
                      muted: muted,
                      onChanged: _load,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.wallpaper_outlined),
                      title: const Text('Chat wallpaper'),
                      subtitle: Text(ChatWallpaper.byId(prefs.wallpaperId).name),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPickerScreen())),
                    ),
                    const Divider(height: 32),
                    if (d != null && d.participants.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('${d.participants.length} participants', style: TextStyle(color: ext.subtext, fontWeight: FontWeight.w600)),
                          ),
                          if (c.isGroup)
                            TextButton.icon(
                              onPressed: () => _addMembers(context, d),
                              icon: const Icon(Icons.person_add_outlined, size: 18),
                              label: const Text('Add'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...d.participants.map(
                        (p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: MessengerAvatar(label: p.initials, radius: 22),
                          title: Text(p.name),
                          subtitle: p.email != null ? Text(p.email!) : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => UserProfileScreen(participant: p)),
                          ),
                        ),
                      ),
                    ],
                    if (c.isGroup) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _editGroup(context, d!),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit group'),
                      ),
                    ],
                  ],
                ),
    );
  }

  Future<void> _addMembers(BuildContext context, ConversationDetail detail) async {
    final existing = detail.participants.map((p) => p.id).toSet();
    final added = await showMemberPickerSheet(
      context,
      title: 'Add members',
      excludeIds: existing,
    );
    if (added == null || added.isEmpty) return;
    try {
      await _repo().updateGroup(
        conversationId: detail.id,
        name: detail.title,
        description: detail.description,
        participantIds: [...existing, ...added],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Members added')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _editGroup(BuildContext context, ConversationDetail detail) async {
    final nameCtrl = TextEditingController(text: detail.title);
    final descCtrl = TextEditingController(text: detail.description ?? '');
    final selected = detail.participants.map((p) => p.id).toSet();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
              const SizedBox(height: 8),
              Text('${selected.length} members', style: TextStyle(fontSize: 12, color: messengerExt(context).subtext)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await _repo().updateGroup(
        conversationId: detail.id,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        participantIds: selected.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group updated')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.conversation, required this.muted, required this.onChanged});

  final ConversationSummary conversation;
  final bool muted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionChip(
          icon: Icons.call_outlined,
          label: 'Call',
          onTap: () => ConversationActions.startCall(context, conversation, video: false),
        ),
        _ActionChip(
          icon: Icons.videocam_outlined,
          label: 'Video',
          onTap: () => ConversationActions.startCall(context, conversation, video: true),
        ),
        _ActionChip(
          icon: muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          label: muted ? 'Unmute' : 'Mute',
          onTap: () async {
            await context.read<MessengerPreferences>().toggleMute(conversation.id);
            onChanged();
          },
        ),
        _ActionChip(
          icon: conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: conversation.isPinned ? 'Unpin' : 'Pin',
          onTap: () => ConversationActions.pin(context, conversation, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: MessengerPalette.whatsAppGreen.withValues(alpha: 0.12),
              child: Icon(icon, color: MessengerPalette.whatsAppGreen),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.participant});

  final ConversationParticipant participant;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: MessengerAvatar(label: participant.initials, radius: 52)),
          const SizedBox(height: 16),
          Center(child: Text(participant.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
          if (participant.email != null) Center(child: Text(participant.email!, style: TextStyle(color: ext.subtext))),
          const SizedBox(height: 32),
          if (participant.email != null)
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: Text(participant.email!),
            ),
        ],
      ),
    );
  }
}
