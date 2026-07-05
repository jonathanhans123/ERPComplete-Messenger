import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/media/attachment_kind.dart';
import '../core/models/api_models.dart';

class MediaViewerItem {
  const MediaViewerItem({required this.url, required this.isVideo, this.title});

  final String url;
  final bool isVideo;
  final String? title;
}

/// Swipeable full-screen viewer for chat images/videos. Only loads pages near the current index.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.items, required this.initialIndex});

  final List<MediaViewerItem> items;
  final int initialIndex;

  static Future<void> open(BuildContext context, {required List<MediaViewerItem> items, required int initialIndex}) {
    if (items.isEmpty) return Future.value();
    final idx = initialIndex.clamp(0, items.length - 1);
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MediaViewerScreen(items: items, initialIndex: idx)),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${items.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: items.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, index) {
          final load = (index - _current).abs() <= 1;
          return _MediaViewerPage(item: items[index], loadContent: load);
        },
      ),
    );
  }
}

class _MediaViewerPage extends StatefulWidget {
  const _MediaViewerPage({required this.item, required this.loadContent});

  final MediaViewerItem item;
  final bool loadContent;

  @override
  State<_MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<_MediaViewerPage> with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _video;

  @override
  bool get wantKeepAlive => widget.loadContent;

  @override
  void didUpdateWidget(covariant _MediaViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loadContent && _video != null) {
      _disposeVideo();
    } else if (widget.loadContent && widget.item.isVideo && _video == null) {
      _initVideo();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadContent && widget.item.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.item.url));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() {});
    }
  }

  void _disposeVideo() {
    _video?.dispose();
    _video = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.loadContent) {
      return const Center(child: Icon(Icons.photo_outlined, color: Colors.white24, size: 48));
    }
    if (widget.item.isVideo) {
      final c = _video;
      if (c == null || !c.value.isInitialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white54));
      }
      return Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              VideoPlayer(c),
              VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Colors.white)),
              Positioned(
                right: 16,
                bottom: 48,
                child: IconButton(
                  icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                  onPressed: () => setState(() {
                    c.value.isPlaying ? c.pause() : c.play();
                  }),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: CachedNetworkImage(imageUrl: widget.item.url, fit: BoxFit.contain),
      ),
    );
  }
}

List<MediaViewerItem> mediaViewerItemsFromMessages(List<ChatMessage> messages) {
  final items = <MediaViewerItem>[];
  for (final m in messages) {
    for (final att in m.attachments) {
      final info = AttachmentInfo.from(att, messageType: m.type);
      final url = info.url;
      if (url == null || url.isEmpty) continue;
      if (info.kind == AttachmentKind.image) {
        items.add(MediaViewerItem(url: url, isVideo: false, title: info.name));
      } else if (info.kind == AttachmentKind.video) {
        items.add(MediaViewerItem(url: url, isVideo: true, title: info.name));
      }
    }
  }
  return items;
}
