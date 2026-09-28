import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_throttle_guard.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/cache/messenger_local_cache.dart';
import '../../core/messaging/messaging_broadcast_service.dart';
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

class _ConversationsScreenState extends State<ConversationsScreen> with WidgetsBindingObserver {
  late MessagingRepository _repo;
  ConversationFilter _filter = ConversationFilter.all;
  List<ConversationSummary> _items = [];
  bool _loading = true;
  String? _error;
  String? _rateLimitNote;
  final _search = TextEditingController();
  int _totalUnread = 0;
  StreamSubscription<MessagingBroadcastEvent>? _broadcastSub;
  MessagingBroadcastService? _broadcastService;
  VoidCallback? _broadcastStateListener;
  Timer? _searchDebounce;
  bool _loadInFlight = false;
  final _multiSelect = <int>{};
  bool _batchBusy = false;

  bool get _selecting => _multiSelect.isNotEmpty;

  void _toggleSelect(int id) {
    setState(() {
      if (!_multiSelect.remove(id)) _multiSelect.add(id);
    });
  }

  void _clearSelection() {
    if (_multiSelect.isEmpty) return;
    setState(() => _multiSelect.clear());
  }

  List<ConversationSummary> get _selectedConvs =>
      _items.where((c) => _multiSelect.contains(c.id)).toList();

  Future<void> _runBatch(String label, Future<void> Function(MessagingRepository repo, ConversationSummary c) op) async {
    final targets = _selectedConvs;
    if (targets.isEmpty || _batchBusy) return;
    setState(() => _batchBusy = true);
    final auth = context.read<AuthRepository>();
    final repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    var ok = 0;
    for (final c in targets) {
      try {
        await op(repo, c);
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _batchBusy = false;
      _multiSelect.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok == targets.length ? '$label ($ok chats)' : '$label: $ok of ${targets.length} done')),
    );
    await _load(silent: true);
  }

  Future<void> _batchClear() async {
    final n = _multiSelect.length;
    if (n == 0 || _batchBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Clear $n chats?'),
        content: const Text('Messages will be cleared for everyone in these chats.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await _runBatch('Chats cleared', (repo, c) => repo.clearChat(c.id));
  }

  Future<void> _batchDelete() async {
    final targets = _selectedConvs;
    if (targets.isEmpty || _batchBusy) return;
    final repo = ConversationActions.repoOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete ${targets.length} chats?'),
        content: const Text('Chats will be cleared and removed from your chat list. This cannot be undone.'),
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
    if (ok != true) return;
    setState(() => _batchBusy = true);
    var done = 0;
    for (final c in targets) {
      if (await ConversationActions.deleteQuiet(repo, c)) done++;
    }
    if (!mounted) return;
    setState(() {
      _batchBusy = false;
      _multiSelect.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done == targets.length ? 'Chats deleted ($done)' : 'Deleted $done of ${targets.length}')),
    );
    await _load(silent: true);
  }

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
    WidgetsBinding.instance.addObserver(this);
    _initRepo();
    _load();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeBroadcast());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After a long absence the server state may have changed completely
    // (e.g. database reset) — silently revalidate instead of trusting cache.
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_load(silent: true));
    }
  }

  void _subscribeBroadcast() {
    final auth = context.read<AuthRepository>();
    final broadcast = context.read<MessagingBroadcastService>();
    _broadcastService = broadcast;
    _broadcastSub?.cancel();
    _broadcastSub = broadcast.events.listen(_onBroadcastEvent);
    if (_broadcastStateListener != null) {
      broadcast.removeListener(_broadcastStateListener!);
    }
    _broadcastStateListener = () {
      if (!mounted) return;
      if (broadcast.isConnected && _items.isNotEmpty) {
        broadcast.syncConversations(_items);
      }
    };
    broadcast.addListener(_broadcastStateListener!);
    if (!broadcast.isConnected) {
      unawaited(broadcast.connect(auth));
    }
  }

  void _onBroadcastEvent(MessagingBroadcastEvent event) {
    if (!mounted) return;
    if (event.eventName != 'message.sent' && event.eventName != 'message.updated') return;

    final convId = event.conversationId;
    final data = event.data;
    final preview = data['body'] as String? ?? '';
    final msgType = data['type'] as String? ?? 'text';
    final time = data['time'] as String?;
    final sender = data['sender'];
    final senderId = sender is Map ? sender['id'] as int? : null;
    final auth = context.read<AuthRepository>();
    final isOwn = senderId != null && senderId == auth.userId;
    final isSelected = widget.selectedId == convId;

    final index = _items.indexWhere((c) => c.id == convId);
    if (index < 0) {
      unawaited(_load(silent: true));
      return;
    }

    final conv = _items[index];
    final unreadDelta = (event.eventName == 'message.sent' && !isOwn && !isSelected) ? 1 : 0;
    setState(() {
      _items = [
        for (var i = 0; i < _items.length; i++)
          if (i == index)
            ConversationSummary(
              id: conv.id,
              title: conv.title,
              avatarInitials: conv.avatarInitials,
              avatarUrl: conv.avatarUrl,
              lastMessagePreview: preview.isNotEmpty ? preview : conv.lastMessagePreview,
              lastMessageType: msgType,
              lastMessageTime: time ?? conv.lastMessageTime,
              unreadCount: conv.unreadCount + unreadDelta,
              isGroup: conv.isGroup,
              channelKind: conv.channelKind,
              isPinned: conv.isPinned,
              isMuted: conv.isMuted,
              isArchived: conv.isArchived,
              online: conv.online,
            )
          else
            _items[i],
      ];
      if (unreadDelta > 0) _totalUnread += unreadDelta;
    });
  }

  void _initRepo() {
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _broadcastSub?.cancel();
    final listener = _broadcastStateListener;
    if (listener != null) {
      _broadcastService?.removeListener(listener);
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    try {
      if (!silent) {
        final cached = await MessengerLocalCache.instance.loadConversations();
        if (cached.isNotEmpty && mounted) {
          setState(() {
            _items = cached;
            _loading = false;
          });
        } else if (!silent) {
          setState(() {
            _loading = true;
            _error = null;
            _rateLimitNote = null;
          });
        }
      }
      if (ApiThrottleGuard.instance.isBlocked) {
        if (mounted) {
          setState(() {
            _rateLimitNote = ApiThrottleGuard.instance.userMessage;
            _loading = false;
            _error = _items.isEmpty ? ApiThrottleGuard.instance.userMessage : null;
          });
        }
        return;
      }
      try {
        final q = _search.text.trim();
        final items = await _repo.fetchConversations(filter: _filter, search: q.isEmpty ? null : q);
        await MessengerLocalCache.instance.saveConversations(items);
        // Skip the extra unread-count request while searching — it doubles
        // request volume on every keystroke. Keep the last known count.
        int unread = _totalUnread;
        if (q.isEmpty) {
          try {
            unread = await _repo.fetchUnreadCount();
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _items = items;
            _totalUnread = unread;
            _rateLimitNote = null;
            _error = null;
          });
          context.read<MessagingBroadcastService>().syncConversations(items);
        }
      } catch (e) {
        if (mounted && !silent) {
          setState(() {
            if (_items.isEmpty) {
              _error = formatApiError(e);
            } else if (e is ApiException && e.statusCode == 429) {
              _rateLimitNote = formatApiError(e);
            } else {
              _rateLimitNote = formatApiError(e);
            }
          });
        }
      } finally {
        if (mounted && !silent) setState(() => _loading = false);
      }
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _newChat() async {
    final conv = await showNewChatFlow(context);
    if (conv != null && mounted) {
      // Open immediately; refresh the list in the background so a slow or
      // throttled reload can't leave the UI stuck.
      widget.onSelect(conv);
      unawaited(_load(silent: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final ext = messengerExt(context);
    final prefs = context.watch<MessengerPreferences>();

    final sel = _selectedConvs;
    final anyUnpinned = sel.any((c) => !c.isPinned);
    final anyUnarchived = sel.any((c) => !c.isArchived);
    final anyUnmuted = sel.any((c) => !prefs.isMuted(c.id) && !c.isMuted);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: _selecting
            ? AppBar(
                leading: IconButton(tooltip: 'Clear selection', onPressed: _clearSelection, icon: const Icon(Icons.close)),
                title: Text('${_multiSelect.length} selected'),
                actions: [
                  IconButton(
                    tooltip: anyUnpinned ? 'Pin' : 'Unpin',
                    onPressed: _batchBusy
                        ? null
                        : () => _runBatch(anyUnpinned ? 'Chats pinned' : 'Chats unpinned',
                            (repo, c) => repo.togglePinConversation(c.id, anyUnpinned)),
                    icon: Icon(anyUnpinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
                  IconButton(
                    tooltip: anyUnmuted ? 'Mute' : 'Unmute',
                    onPressed: _batchBusy
                        ? null
                        : () async {
                            for (final c in sel) {
                              final muted = prefs.isMuted(c.id) || c.isMuted;
                              if (muted == anyUnmuted) {
                                await prefs.toggleMute(c.id);
                              }
                            }
                            if (context.mounted) {
                              setState(() => _multiSelect.clear());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(anyUnmuted ? 'Chats muted (${sel.length})' : 'Chats unmuted (${sel.length})')),
                              );
                            }
                          },
                    icon: Icon(anyUnmuted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
                  ),
                  IconButton(
                    tooltip: anyUnarchived ? 'Archive' : 'Unarchive',
                    onPressed: _batchBusy
                        ? null
                        : () => _runBatch(anyUnarchived ? 'Chats archived' : 'Chats unarchived',
                            (repo, c) => repo.toggleArchiveConversation(c.id, anyUnarchived)),
                    icon: Icon(anyUnarchived ? Icons.archive_outlined : Icons.unarchive_outlined),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_batchBusy,
                    onSelected: (v) async {
                      switch (v) {
                        case 'all':
                          setState(() => _multiSelect.addAll(_items.map((c) => c.id)));
                        case 'info':
                          if (sel.length == 1 && mounted) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ConversationInfoScreen(conversation: sel.first)),
                            );
                          }
                        case 'export':
                          if (sel.length == 1 && mounted) {
                            await ConversationActions.exportChat(context, sel.first);
                          }
                        case 'clear':
                          await _batchClear();
                        case 'delete':
                          await _batchDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'all', child: Text('Select all')),
                      if (sel.length == 1) ...[
                        const PopupMenuItem(value: 'info', child: Text('Contact / group info')),
                        const PopupMenuItem(value: 'export', child: Text('Export chat')),
                      ],
                      const PopupMenuItem(value: 'clear', child: Text('Clear chats')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete chats', style: TextStyle(color: MessengerPalette.danger)),
                      ),
                    ],
                  ),
                ],
              )
            : AppBar(
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
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
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
          if (_rateLimitNote != null)
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final bannerBg = isDark ? const Color(0xFF3A2E00) : Colors.amber.shade100;
                final bannerFg = isDark ? const Color(0xFFFFE082) : const Color(0xFF6D4C00);
                return Material(
                  color: bannerBg,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, size: 18, color: bannerFg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _rateLimitNote!,
                            style: TextStyle(fontSize: 13, color: bannerFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          Expanded(child: _buildBody(ext, prefs)),
        ],
      ),
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
        separatorBuilder: (_, __) => Divider(height: 1, indent: 66, color: ext.subtext.withValues(alpha: 0.12)),
        itemBuilder: (context, index) {
          final c = _items[index];
          final muted = prefs.isMuted(c.id);
          return ConversationTile(
            conversation: c.copyWith(isMuted: muted || c.isMuted),
            selected: widget.selectedId == c.id,
            multiSelected: _multiSelect.contains(c.id),
            // Long-press enters multi-select (WhatsApp style). Single-chat
            // actions (info/export/clear/delete) live in the selection
            // toolbar's overflow menu once chats are selected.
            onTap: () => _selecting ? _toggleSelect(c.id) : widget.onSelect(c),
            onInfo: () => _selecting
                ? _toggleSelect(c.id)
                : Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationInfoScreen(conversation: c))),
            onLongPressMenu: () => _toggleSelect(c.id),
          );
        },
      ),
    );
  }
}
