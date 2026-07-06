import 'package:flutter/material.dart';

import '../core/platform/android_background_reliability.dart';

/// Prompts the user to allow unrestricted battery / background operation (Android).
class BackgroundReliabilityPrompt {
  static Future<void> maybeShow(BuildContext context) async {
    if (!AndroidBackgroundReliability.isAndroid) return;
    if (!context.mounted) return;
    if (!await AndroidBackgroundReliability.shouldPromptUser()) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _BackgroundReliabilityDialog(),
    );
  }
}

class _BackgroundReliabilityDialog extends StatefulWidget {
  const _BackgroundReliabilityDialog();

  @override
  State<_BackgroundReliabilityDialog> createState() => _BackgroundReliabilityDialogState();
}

class _BackgroundReliabilityDialogState extends State<_BackgroundReliabilityDialog> {
  bool _busy = false;

  Future<void> _requestExemption() async {
    setState(() => _busy = true);
    final granted = await AndroidBackgroundReliability.requestBatteryOptimizationExemption();
    if (!mounted) return;
    setState(() => _busy = false);
    if (granted) {
      Navigator.of(context).pop();
      return;
    }
    await _showManualSteps();
  }

  Future<void> _showManualSteps() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set battery to No restrictions'),
        content: Text(AndroidBackgroundReliability.manualStepsText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AndroidBackgroundReliability.openApplicationSettings();
            },
            child: const Text('Open App info'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allow background operation'),
      content: const Text(
        'ERPComplete Messenger needs to run in the background for incoming calls and '
        'message alerts.\n\n'
        'On the next screen, tap Allow. If you do not see that option, open App info → '
        'Battery and set Battery saver to No restrictions (Unrestricted).',
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await AndroidBackgroundReliability.snoozePrompt();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Remind me later'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await AndroidBackgroundReliability.setDontAskAgain(true);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Don\'t ask again'),
        ),
        FilledButton(
          onPressed: _busy ? null : _requestExemption,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Allow'),
        ),
      ],
    );
  }
}
