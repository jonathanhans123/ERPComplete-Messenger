import '../../config/api_config.dart';

/// Resolves attachment URLs from API (localhost/relative paths → VPS origin).
class MediaUrlResolver {
  static String get _origin {
    final uri = Uri.parse(ApiConfig.defaultBaseUrl);
    return '${uri.scheme}://${uri.host}';
  }

  static final _brokenStorageUrl = RegExp(r'/storage/?$', caseSensitive: false);

  static String? resolve(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var url = raw.trim();
    if (url == 'null' || url == 'false') return null;
    if (_brokenStorageUrl.hasMatch(url)) return null;
    if (url.startsWith('blob:') || url.startsWith('data:')) return url;

    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (url.startsWith('/')) {
      url = '$_origin$url';
    } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = '$_origin/$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.endsWith('.local')) {
      final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      return '$_origin$path';
    }

    return url;
  }
}
