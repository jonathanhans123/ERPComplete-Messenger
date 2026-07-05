import 'package:flutter/material.dart';

import '../theme/messenger_theme.dart';

/// Live voice recording waveform bars (expects normalized 0.0–1.0 samples).
class VoiceWaveformBars extends StatelessWidget {
  const VoiceWaveformBars({
    super.key,
    required this.samples,
    this.paused = false,
    this.barCount = 28,
  });

  final List<double> samples;
  final bool paused;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final data = samples.length >= barCount
        ? samples
        : [...List<double>.filled(barCount - samples.length, 0.1), ...samples];

    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (i) {
          final level = paused ? 0.1 : data[i].clamp(0.08, 1.0);
          final height = 4.0 + level * 22.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOutCubic,
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            decoration: BoxDecoration(
              color: paused
                  ? ext.subtext.withValues(alpha: 0.35)
                  : MessengerPalette.whatsAppGreen.withValues(alpha: 0.45 + level * 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
