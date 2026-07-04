import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final MessagingRepository _repo;
  List<ConversationSummary> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetchConversations();
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
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Video calls (coming soon)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('LiveKit video — phase 2')),
              );
            },
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No conversations yet')),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = _items[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(c.title.isNotEmpty ? c.title[0].toUpperCase() : '?'),
                              ),
                              title: Text(c.title),
                              subtitle: c.lastMessagePreview != null
                                  ? Text(c.lastMessagePreview!, maxLines: 1, overflow: TextOverflow.ellipsis)
                                  : null,
                              trailing: c.unreadCount > 0
                                  ? CircleAvatar(
                                      radius: 12,
                                      child: Text('${c.unreadCount}', style: const TextStyle(fontSize: 11)),
                                    )
                                  : null,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Chat thread #${c.id} — phase 2')),
                                );
                              },
                            );
                          },
                        ),
                ),
    );
  }
}
