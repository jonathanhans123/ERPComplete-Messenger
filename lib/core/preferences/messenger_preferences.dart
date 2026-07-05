import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Local prefs (wallpaper, muted chats) — mirrors web localStorage keys.
class MessengerPreferences extends ChangeNotifier {
  MessengerPreferences(this._storage);

  static const _wallpaperKey = 'chat_wallpaper';
  static const _customWallpaperKey = 'chat_wallpaper_custom_path';
  static const _mutedKey = 'muted_conversations';
  static const _starredKey = 'starred_messages';
  static const _pushKey = 'push_notifications_enabled';

  final FlutterSecureStorage _storage;
  String _wallpaper = ChatWallpaper.defaultId;
  String? _customWallpaperPath;
  Set<int> _mutedConversationIds = {};
  Map<int, Set<int>> _starredByConversation = {};
  bool _pushNotificationsEnabled = true;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get wallpaperId => _wallpaper;
  String? get customWallpaperPath => _customWallpaperPath;
  bool get pushNotificationsEnabled => _pushNotificationsEnabled;
  Set<int> get mutedConversationIds => Set.unmodifiable(_mutedConversationIds);

  Future<void> load() async {
    _wallpaper = await _storage.read(key: _wallpaperKey) ?? ChatWallpaper.defaultId;
    _customWallpaperPath = await _storage.read(key: _customWallpaperKey);
    _pushNotificationsEnabled = (await _storage.read(key: _pushKey)) != 'false';
    final mutedRaw = await _storage.read(key: _mutedKey);
    if (mutedRaw != null && mutedRaw.isNotEmpty) {
      try {
        final list = jsonDecode(mutedRaw) as List;
        _mutedConversationIds = list.map((e) => int.parse(e.toString())).toSet();
      } catch (_) {
        _mutedConversationIds = {};
      }
    }
    final starredRaw = await _storage.read(key: _starredKey);
    if (starredRaw != null && starredRaw.isNotEmpty) {
      try {
        final map = jsonDecode(starredRaw) as Map<String, dynamic>;
        _starredByConversation = map.map(
          (k, v) => MapEntry(int.parse(k), (v as List).map((e) => int.parse(e.toString())).toSet()),
        );
      } catch (_) {
        _starredByConversation = {};
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setWallpaper(String id) async {
    _wallpaper = id;
    _customWallpaperPath = null;
    await _storage.write(key: _wallpaperKey, value: id);
    await _storage.delete(key: _customWallpaperKey);
    notifyListeners();
  }

  Future<void> setCustomWallpaperFromFile(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final wallpapersDir = Directory('${dir.path}/wallpapers');
    if (!await wallpapersDir.exists()) {
      await wallpapersDir.create(recursive: true);
    }
    final dest = File('${wallpapersDir.path}/custom_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await source.copy(dest.path);
    _wallpaper = ChatWallpaper.customId;
    _customWallpaperPath = dest.path;
    await _storage.write(key: _wallpaperKey, value: ChatWallpaper.customId);
    await _storage.write(key: _customWallpaperKey, value: dest.path);
    notifyListeners();
  }

  Future<void> clearCustomWallpaper() async {
    final old = _customWallpaperPath;
    _customWallpaperPath = null;
    _wallpaper = ChatWallpaper.defaultId;
    await _storage.delete(key: _customWallpaperKey);
    await _storage.write(key: _wallpaperKey, value: ChatWallpaper.defaultId);
    if (old != null) {
      try {
        final f = File(old);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  bool isMuted(int conversationId) => _mutedConversationIds.contains(conversationId);

  bool shouldNotifyForConversation(int conversationId) {
    return _pushNotificationsEnabled && !isMuted(conversationId);
  }

  Future<void> setPushNotificationsEnabled(bool enabled) async {
    _pushNotificationsEnabled = enabled;
    await _storage.write(key: _pushKey, value: enabled ? 'true' : 'false');
    notifyListeners();
  }

  Future<void> toggleMute(int conversationId) async {
    if (_mutedConversationIds.contains(conversationId)) {
      _mutedConversationIds.remove(conversationId);
    } else {
      _mutedConversationIds.add(conversationId);
    }
    await _storage.write(key: _mutedKey, value: jsonEncode(_mutedConversationIds.toList()));
    notifyListeners();
  }

  Color wallpaperColor(Brightness brightness) {
    if (_customWallpaperPath != null && File(_customWallpaperPath!).existsSync()) {
      return Colors.transparent;
    }
    return ChatWallpaper.byId(_wallpaper).colorFor(brightness);
  }

  Set<int> starredMessageIds(int conversationId) {
    return Set.unmodifiable(_starredByConversation[conversationId] ?? const {});
  }

  bool isMessageStarred(int conversationId, int messageId) {
    return _starredByConversation[conversationId]?.contains(messageId) ?? false;
  }

  Future<void> toggleStarMessage(int conversationId, int messageId) async {
    final set = _starredByConversation.putIfAbsent(conversationId, () => {});
    if (set.contains(messageId)) {
      set.remove(messageId);
      if (set.isEmpty) _starredByConversation.remove(conversationId);
    } else {
      set.add(messageId);
    }
    await _persistStarred();
    notifyListeners();
  }

  Future<void> _persistStarred() async {
    final encoded = _starredByConversation.map((k, v) => MapEntry(k.toString(), v.toList()));
    await _storage.write(key: _starredKey, value: jsonEncode(encoded));
  }
}

Future<MessengerPreferences> createMessengerPreferences() async {
  final prefs = MessengerPreferences(const FlutterSecureStorage());
  await prefs.load();
  return prefs;
}

class ChatWallpaper {
  const ChatWallpaper({required this.id, required this.name, this.lightColor, this.darkColor});

  final String id;
  final String name;
  final Color? lightColor;
  final Color? darkColor;

  static const defaultId = 'default';
  static const customId = 'custom';

  static const presets = [
    ChatWallpaper(id: 'default', name: 'Default'),
    ChatWallpaper(id: 'blue', name: 'Blue', lightColor: Color(0xFFE3F2FD), darkColor: Color(0xFF1A2A3A)),
    ChatWallpaper(id: 'green', name: 'Green', lightColor: Color(0xFFE8F5E9), darkColor: Color(0xFF1B2E1F)),
    ChatWallpaper(id: 'purple', name: 'Purple', lightColor: Color(0xFFF3E5F5), darkColor: Color(0xFF2A1F33)),
    ChatWallpaper(id: 'orange', name: 'Orange', lightColor: Color(0xFFFFF3E0), darkColor: Color(0xFF3A2A1A)),
    ChatWallpaper(id: 'dark', name: 'Slate', lightColor: Color(0xFFECEFF1), darkColor: Color(0xFF263238)),
  ];

  static ChatWallpaper byId(String id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }

  Color colorFor(Brightness brightness) {
    if (id == defaultId) return Colors.transparent;
    return brightness == Brightness.dark ? (darkColor ?? lightColor!) : (lightColor ?? darkColor!);
  }
}
