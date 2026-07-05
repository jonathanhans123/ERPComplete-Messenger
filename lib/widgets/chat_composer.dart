import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';

import '../theme/messenger_theme.dart';
import 'voice_waveform_bars.dart';

class VoiceRecordingState {
  const VoiceRecordingState({
    required this.durationSeconds,
    required this.paused,
    this.recorderController,
    this.waveSamples = const [],
  });

  final int durationSeconds;
  final bool paused;
  final RecorderController? recorderController;
  /// Legacy fallback samples when no live recorder controller is attached.
  final List<double> waveSamples;
}



class ChatComposer extends StatefulWidget {

  const ChatComposer({

    super.key,

    required this.controller,

    required this.onSend,

    required this.onAttach,

    this.onStartVoiceRecord,

    this.voiceRecording,

    this.onCancelVoiceRecording,

    this.onPauseVoiceRecording,

    this.onResumeVoiceRecording,

    this.onSendVoiceRecording,

    this.sending = false,

    this.replyPreview,

    this.onCancelReply,

  });



  final TextEditingController controller;

  final VoidCallback onSend;

  final VoidCallback onAttach;

  final Future<void> Function()? onStartVoiceRecord;

  final VoiceRecordingState? voiceRecording;

  final VoidCallback? onCancelVoiceRecording;

  final VoidCallback? onPauseVoiceRecording;

  final VoidCallback? onResumeVoiceRecording;

  final VoidCallback? onSendVoiceRecording;

  final bool sending;

  final String? replyPreview;

  final VoidCallback? onCancelReply;



  @override

  State<ChatComposer> createState() => _ChatComposerState();

}



class _ChatComposerState extends State<ChatComposer> {

  @override

  void initState() {

    super.initState();

    widget.controller.addListener(_onTextChanged);

  }



  @override

  void dispose() {

    widget.controller.removeListener(_onTextChanged);

    super.dispose();

  }



  void _onTextChanged() => setState(() {});



  static String _formatDuration(int seconds) {

    final mins = seconds ~/ 60;

    final secs = seconds % 60;

    return '$mins:${secs.toString().padLeft(2, '0')}';

  }



  @override

  Widget build(BuildContext context) {

    final ext = messengerExt(context);

    final hasText = widget.controller.text.trim().isNotEmpty;

    final recording = widget.voiceRecording;



    return Material(

      color: ext.composerBackground,

      child: SafeArea(

        top: false,

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            if (widget.replyPreview != null)

              Container(

                width: double.infinity,

                padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),

                child: Row(

                  children: [

                    Container(width: 3, height: 36, decoration: BoxDecoration(color: MessengerPalette.whatsAppGreen, borderRadius: BorderRadius.circular(2))),

                    const SizedBox(width: 10),

                    Expanded(

                      child: Column(

                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [

                          Text('Replying', style: TextStyle(color: MessengerPalette.whatsAppGreen, fontSize: 12, fontWeight: FontWeight.w600)),

                          Text(widget.replyPreview!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ext.subtext, fontSize: 13)),

                        ],

                      ),

                    ),

                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: widget.onCancelReply),

                  ],

                ),

              ),

            Padding(

              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),

              child: recording != null

                  ? _VoiceRecordingBar(

                      durationLabel: _formatDuration(recording.durationSeconds),

                      paused: recording.paused,

                      recorderController: recording.recorderController,

                      waveSamples: recording.waveSamples,

                      onCancel: widget.onCancelVoiceRecording,

                      onPause: widget.onPauseVoiceRecording,

                      onResume: widget.onResumeVoiceRecording,

                      onSend: widget.onSendVoiceRecording,

                      sending: widget.sending,

                    )

                  : Row(

                      crossAxisAlignment: CrossAxisAlignment.end,

                      children: [

                        IconButton(

                          onPressed: widget.onAttach,

                          icon: Icon(Icons.add_circle_outline, color: ext.subtext, size: 28),

                        ),

                        Expanded(

                          child: Container(

                            decoration: BoxDecoration(

                              color: Theme.of(context).inputDecorationTheme.fillColor,

                              borderRadius: BorderRadius.circular(24),

                            ),

                            child: TextField(

                              controller: widget.controller,

                              minLines: 1,

                              maxLines: 5,

                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),

                              decoration: const InputDecoration(

                                hintText: 'Message',

                                border: InputBorder.none,

                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),

                                filled: false,

                              ),

                              textInputAction: TextInputAction.newline,

                            ),

                          ),

                        ),

                        const SizedBox(width: 6),

                        Material(

                          color: hasText || widget.sending ? MessengerPalette.whatsAppGreen : ext.subtext.withValues(alpha: 0.3),

                          shape: const CircleBorder(),

                          child: InkWell(

                            customBorder: const CircleBorder(),

                            onTap: widget.sending

                                ? null

                                : hasText

                                    ? widget.onSend

                                    : (widget.onStartVoiceRecord != null ? () => widget.onStartVoiceRecord!() : null),

                            child: SizedBox(

                              width: 48,

                              height: 48,

                              child: Center(

                                child: widget.sending

                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))

                                    : Icon(hasText ? Icons.send_rounded : Icons.mic_none_rounded, color: Colors.white, size: hasText ? 22 : 24),

                              ),

                            ),

                          ),

                        ),

                      ],

                    ),

            ),

          ],

        ),

      ),

    );

  }

}



class _VoiceRecordingBar extends StatelessWidget {

  const _VoiceRecordingBar({
    required this.durationLabel,
    required this.paused,
    this.recorderController,
    this.waveSamples = const [],
    this.onCancel,
    this.onPause,
    this.onResume,
    this.onSend,
    this.sending = false,
  });

  final String durationLabel;
  final bool paused;
  final RecorderController? recorderController;
  final List<double> waveSamples;

  final VoidCallback? onCancel;

  final VoidCallback? onPause;

  final VoidCallback? onResume;

  final VoidCallback? onSend;

  final bool sending;



  @override

  Widget build(BuildContext context) {

    final ext = messengerExt(context);

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),

      decoration: BoxDecoration(

        color: Theme.of(context).inputDecorationTheme.fillColor,

        borderRadius: BorderRadius.circular(28),

      ),

      child: Row(

        children: [

          IconButton(

            tooltip: 'Delete recording',

            onPressed: onCancel,

            icon: Icon(Icons.delete_outline, color: ext.subtext),

          ),

          if (!paused)

            Container(

              width: 8,

              height: 8,

              margin: const EdgeInsets.only(right: 6),

              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),

            ),

          Text(durationLabel, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 15)),

          const SizedBox(width: 8),

          Expanded(
            child: recorderController != null
                ? AudioWaveforms(
                    size: const Size(double.infinity, 32),
                    recorderController: recorderController!,
                    enableGesture: false,
                    waveStyle: const WaveStyle(
                      waveColor: MessengerPalette.whatsAppGreen,
                      showDurationLabel: false,
                      spacing: 4,
                      showBottom: true,
                      extendWaveform: true,
                      showMiddleLine: false,
                    ),
                  )
                : VoiceWaveformBars(samples: waveSamples, paused: paused),
          ),

          IconButton(

            tooltip: paused ? 'Resume recording' : 'Pause recording',

            onPressed: paused ? onResume : onPause,

            icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Theme.of(context).colorScheme.onSurface),

          ),

          Material(

            color: MessengerPalette.whatsAppGreen,

            shape: const CircleBorder(),

            child: InkWell(

              customBorder: const CircleBorder(),

              onTap: sending ? null : onSend,

              child: SizedBox(

                width: 44,

                height: 44,

                child: Center(

                  child: sending

                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))

                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }

}

