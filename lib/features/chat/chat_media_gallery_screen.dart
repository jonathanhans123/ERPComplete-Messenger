import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/media/attachment_kind.dart';
import '../../core/models/api_models.dart';
import '../../theme/messenger_theme.dart';
import '../../widgets/media_viewer_screen.dart';
import '../../widgets/message_media_widgets.dart';

enum MediaGalleryFilter { all, image, video, voice, location, file, link }

class ChatMediaGalleryScreen extends StatefulWidget {
  const ChatMediaGalleryScreen({super.key, required this.messages});

  final List<ChatMessage> messages;

  @override
  State<ChatMediaGalleryScreen> createState() => _ChatMediaGalleryScreenState();
}

class _ChatMediaGalleryScreenState extends State<ChatMediaGalleryScreen> {
  MediaGalleryFilter _filter = MediaGalleryFilter.all;

  List<_GalleryItem> get _items {
    final items = <_GalleryItem>[];

    for (final m in widget.messages) {
      for (final att in m.attachments) {
        final info = AttachmentInfo.from(att, messageType: m.type);
        if (info.kind == AttachmentKind.image ||
            info.kind == AttachmentKind.video ||
            info.kind == AttachmentKind.voice ||
            info.kind == AttachmentKind.location ||
            info.kind == AttachmentKind.file) {
          items.add(_GalleryItem(info: info, message: m));
        }
      }
      for (final url in extractUrlsFromText(m.body)) {
        items.add(_GalleryItem(linkUrl: url, message: m));
      }
    }

    return switch (_filter) {
      MediaGalleryFilter.all => items,
      MediaGalleryFilter.image => items.where((i) => i.info?.kind == AttachmentKind.image).toList(),
      MediaGalleryFilter.video => items.where((i) => i.info?.kind == AttachmentKind.video).toList(),
      MediaGalleryFilter.voice => items.where((i) => i.info?.kind == AttachmentKind.voice).toList(),
      MediaGalleryFilter.location => items.where((i) => i.info?.kind == AttachmentKind.location).toList(),
      MediaGalleryFilter.file => items.where((i) => i.info?.kind == AttachmentKind.file).toList(),
      MediaGalleryFilter.link => items.where((i) => i.linkUrl != null).toList(),
    };
  }

  void _openItem(_GalleryItem item) {
    final info = item.info;
    if (info?.kind == AttachmentKind.image && info!.url != null) {
      final items = mediaViewerItemsFromMessages(widget.messages);
      final idx = items.indexWhere((i) => i.url == info.url);
      MediaViewerScreen.open(context, items: items, initialIndex: idx >= 0 ? idx : 0);
      return;
    }
    if (info?.kind == AttachmentKind.video && info!.url != null) {
      final items = mediaViewerItemsFromMessages(widget.messages);
      final idx = items.indexWhere((i) => i.url == info.url);
      MediaViewerScreen.open(context, items: items, initialIndex: idx >= 0 ? idx : 0);
      return;
    }
    if (info?.kind == AttachmentKind.voice && info!.url != null) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: VoiceMessagePlayer(url: info.url!, durationLabel: info.duration, textColor: Theme.of(ctx).colorScheme.onSurface),
        ),
      );
      return;
    }
    if (info?.kind == AttachmentKind.location && info!.latitude != null && info.longitude != null) {
      final url = info.url ?? 'https://www.google.com/maps?q=${info.latitude},${info.longitude}';
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (info?.url != null) {
      launchUrl(Uri.parse(info!.url!), mode: LaunchMode.externalApplication);
      return;
    }
    if (item.linkUrl != null) {
      launchUrl(Uri.parse(item.linkUrl!), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Media gallery')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: MediaGalleryFilter.values.map((f) {
                final label = switch (f) {
                  MediaGalleryFilter.all => 'All',
                  MediaGalleryFilter.image => 'Photos',
                  MediaGalleryFilter.video => 'Videos',
                  MediaGalleryFilter.voice => 'Voice',
                  MediaGalleryFilter.location => 'Locations',
                  MediaGalleryFilter.file => 'Files',
                  MediaGalleryFilter.link => 'Links',
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('No items', style: TextStyle(color: ext.subtext)))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _GalleryTile(item: items[index], onTap: () => _openItem(items[index])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.item, required this.onTap});

  final _GalleryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = item.info;
    if (info?.kind == AttachmentKind.image && info!.url != null) {
      return GestureDetector(
        onTap: onTap,
        child: NetworkMediaImage(url: info.url!, fit: BoxFit.cover),
      );
    }
    if (info?.kind == AttachmentKind.location && info!.latitude != null && info.longitude != null) {
      return GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                locationStaticMapUrl(info.latitude!, info.longitude!),
                fit: BoxFit.cover,
                headers: const {'User-Agent': kOsmTileUserAgent},
                errorBuilder: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              const Align(alignment: Alignment.bottomCenter, child: Icon(Icons.location_on, color: Colors.white, shadows: [Shadow(blurRadius: 4)])),
            ],
          ),
        ),
      );
    }
    if (item.linkUrl != null) {
      final favicon = linkFaviconUrl(item.linkUrl!);
      return InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (favicon.isNotEmpty)
                Image.network(favicon, width: 32, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.link))
              else
                const Icon(Icons.link),
              const SizedBox(height: 4),
              Text(linkDomain(item.linkUrl!) ?? item.linkUrl!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    final icon = switch (info?.kind) {
      AttachmentKind.video => Icons.videocam,
      AttachmentKind.voice => Icons.mic,
      AttachmentKind.file => Icons.insert_drive_file,
      _ => Icons.attach_file,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            if (info?.name != null)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(info!.name!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryItem {
  _GalleryItem({this.info, this.linkUrl, required this.message});
  final AttachmentInfo? info;
  final String? linkUrl;
  final ChatMessage message;
}
