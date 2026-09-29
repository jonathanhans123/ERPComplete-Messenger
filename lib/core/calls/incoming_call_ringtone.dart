import 'dart:async';

import 'package:flutter/services.dart';

import 'call_sounds.dart';

/// Audible ring + vibration pulse while an incoming call is ringing.
/// (Notification channels also handle sound when the app is backgrounded.)
class IncomingCallRingtone {
  IncomingCallRingtone._();

  static Timer? _timer;
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
    unawaited(CallSounds.startIncoming());
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
    await CallSounds.stopAll();
  }
}
