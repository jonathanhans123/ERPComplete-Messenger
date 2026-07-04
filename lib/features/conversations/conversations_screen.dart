import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    required this.onSelect,
    this.selectedId,
  });

  final void Function(ConversationSummary conversation) onSelect;
  final int? selectedId;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late MessagingRepository _repo;
  ConversationFilter _filter = ConversationFilter.all;
  List<ConversationSummary> _items = [];
  bool _loading = true;
  String? _error;

  static const _filters = [
    (ConversationFilter.all, 'All'),
    (ConversationFilter.unread, 'Unread'),
    (ConversationFilter.groups, 'Groups'),
    (ConversationFilter.teams, 'Teams'),
    (ConversationFilter.operations, 'Ops'),
    (ConversationFilter.archived, 'Archived'),
  ];

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetchConversations(filter: _filter);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    return Scaffold(
      backgroundColor: MessengerColors.bgPrimary,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Messages'),
            if (auth.userName != null)
              Text(auth.userName!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: MessengerColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Sign out', onPressed: () => auth.logout(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (filter, label) = _filters[index];
                final selected = _filter == filter;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filter = filter);
                    _load();
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
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
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No conversations'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final c = _items[index];
          final selected = widget.selectedId == c.id;
          return Material(
            color: selected ? MessengerColors.primary.withValues(alpha: 0.08) : MessengerColors.bgPrimary,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: c.isGroup ? MessengerColors.sentBubble : MessengerColors.primary,
                    child: Text(c.avatarInitials ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  if (c.online == true)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: MessengerColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      ),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: c.unreadCount > 0 ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                  if (c.lastMessageTime != null)
                    Text(c.lastMessageTime!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: MessengerColors.textSecondary)),
                ],
              ),
              subtitle: Text(
                c.lastMessagePreview ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.unreadCount > 0 ? MessengerColors.textPrimary : MessengerColors.textSecondary),
              ),
              trailing: c.unreadCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: MessengerColors.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('${c.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    )
                  : (c.isPinned ? const Icon(Icons.push_pin, size: 16, color: MessengerColors.textSecondary) : null),
              onTap: () => widget.onSelect(c),
            ),
          );
        },
      ),
    );
  }
}
