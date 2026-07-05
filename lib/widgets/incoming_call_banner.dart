import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calls/call_session_controller.dart';
import '../core/calls/incoming_call_actions.dart';
import '../core/calls/incoming_call_controller.dart';
import '../theme/messenger_theme.dart';
import 'messenger_avatar.dart';

/// Top-of-screen incoming call banner with accept / reject actions.
class IncomingCallBanner extends StatelessWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final callSession = context.watch<CallSessionController>();
    final incoming = context.watch<IncomingCallController>();
    final invite = incoming.pending;

    if (callSession.isActive || invite == null) {
      return const SizedBox.shrink();
    }

    final video = invite.isVideo;
    final conv = invite.conversation;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1F2C34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                MessengerAvatar(
                  label: conv.avatarInitials ?? '?',
                  radius: 22,
                  isGroup: conv.isGroup,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        video ? 'Incoming video call' : 'Incoming voice call',
                        style: const TextStyle(
                          color: MessengerPalette.whatsAppGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        invite.callerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (conv.title != invite.callerName)
                        Text(
                          conv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RoundActionButton(
                  icon: Icons.call_end,
                  color: MessengerPalette.danger,
                  tooltip: 'Decline',
                  onPressed: () => IncomingCallActions.decline(context, invite),
                ),
                const SizedBox(width: 10),
                _RoundActionButton(
                  icon: video ? Icons.videocam : Icons.call,
                  color: MessengerPalette.whatsAppGreen,
                  tooltip: video ? 'Answer video' : 'Answer',
                  onPressed: () => IncomingCallActions.accept(context, invite),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
