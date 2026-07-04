import 'package:flutter/material.dart';

import '../core/models/api_models.dart';
import '../features/conversations/conversation_actions.dart';
import '../theme/messenger_theme.dart';
import 'messenger_avatar.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.selected = false,
    this.onMenu,
    this.onInfo,
    this.onLongPressMenu,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final bool selected;
  final void Function(String value)? onMenu;
  final VoidCallback? onInfo;
  final VoidCallback? onLongPressMenu;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final theme = Theme.of(context);
    final c = conversation;
    final hasUnread = c.unreadCount > 0;

    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.08) : theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPressMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: onInfo ?? onTap,
                child: MessengerAvatar(label: c.avatarInitials ?? '?', isGroup: c.isGroup, online: c.online),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (c.lastMessageTime != null)
                          Text(c.lastMessageTime!, style: theme.textTheme.labelSmall?.copyWith(color: ext.subtext, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.lastMessagePreview ?? (c.isGroup ? 'Group chat' : 'Start a conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: hasUnread ? theme.colorScheme.onSurface : ext.subtext,
                              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (c.isPinned) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.push_pin, size: 14, color: ext.subtext)),
                        if (c.isMuted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.notifications_off_outlined, size: 14, color: ext.subtext)),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: ext.unreadBadge, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                        if (onMenu != null) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, size: 20, color: ext.subtext),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onSelected: onMenu,
                            itemBuilder: (_) => ConversationActions.listMenuItems(c, muted: c.isMuted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
