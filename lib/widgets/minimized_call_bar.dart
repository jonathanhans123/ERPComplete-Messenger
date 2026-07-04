import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/messenger_notification_service.dart';
import '../core/calls/call_session_controller.dart';
import '../theme/messenger_theme.dart';

class MinimizedCallBar extends StatelessWidget {
  const MinimizedCallBar({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallSessionController>();
    if (!call.active || !call.minimized || call.conversation == null) {
      return const SizedBox.shrink();
    }
    final conv = call.conversation!;
    return Material(
      elevation: 6,
      color: const Color(0xFF1F2C34),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(call.isVideo ? Icons.videocam : Icons.call, color: MessengerPalette.whatsAppGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        call.isVideo ? 'Video call' : 'Voice call',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'End call',
                  onPressed: () async {
                    await MessengerNotificationService.instance.clearOngoingCallNotification();
                    await call.end();
                  },
                  icon: const Icon(Icons.call_end, color: MessengerPalette.danger),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
