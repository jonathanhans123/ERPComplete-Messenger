import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../core/preferences/messenger_preferences.dart';
import 'chat_list_helpers.dart';

Future<void> showMessageActions(
  BuildContext context, {
  required ChatMessage message,
  required MessagingRepository repo,
  required int conversationId,
  required void Function(ChatMessage?) onUpdated,
  required void Function(ChatMessage) onReply,
}) async {
  final prefs = context.read<MessengerPreferences>();
  final starred = prefs.isMessageStarred(conversationId, message.id);
  final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis
                  .map(
                    (e) => IconButton(
                      icon: Text(e, style: const TextStyle(fontSize: 28)),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final updated = await repo.toggleReaction(message.id, e, fallback: message);
                          onUpdated(updated.copyWith(isStarred: starred));
                        } catch (err) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(err))));
                          }
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(ctx);
              onReply(message);
            },
          ),
          ListTile(
            leading: Icon(starred ? Icons.star : Icons.star_border),
            title: Text(starred ? 'Unstar' : 'Star'),
            onTap: () async {
              Navigator.pop(ctx);
              await prefs.toggleStarMessage(conversationId, message.id);
              onUpdated(message.copyWith(isStarred: !starred));
            },
          ),
          ListTile(
            leading: Icon(message.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(message.isPinned ? 'Unpin message' : 'Pin message'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final updated = await repo.togglePinMessage(message.id, !message.isPinned, fallback: message);
                onUpdated(updated.copyWith(isStarred: starred));
              } catch (err) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(err))));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.forward),
            title: const Text('Forward'),
            onTap: () async {
              Navigator.pop(ctx);
              await _forwardMessage(context, repo: repo, conversationId: conversationId, message: message);
            },
          ),
          if (message.isSent)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () async {
                Navigator.pop(ctx);
                final controller = TextEditingController(text: message.body);
                final newBody = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Edit message'),
                    content: TextField(controller: controller, maxLines: 4, autofocus: true),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, controller.text.trim()), child: const Text('Save')),
                    ],
                  ),
                );
                if (newBody != null && newBody.isNotEmpty && newBody != message.body) {
                  try {
                    final updated = await repo.updateMessage(message.id, newBody, fallback: message);
                    onUpdated(updated.copyWith(isStarred: starred, isEdited: true));
                  } catch (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(err))));
                    }
                  }
                }
              },
            ),
          if (message.isSent)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await repo.deleteMessage(message.id);
                  onUpdated(null);
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(err))));
                  }
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy text'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.body));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _forwardMessage(
  BuildContext context, {
  required MessagingRepository repo,
  required int conversationId,
  required ChatMessage message,
}) async {
  try {
    final targets = await fetchForwardTargets(repo, excludeConversationId: conversationId);
    if (!context.mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other chats to forward to')));
      return;
    }
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ForwardTargetSheet(targets: targets),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;
    await repo.forwardMessages(
      conversationId: conversationId,
      messageIds: [message.id],
      targetConversationIds: selected.toList(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message forwarded')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }
}

class _ForwardTargetSheet extends StatefulWidget {
  const _ForwardTargetSheet({required this.targets});

  final List<ConversationSummary> targets;

  @override
  State<_ForwardTargetSheet> createState() => _ForwardTargetSheetState();
}

class _ForwardTargetSheetState extends State<_ForwardTargetSheet> {
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, sc) => Column(
        children: [
          AppBar(
            title: const Text('Forward to'),
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
                child: const Text('Send'),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: widget.targets.length,
              itemBuilder: (_, i) {
                final c = widget.targets[i];
                final checked = _selected.contains(c.id);
                return CheckboxListTile(
                  title: Text(c.title),
                  subtitle: c.isGroup ? const Text('Group') : null,
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(c.id);
                    } else {
                      _selected.remove(c.id);
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
