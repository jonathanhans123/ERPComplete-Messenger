import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/media/attachment_kind.dart';
import '../theme/messenger_theme.dart';

class NetworkMediaImage extends StatelessWidget {
  const NetworkMediaImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
    this.onTap,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        httpHeaders: url.contains('openstreetmap.org') ? const {'User-Agent': kOsmTileUserAgent} : null,
        placeholder: (_, __) => Container(
          width: width ?? 220,
          height: height ?? 160,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          width: width ?? 220,
          height: height ?? 160,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }
}

class FullScreenImageViewer extends StatelessWidget {
  const FullScreenImageViewer({super.key, required this.url, this.title});

  final String url;
  final String? title;

  static Future<void> open(BuildContext context, String url, {String? title}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FullScreenImageViewer(url: url, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title ?? 'Photo')),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class MediaUnavailableTile extends StatelessWidget {
  const MediaUnavailableTile({super.key, required this.label, required this.textColor, this.hint});

  final String label;
  final Color textColor;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                if (hint != null)
                  Text(hint!, style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImageMessageTile extends StatelessWidget {
  const ImageMessageTile({super.key, required this.url, this.onTap});

  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NetworkMediaImage(
      url: url,
      width: 240,
      height: 180,
      onTap: onTap ?? () => FullScreenImageViewer.open(context, url),
    );
  }
}

class VideoMessageTile extends StatelessWidget {
  const VideoMessageTile({super.key, required this.url, this.name, this.onTap});

  final String url;
  final String? name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ??
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: url, title: name))),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 240,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.videocam, color: Colors.white54, size: 48),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
          ),
        ],
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play video');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Video'),
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white70))
            : c == null || !c.value.isInitialized
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(c),
                        VideoProgressIndicator(c, allowScrubbing: true),
                        Positioned(
                          right: 12,
                          bottom: 36,
                          child: IconButton(
                            icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                            onPressed: () => setState(() {
                              c.value.isPlaying ? c.pause() : c.play();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({super.key, required this.url, this.durationLabel, required this.textColor});

  final String url;
  final String? durationLabel;
  final Color textColor;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted || d.inMilliseconds <= 0) return;
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final total = d.inSeconds;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  String get _label {
    final total = _duration.inSeconds > 0 ? _duration : _parseLabel(widget.durationLabel);
    if (_playing || _position.inSeconds > 0) {
      final t = total.inSeconds > 0 ? total : _position;
      return '${_format(_position)} / ${_format(t)}';
    }
    if (total.inSeconds > 0) return '0:00 / ${_format(total)}';
    return widget.durationLabel != null ? '0:00 / ${widget.durationLabel}' : '0:00 / 0:00';
  }

  Duration _parseLabel(String? label) {
    if (label == null) return Duration.zero;
    final part = label.contains('/') ? label.split('/').last.trim() : label.trim();
    final m = RegExp(r'^(\d+):(\d{2})$').firstMatch(part);
    if (m == null) return Duration.zero;
    return Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!));
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _error = null);
    try {
      await _player.play(UrlSource(widget.url));
    } catch (_) {
      if (mounted) setState(() => _error = 'Playback failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: MessengerPalette.whatsAppGreen,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggle,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_label, style: TextStyle(color: widget.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: widget.textColor.withValues(alpha: 0.7), fontSize: 11)),
          ),
      ],
    );
  }
}

class LocationMessageTile extends StatelessWidget {
  const LocationMessageTile({
    super.key,
    required this.latitude,
    required this.longitude,
    this.address,
    this.mapsUrl,
    required this.textColor,
  });

  final double latitude;
  final double longitude;
  final String? address;
  final String? mapsUrl;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final mapUrl = locationStaticMapUrl(latitude, longitude);
    final openUrl = mapsUrl ?? 'https://www.google.com/maps?q=$latitude,$longitude';
    final coords = '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

    return InkWell(
      onTap: () => launchUrl(Uri.parse(openUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 220,
              height: 110,
              child: CachedNetworkImage(
                imageUrl: mapUrl,
                fit: BoxFit.cover,
                httpHeaders: const {'User-Agent': kOsmTileUserAgent},
                placeholder: (_, __) => Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.map_outlined),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.location_on, color: MessengerPalette.whatsAppGreen),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: MessengerPalette.whatsAppGreen, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(address ?? 'Shared location', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(coords, style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LinkPreviewTile extends StatelessWidget {
  const LinkPreviewTile({super.key, required this.url, required this.textColor});

  final String url;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final domain = linkDomain(url) ?? url;
    final favicon = linkFaviconUrl(url);

    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (favicon.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: favicon,
                  width: 40,
                  height: 40,
                  errorWidget: (_, __, ___) => const Icon(Icons.link, size: 32),
                ),
              )
            else
              const Icon(Icons.link, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(domain, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(url, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileMessageTile extends StatelessWidget {
  const FileMessageTile({super.key, required this.name, this.url, required this.textColor});

  final String name;
  final String? url;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: url == null ? null : () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: textColor.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Flexible(child: Text(name, style: TextStyle(color: textColor, fontSize: 15))),
        ],
      ),
    );
  }
}

/// Chat wallpaper from custom image file or solid color.
class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    super.key,
    required this.customImagePath,
    required this.fallbackColor,
    required this.child,
  });

  final String? customImagePath;
  final Color fallbackColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = customImagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover),
        ),
        child: child,
      );
    }
    return ColoredBox(color: fallbackColor, child: child);
  }
}
