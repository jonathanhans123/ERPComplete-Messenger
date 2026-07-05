import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Renders a LiveKit video track; hides immediately when disabled or disposed.
class SafeVideoTrack extends StatefulWidget {
  const SafeVideoTrack({
    super.key,
    required this.track,
    this.fit = VideoViewFit.cover,
    this.mirrorMode = VideoViewMirrorMode.auto,
  });

  final VideoTrack? track;
  final VideoViewFit fit;
  final VideoViewMirrorMode mirrorMode;

  @override
  State<SafeVideoTrack> createState() => _SafeVideoTrackState();
}

class _SafeVideoTrackState extends State<SafeVideoTrack> {
  bool _dead = false;

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dead) {
      return const ColoredBox(color: Colors.black);
    }
    final t = widget.track;
    if (t == null || t.muted) {
      return const ColoredBox(color: Colors.black);
    }
    return VideoTrackRenderer(
      t,
      fit: widget.fit,
      mirrorMode: widget.mirrorMode,
    );
  }
}
