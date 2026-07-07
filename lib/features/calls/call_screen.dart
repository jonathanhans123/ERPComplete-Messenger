import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../core/calls/call_screen_navigator.dart';
import '../../core/calls/call_session_controller.dart';
import '../../core/notifications/messenger_notification_service.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/safe_video_track.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  String? _shownStatusMessage;
  late CallSessionController _call;
  bool _popping = false;
  bool _minimizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _call = context.read<CallSessionController>();
    _call.addListener(_onCallStateChanged);
    _syncCallNotification();
  }

  @override
  void dispose() {
    _call.removeListener(_onCallStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!_call.active && mounted && !_popping) {
      _popCallScreen();
    }
  }

  void _popCallScreen() {
    if (_popping || !mounted) return;
    _popping = true;
    unawaited(MessengerNotificationService.instance.clearAllCallNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CallScreenNavigator.popIfOpen();
      _popping = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_call.active && (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      _syncCallNotification();
    }
  }

  void _syncCallNotification() {
    if (_call.active && _call.conversation != null) {
      MessengerNotificationService.instance.showOngoingCallNotification(
        title: _call.conversation!.title,
        isVideo: _call.isVideo,
      );
    }
  }

  void _endCall(CallSessionController call) {
    if (_popping) return;
    HapticFeedback.mediumImpact();
    unawaited(MessengerNotificationService.instance.clearAllCallNotifications());
    unawaited(call.end());
    _popCallScreen();
  }

  void _minimize(CallSessionController call) {
    if (_popping || _minimizing || !call.active) return;
    _minimizing = true;
    call.minimize();
    unawaited(
      MessengerNotificationService.instance.showOngoingCallNotification(
        title: call.conversation?.title ?? 'Call',
        isVideo: call.isVideo,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CallScreenNavigator.popIfOpen();
      _minimizing = false;
    });
  }

  void _maybeShowStatus(CallSessionController call) {
    final msg = call.statusMessage;
    if (msg == null || msg == _shownStatusMessage || !mounted) return;
    _shownStatusMessage = msg;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showDeviceSheet(CallSessionController call) async {
    final audioInputs = await call.listAudioInputs();
    final videoInputs = call.isVideo ? await call.listVideoInputs() : const <MediaDevice>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Call devices', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            if (audioInputs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Microphone', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              ...audioInputs.map(
                (d) => ListTile(
                  leading: const Icon(Icons.mic, color: Colors.white70),
                  title: Text(d.label.isNotEmpty ? d.label : 'Microphone', style: const TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await call.selectAudioInput(d);
                  },
                ),
              ),
            ],
            if (videoInputs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Camera', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              ...videoInputs.map(
                (d) => ListTile(
                  leading: const Icon(Icons.videocam, color: Colors.white70),
                  title: Text(d.label.isNotEmpty ? d.label : 'Camera', style: const TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await call.selectVideoInput(d);
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallSessionController>();

    if (!call.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_popping) _popCallScreen();
      });
      return const Scaffold(
        backgroundColor: Color(0xFF0B141A),
        body: SizedBox.shrink(),
      );
    }

    final conv = call.conversation;
    if (conv == null) {
      return const Scaffold(body: Center(child: Text('No active call')));
    }

    _maybeShowStatus(call);

    final statusText = call.connecting
        ? 'Connecting…'
        : call.error != null
            ? 'Connection problem'
            : call.connected
                ? (call.isVideo ? 'Video call in progress' : 'Voice call in progress')
                : 'Calling…';

    final canRenderVideo = call.active && call.connected && !call.isEnding;
    final remoteVideo = canRenderVideo ? call.remoteVideoTrack : null;
    final localVideo = canRenderVideo ? call.localVideoTrack : null;
    final showVideo = call.isVideo && canRenderVideo && !call.cameraOff;

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
            if (call.connected)
              IconButton(
                tooltip: 'Devices',
                icon: const Icon(Icons.settings_input_component_outlined),
                onPressed: () => _showDeviceSheet(call),
              ),
            IconButton(
              tooltip: 'Minimize',
              icon: const Icon(Icons.minimize_rounded),
              onPressed: () => _minimize(call),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo && remoteVideo != null)
              SafeVideoTrack(track: remoteVideo, fit: VideoViewFit.cover)
            else if (showVideo && localVideo != null)
              SafeVideoTrack(
                track: localVideo,
                fit: VideoViewFit.cover,
                mirrorMode: VideoViewMirrorMode.mirror,
              )
            else
              _VoiceBackdrop(conv: conv, statusText: statusText),
            if (showVideo && localVideo != null && remoteVideo != null)
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 108,
                    height: 152,
                    child: SafeVideoTrack(
                      track: localVideo,
                      fit: VideoViewFit.cover,
                      mirrorMode: VideoViewMirrorMode.mirror,
                    ),
                  ),
                ),
              ),
            if (call.connecting)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  color: MessengerPalette.whatsAppGreen,
                ),
              ),
            if (call.error != null)
              Center(
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
                      _Control(
                        icon: call.muted ? Icons.mic_off : Icons.mic,
                        label: call.muted ? 'Unmute' : 'Mute',
                        onTap: call.toggleMute,
                      ),
                      if (!call.isVideo)
                        _Control(
                          icon: Icons.videocam,
                          label: 'Video',
                          onTap: call.upgradeToVideo,
                        ),
                      if (call.isVideo && !call.cameraOff && (Platform.isAndroid || Platform.isIOS))
                        _Control(
                          icon: Icons.cameraswitch,
                          label: 'Flip',
                          onTap: call.flipCamera,
                        ),
                      if (call.isVideo)
                        _Control(
                          icon: call.cameraOff ? Icons.videocam_off : Icons.videocam,
                          label: call.cameraOff ? 'Camera on' : 'Camera off',
                          onTap: call.toggleCamera,
                        ),
                      if (call.canToggleSpeaker && (Platform.isAndroid || Platform.isIOS))
                        _Control(
                          icon: call.loudspeakerOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
                          label: call.loudspeakerOn ? 'Speaker' : 'Earpiece',
                          onTap: call.toggleLoudspeaker,
                        ),
                      _Control(
                        icon: Icons.call_end,
                        label: 'End',
                        color: MessengerPalette.danger,
                        onTap: () => _endCall(call),
                      ),
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

class _VoiceBackdrop extends StatelessWidget {
  const _VoiceBackdrop({required this.conv, required this.statusText});

  final ConversationSummary conv;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: Text(
                conv.avatarInitials ?? '?',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),
            Text(conv.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(statusText, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
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
