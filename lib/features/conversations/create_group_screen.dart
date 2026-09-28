import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../widgets/messenger_avatar.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  late MessagingRepository _repo;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _search = TextEditingController();
  List<AccessibleUser> _allUsers = [];
  List<AccessibleUser> _users = [];
  final Set<int> _selected = {};
  bool _loadingUsers = true;
  bool _creating = false;
  String? _usersError;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    _loadUsers();
    // The server ignores the search query — filter locally for instant results.
    _search.addListener(_applyFilter);
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

  @override
  void dispose() {
    _search.removeListener(_applyFilter);
    _name.dispose();
    _description.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _loadingUsers = true);
    try {
      final users = await _repo.fetchAccessibleUsers();
      if (!mounted) return;
      setState(() {
        _allUsers = users;
        _usersError = null;
      });
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() => _usersError = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one member')));
      return;
    }
    setState(() => _creating = true);
    try {
      final conv = await _repo.createConversation(
        type: 'group',
        participantIds: _selected.toList(),
        name: name,
        description: _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, conv);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Group name', prefixIcon: Icon(Icons.groups_outlined))),
                const SizedBox(height: 8),
                TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description (optional)'), maxLines: 2),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final id = _selected.elementAt(i);
                  final u = _allUsers.where((x) => x.id == id).firstOrNull;
                  return Chip(
                    label: Text(u?.name ?? '$id'),
                    onDeleted: () => setState(() => _selected.remove(id)),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(controller: _search, decoration: const InputDecoration(hintText: 'Add members', prefixIcon: Icon(Icons.person_search_outlined))),
          ),
          Expanded(
            child: _loadingUsers && _allUsers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _usersError != null && _allUsers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_usersError!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _loadUsers, child: const Text('Retry')),
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
                                itemCount: _users.length,
                                itemBuilder: (_, i) {
                                  final u = _users[i];
                                  final checked = _selected.contains(u.id);
                                  return CheckboxListTile(
                                    secondary: MessengerAvatar(label: u.initials, radius: 20),
                                    title: Text(u.name),
                                    subtitle: u.email != null ? Text(u.email!) : null,
                                    value: checked,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selected.add(u.id);
                                      } else {
                                        _selected.remove(u.id);
                                      }
                                    }),
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
