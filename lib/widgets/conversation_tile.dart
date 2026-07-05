import 'package:flutter/material.dart';

import '../core/models/api_models.dart';
import '../theme/messenger_theme.dart';
import 'messenger_avatar.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.selected = false,
    this.onInfo,
    this.onLongPressMenu,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final bool selected;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onInfo ?? onTap,
                child: MessengerAvatar(
                  label: c.avatarInitials ?? '?',
                  radius: 22,
                  isGroup: c.isGroup,
                  online: c.online,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (c.isPinned) ...[
                          Icon(Icons.push_pin, size: 12, color: ext.subtext),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 15,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (c.lastMessageTime != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            c.lastMessageTime!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: hasUnread ? MessengerPalette.whatsAppGreen : ext.subtext,
                              fontSize: 11,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (c.isMuted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.notifications_off_outlined, size: 12, color: ext.subtext),
                          ),
                        Expanded(
                          child: Text(
                            c.lastMessagePreview ?? (c.isGroup ? 'Group chat' : 'Start a conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: hasUnread ? theme.colorScheme.onSurface : ext.subtext,
                              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                              fontSize: 13,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ext.unreadBadge,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
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
