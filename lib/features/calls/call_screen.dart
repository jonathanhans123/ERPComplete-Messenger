import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/calls/call_session_controller.dart';
import '../../core/notifications/messenger_notification_service.dart';
import '../../theme/messenger_theme.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncCallNotification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final call = context.read<CallSessionController>();
    if (call.active && (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      _syncCallNotification();
    }
  }

  void _syncCallNotification() {
    final call = context.read<CallSessionController>();
    if (call.active && call.conversation != null) {
      MessengerNotificationService.instance.showOngoingCallNotification(
        title: call.conversation!.title,
        isVideo: call.isVideo,
      );
    }
  }

  Future<void> _endCall(CallSessionController call) async {
    await MessengerNotificationService.instance.clearOngoingCallNotification();
    await call.end();
    if (mounted) Navigator.pop(context);
  }

  void _minimize(CallSessionController call) {
    call.minimize();
    _syncCallNotification();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallSessionController>();
    final conv = call.conversation;
    if (conv == null) {
      return const Scaffold(body: Center(child: Text('No active call')));
    }

    final statusText = call.connecting
        ? 'Connecting…'
        : call.error != null
            ? 'Connection problem'
            : call.connected
                ? (call.isVideo ? 'Video call in progress' : 'Voice call in progress')
                : 'Calling…';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize(call);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Back to chat',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => _minimize(call),
          ),
          title: Text('${call.isVideo ? 'Video' : 'Voice'} · ${conv.title}'),
          actions: [
            IconButton(
              tooltip: 'Minimize',
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: () => _minimize(call),
            ),
          ],
        ),
        body: call.connecting
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : call.error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(call.isVideo ? Icons.videocam_off : Icons.call_end, color: Colors.white70, size: 48),
                          const SizedBox(height: 12),
                          Text(call.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: call.retryConnection, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (call.isVideo && !call.cameraOff)
                        Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam, size: 72, color: Colors.white.withValues(alpha: 0.35)),
                                const SizedBox(height: 12),
                                Text('Camera preview', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF1F2C34), Color(0xFF0B141A)],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 56,
                                  backgroundColor: MessengerPalette.whatsAppGreen,
                                  child: Text(conv.avatarInitials ?? '?', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(height: 20),
                                Text(conv.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(statusText, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _Control(icon: call.muted ? Icons.mic_off : Icons.mic, label: call.muted ? 'Unmute' : 'Mute', onTap: call.toggleMute),
                                if (call.isVideo)
                                  _Control(
                                    icon: call.cameraOff ? Icons.videocam_off : Icons.videocam,
                                    label: call.cameraOff ? 'Camera on' : 'Camera off',
                                    onTap: call.toggleCamera,
                                  ),
                                _Control(icon: Icons.call_end, label: 'End', color: MessengerPalette.danger, onTap: () => _endCall(call)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? Colors.white.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 56, height: 56, child: Icon(icon, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
