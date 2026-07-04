import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';
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
  List<AccessibleUser> _users = [];
  final Set<int> _selected = {};
  bool _loadingUsers = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthRepository>();
    _repo = MessagingRepository(() => auth.client(), currentUserId: auth.userId);
    _loadUsers();
    _search.addListener(() => _loadUsers(_search.text.trim()));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUsers([String? q]) async {
    setState(() => _loadingUsers = true);
    try {
      final users = await _repo.fetchAccessibleUsers(search: q?.isEmpty == true ? null : q);
      if (mounted) setState(() => _users = users);
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
                  final u = _users.where((x) => x.id == id).firstOrNull;
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
            child: _loadingUsers
                ? const Center(child: CircularProgressIndicator())
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
