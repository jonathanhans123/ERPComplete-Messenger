import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_repository.dart';
import '../core/messaging/messaging_repository.dart';
import '../core/models/api_models.dart';
import 'messenger_avatar.dart';

/// Bottom sheet to pick one or more users (new group, add members, etc.).
Future<Set<int>?> showMemberPickerSheet(
  BuildContext context, {
  required String title,
  Set<int> initialSelected = const {},
  Set<int> excludeIds = const {},
  bool requireSelection = true,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MemberPickerSheet(
      title: title,
      initialSelected: initialSelected,
      excludeIds: excludeIds,
      requireSelection: requireSelection,
    ),
  );
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({
    required this.title,
    required this.initialSelected,
    required this.excludeIds,
    required this.requireSelection,
  });

  final String title;
  final Set<int> initialSelected;
  final Set<int> excludeIds;
  final bool requireSelection;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  late MessagingRepository _repo;
  final _search = TextEditingController();
  List<AccessibleUser> _users = [];
  late Set<int> _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
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
      if (mounted) {
        setState(() => _users = users.where((u) => !widget.excludeIds.contains(u.id)).toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _done() {
    if (widget.requireSelection && _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one person')));
      return;
    }
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, sc) => Column(
        children: [
          AppBar(
            title: Text(widget.title),
            automaticallyImplyLeading: false,
            actions: [
              TextButton(onPressed: _done, child: const Text('Done')),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
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
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Search people', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: sc,
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
