import 'package:flutter/material.dart';

import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';

/// LiveKit native SDK integration is phase 2 — this screen mirrors video-app join flow
/// (token from POST /api/v1/messaging/live-call/token) and shows call UI shell.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.conversation,
    required this.repo,
    required this.displayName,
  });

  final ConversationSummary conversation;
  final MessagingRepository repo;
  final String displayName;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  LiveCallToken? _token;
  bool _loading = true;
  String? _error;
  bool _muted = false;
  bool _cameraOff = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = MessagingRepository.messengerCallRoom(widget.conversation.id);
      final token = await widget.repo.liveCallToken(room: room, displayName: widget.displayName);
      if (mounted) setState(() => _token = token);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('Call · ${widget.conversation.title}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off, color: Colors.white70, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _connect, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: MessengerColors.primary,
                              child: Text(
                                widget.conversation.avatarInitials ?? '?',
                                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(widget.conversation.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(
                              'Room ready · LiveKit SDK connects in next update',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                              textAlign: TextAlign.center,
                            ),
                            if (_token != null) ...[
                              const SizedBox(height: 12),
                              Text('${_token!.url}', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                            ],
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
                              _CallControl(
                                icon: _muted ? Icons.mic_off : Icons.mic,
                                label: _muted ? 'Unmute' : 'Mute',
                                onTap: () => setState(() => _muted = !_muted),
                              ),
                              _CallControl(
                                icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                                label: _cameraOff ? 'Camera on' : 'Camera off',
                                onTap: () => setState(() => _cameraOff = !_cameraOff),
                              ),
                              _CallControl(
                                icon: Icons.call_end,
                                label: 'End',
                                color: MessengerColors.danger,
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({required this.icon, required this.label, required this.onTap, this.color});

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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
      ],
    );
  }
}
