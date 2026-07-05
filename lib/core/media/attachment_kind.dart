import 'dart:math' as math;

import 'media_url_resolver.dart';

/// OSM tile servers require a valid User-Agent (see usage policy).
const kOsmTileUserAgent = 'ERPComplete-Messenger/1.0 (+https://srv1804550.hstgr.cloud)';

enum AttachmentKind { image, video, voice, location, contact, file, link, poll, other }

class AttachmentInfo {
  AttachmentInfo({
    required this.kind,
    required this.raw,
    this.url,
    this.name,
    this.duration,
    this.latitude,
    this.longitude,
    this.address,
  });

  final AttachmentKind kind;
  final Map<String, dynamic> raw;
  final String? url;
  final String? name;
  final String? duration;
  final double? latitude;
  final double? longitude;
  final String? address;

  static AttachmentInfo from(Map<String, dynamic> att, {String messageType = 'text'}) {
    final normalized = Map<String, dynamic>.from(att);
    if (normalized['url'] != null) {
      normalized['url'] = MediaUrlResolver.resolve(normalized['url'] as String?);
    }

    final kind = _inferKind(normalized, messageType);
    return AttachmentInfo(
      kind: kind,
      raw: normalized,
      url: normalized['url'] as String?,
      name: normalized['name'] as String?,
      duration: normalized['duration'] as String?,
      latitude: _asDouble(normalized['latitude']),
      longitude: _asDouble(normalized['longitude']),
      address: normalized['address'] as String? ?? normalized['label'] as String?,
    );
  }

  static List<AttachmentInfo> listFromMessage(Map<String, dynamic>? att, String messageType) {
    if (att == null) return [];
    return [from(att, messageType: messageType)];
  }

  static AttachmentKind _inferKind(Map<String, dynamic> att, String messageType) {
    final declared = (att['type'] as String? ?? messageType).toLowerCase();
    final mime = (att['mime_type'] as String? ?? '').toLowerCase();
    final name = (att['name'] as String? ?? '').toLowerCase();

    if (messageType == 'voice' || messageType == 'audio' || declared == 'voice' || declared == 'audio') {
      return AttachmentKind.voice;
    }
    if (messageType == 'image' || declared == 'image') return AttachmentKind.image;
    if (messageType == 'video' && declared != 'voice' && declared != 'audio') return AttachmentKind.video;
    if (messageType == 'location' || declared == 'location') return AttachmentKind.location;
    if (declared == 'contact') return AttachmentKind.contact;
    if (declared == 'poll') return AttachmentKind.poll;

    if (_hasExt(name, ['.m4a', '.mp3', '.wav', '.ogg', '.aac', '.opus'])) {
      return AttachmentKind.voice;
    }
    if (mime.startsWith('image/') || _hasExt(name, ['.jpg', '.jpeg', '.png', '.gif', '.webp'])) {
      return AttachmentKind.image;
    }
    if (mime.startsWith('audio/')) {
      return AttachmentKind.voice;
    }
    if (mime == 'video/mp4' && _hasExt(name, ['.m4a'])) {
      return AttachmentKind.voice;
    }
    if (mime.startsWith('video/') || _hasExt(name, ['.mp4', '.mov', '.mkv'])) {
      return AttachmentKind.video;
    }
    if (_hasExt(name, ['.webm']) && messageType == 'voice') {
      return AttachmentKind.voice;
    }
    if (_hasExt(name, ['.webm'])) {
      final hasVideo = att['has_video'];
      final hasAudio = att['has_audio'];
      if (hasVideo == false && hasAudio == true) return AttachmentKind.voice;
      if (hasVideo == true) return AttachmentKind.video;
      return messageType == 'voice' ? AttachmentKind.voice : AttachmentKind.video;
    }
    return AttachmentKind.file;
  }

  static bool _hasExt(String name, List<String> exts) {
    return exts.any((e) => name.endsWith(e));
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

final _urlPattern = RegExp(r'https?:\/\/[^\s<>"{}|\\^`\[\]]+', caseSensitive: false);

List<String> extractUrlsFromText(String text) {
  return _urlPattern.allMatches(text).map((m) => m.group(0)!).toList();
}

String? linkDomain(String url) {
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return null;
  }
}

String linkFaviconUrl(String url) {
  final domain = linkDomain(url);
  if (domain == null || domain.isEmpty) return '';
  return 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
}

String locationStaticMapUrl(double lat, double lng, {int zoom = 15}) {
  final n = math.pow(2, zoom).toDouble();
  final x = ((lng + 180) / 360 * n).floor();
  final latRad = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
  return 'https://tile.openstreetmap.org/$zoom/$x/$y.png';
}
