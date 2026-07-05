import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calls/call_session_controller.dart';
import '../core/calls/incoming_call_actions.dart';
import '../core/calls/incoming_call_controller.dart';
import '../theme/messenger_theme.dart';
import 'messenger_avatar.dart';

/// Full-screen incoming call UI (in-app) with accept / decline.
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

    return AbsorbPointer(
      absorbing: _busy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Material(
          color: const Color(0xF0000000),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  const Spacer(),
                  Text(
                    video ? 'Incoming video call' : 'Incoming voice call',
                    style: const TextStyle(
                      color: MessengerPalette.whatsAppGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  MessengerAvatar(
                    label: conv.avatarInitials ?? '?',
                    radius: 56,
                    isGroup: conv.isGroup,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    invite.callerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (conv.title != invite.callerName) ...[
                    const SizedBox(height: 6),
                    Text(
                      conv.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                  const Spacer(),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _LargeCallAction(
                          icon: Icons.call_end,
                          label: 'Decline',
                          color: MessengerPalette.danger,
                          onPressed: () => _run(() => IncomingCallActions.decline(context, invite)),
                        ),
                        _LargeCallAction(
                          icon: video ? Icons.videocam : Icons.call,
                          label: 'Accept',
                          color: MessengerPalette.whatsAppGreen,
                          onPressed: () => _run(() => IncomingCallActions.accept(context, invite)),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LargeCallAction extends StatelessWidget {
  const _LargeCallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: 72, height: 72, child: Icon(icon, color: Colors.white, size: 32)),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ],
    );
  }
}
