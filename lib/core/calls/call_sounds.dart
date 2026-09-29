import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Call audio synthesized in code (8 kHz mono WAV via BytesSource), so no
/// audio assets or new packages are needed. All methods are safe to call
/// repeatedly; starting one tone stops any other.
class CallSounds {
  CallSounds._();

  static const _rate = 8000;
  static AudioPlayer? _player;
  static String? _current;

  static bool get playing => _current != null;

  /// Classic dual-tone ring, looped. Used for incoming calls.
  static Future<void> startIncoming() => _playLoop(
        'incoming',
        _tone(
          ms: 1600,
          sample: (t) {
            final warble = 0.6 + 0.4 * sin(2 * pi * 20 * t);
            return warble *
                0.5 *
                (sin(2 * pi * 440 * t) + sin(2 * pi * 480 * t)) *
                0.5;
          },
        ),
      );

  /// Soft ringback while waiting for the other side to pick up.
  static Future<void> startRingback() => _playLoop(
        'ringback',
        _tone(
          ms: 3000,
          sample: (t) {
            // 1s on, 2s off.
            if (t % 3.0 >= 1.0) return 0.0;
            final fade = min(1.0, min(t % 3.0, 1.0 - (t % 3.0)) / 0.01).clamp(0.0, 1.0);
            return 0.35 * sin(2 * pi * 440 * t) * fade;
          },
        ),
      );

  /// Short descending blip when a call ends.
  static Future<void> playEnded() async {
    await stopAll();
    try {
      final player = AudioPlayer();
      await player.play(
        BytesSource(_tone(
          ms: 350,
          sample: (t) {
            final f = 880 - (440 * t / 0.35);
            final fade = min(1.0, min(t, 0.35 - t) / 0.02).clamp(0.0, 1.0);
            return 0.4 * sin(2 * pi * f * t) * fade;
          },
        )),
      );
      // Release after it finishes.
      Future.delayed(const Duration(milliseconds: 600), player.dispose);
    } catch (_) {}
  }

  static Future<void> stopAll() async {
    _current = null;
    final player = _player;
    _player = null;
    try {
      await player?.stop();
    } catch (_) {}
    try {
      await player?.dispose();
    } catch (_) {}
  }

  static Future<void> _playLoop(String name, Uint8List wav) async {
    if (_current == name) return;
    await stopAll();
    _current = name;
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1.0);
      await player.play(BytesSource(wav));
    } catch (_) {
      _current = null;
    }
  }

  /// Builds a 16-bit PCM mono WAV.
  static Uint8List _tone({required int ms, required double Function(double t) sample}) {
    final n = (_rate * ms / 1000).round();
    final bytes = ByteData(44 + n * 2);
    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    bytes.setUint32(4, 36 + n * 2, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, _rate, Endian.little);
    bytes.setUint32(28, _rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    bytes.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final v = sample(i / _rate).clamp(-1.0, 1.0);
      bytes.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
