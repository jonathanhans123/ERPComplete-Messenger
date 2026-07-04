import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._storage) {
    _loadStored();
  }

  static const _key = 'theme_mode';
  final FlutterSecureStorage _storage;
  ThemeMode _mode = ThemeMode.system;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  bool get isLoaded => _loaded;

  Future<void> _loadStored() async {
    final stored = await _storage.read(key: _key);
    if (stored == 'light') _mode = ThemeMode.light;
    if (stored == 'dark') _mode = ThemeMode.dark;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await _storage.write(
      key: _key,
      value: switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    notifyListeners();
  }
}

Future<ThemeController> createThemeController() async {
  return ThemeController(const FlutterSecureStorage());
}
