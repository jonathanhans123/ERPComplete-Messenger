import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calls/call_session_controller.dart';
import '../core/notifications/messenger_notification_service.dart';
import '../theme/messenger_theme.dart';

/// Visible whenever a call is active — tap to return/rejoin, end to hang up.
class MinimizedCallBar extends StatelessWidget {
  const MinimizedCallBar({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallSessionController>();
    if (!call.active || call.conversation == null) {
      return const SizedBox.shrink();
    }

    final conv = call.conversation!;
    final needsRejoin = call.needsRejoin;
    final groupLike = call.isGroupLikeCall || conv.isGroup;

    return Material(
      elevation: 6,
      color: const Color(0xFF1F2C34),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                call.isVideo ? Icons.videocam : Icons.call,
                color: MessengerPalette.whatsAppGreen,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onExpand,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        groupLike
                            ? (call.isVideo ? 'Group video call' : 'Group voice call')
                            : (call.isVideo ? 'Video call' : 'Voice call'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        needsRejoin
                            ? (groupLike ? 'Tap Rejoin group call · ${conv.title}' : 'Tap Rejoin call · ${conv.title}')
                            : (call.minimized
                                ? 'Tap to return to call · ${conv.title}'
                                : conv.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (needsRejoin)
                TextButton(
                  onPressed: () {
                    unawaited(call.rejoinCall());
                    onExpand();
                  },
                  child: Text(
                    groupLike ? 'Rejoin' : 'Rejoin',
                    style: const TextStyle(color: MessengerPalette.whatsAppGreen, fontWeight: FontWeight.w600),
                  ),
                ),
              IconButton(
                tooltip: 'End call',
                onPressed: () {
                  unawaited(MessengerNotificationService.instance.clearAllCallNotifications());
                  unawaited(call.end());
                },
                icon: const Icon(Icons.call_end, color: MessengerPalette.danger),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
