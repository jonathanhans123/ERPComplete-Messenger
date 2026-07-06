import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Keeps calls/messages working in background — requests battery exemption when possible.
class AndroidBackgroundReliability {
  AndroidBackgroundReliability._();

  static const _storage = FlutterSecureStorage();
  static const _snoozeUntilKey = 'bg_reliability_snooze_until_ms';
  static const _dontAskKey = 'bg_reliability_dont_ask';

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!isAndroid) return true;
    try {
      final status = await ph.Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestBatteryOptimizationExemption() async {
    if (!isAndroid) return true;
    try {
      final result = await ph.Permission.ignoreBatteryOptimizations.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openApplicationSettings() async {
    await ph.openAppSettings();
  }

  static Future<bool> shouldPromptUser() async {
    if (!isAndroid) return false;
    if (await isBatteryOptimizationDisabled()) return false;
    final dontAsk = await _storage.read(key: _dontAskKey);
    if (dontAsk == 'true') return false;
    final snoozeRaw = await _storage.read(key: _snoozeUntilKey);
    if (snoozeRaw != null) {
      final snoozeMs = int.tryParse(snoozeRaw);
      if (snoozeMs != null && DateTime.now().millisecondsSinceEpoch < snoozeMs) {
        return false;
      }
    }
    return true;
  }

  static Future<void> snoozePrompt({Duration duration = const Duration(hours: 24)}) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await _storage.write(key: _snoozeUntilKey, value: '$until');
  }

  static Future<void> setDontAskAgain(bool value) async {
    if (value) {
      await _storage.write(key: _dontAskKey, value: 'true');
    } else {
      await _storage.delete(key: _dontAskKey);
    }
  }

  static String get manualStepsText =>
      'If calls or messages stop in the background, open App info → Battery and set '
      'Battery saver to No restrictions (or Unrestricted).\n\n'
      'On some phones (Samsung, Xiaomi, Oppo, Vivo) also allow Autostart / '
      'Run in background for this app in the same App info screen.';
}
