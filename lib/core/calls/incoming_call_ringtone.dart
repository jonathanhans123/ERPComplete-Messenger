import 'dart:async';

import 'package:flutter/services.dart';

/// Vibration pulse while an incoming call is ringing (notification channel handles sound).
class IncomingCallRingtone {
  IncomingCallRingtone._();

  static Timer? _timer;
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
    await HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
  }
}
