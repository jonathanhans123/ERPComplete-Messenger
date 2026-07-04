import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/preferences/messenger_preferences.dart';
import '../../features/settings/settings_sheet.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/conversation_tile.dart';
import 'conversation_actions.dart';
import 'conversation_info_screen.dart';

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
  final _search = TextEditingController();
  int _totalUnread = 0;
  Timer? _refreshTimer;

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
    _search.addListener(_onSearchChanged);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  void _initRepo() {
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  void _onSearchChanged() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final q = _search.text.trim();
      final items = await _repo.fetchConversations(filter: _filter, search: q.isEmpty ? null : q);
      final unread = await _repo.fetchUnreadCount();
      if (mounted) {
        setState(() {
          _items = items;
          _totalUnread = unread;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _newChat() async {
    final conv = await showNewChatFlow(context);
    if (conv != null && mounted) {
      await _load();
      widget.onSelect(conv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final ext = messengerExt(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chats'),
            if (auth.userName != null)
              Text(auth.userName!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ext.subtext, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          if (_totalUnread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: ext.unreadBadge.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('$_totalUnread unread', style: TextStyle(color: ext.unreadBadge, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          IconButton(tooltip: 'Settings', onPressed: () => openSettings(context), icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        child: const Icon(Icons.chat_rounded),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search, color: ext.subtext),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  labelStyle: TextStyle(
                    color: selected ? MessengerPalette.whatsAppGreen : Theme.of(context).colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody(ext, context.watch<MessengerPreferences>())),
        ],
      ),
    );
  }

  Widget _buildBody(MessengerThemeExtension ext, MessengerPreferences prefs) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: ext.subtext),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: ext.subtext),
            const SizedBox(height: 12),
            Text('No conversations yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Start a new chat with your team', style: TextStyle(color: ext.subtext)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add), label: const Text('New chat')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: MessengerPalette.whatsAppGreen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => Divider(height: 1, indent: 78, color: ext.subtext.withValues(alpha: 0.15)),
        itemBuilder: (context, index) {
          final c = _items[index];
          final muted = prefs.isMuted(c.id);
          return ConversationTile(
            conversation: c.copyWith(isMuted: muted || c.isMuted),
            selected: widget.selectedId == c.id,
            onTap: () => widget.onSelect(c),
            onInfo: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationInfoScreen(conversation: c))),
            onLongPressMenu: () => ConversationActions.showListMenuSheet(
              context,
              conversation: c,
              onChanged: _load,
              muted: muted,
            ),
            onMenu: (value) => ConversationActions.handleMenuSelection(
              context,
              value: value,
              conversation: c,
              onChanged: _load,
              muted: muted,
            ),
          );
        },
      ),
    );
  }
}
