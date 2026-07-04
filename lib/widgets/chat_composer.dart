import 'package:flutter/material.dart';

import '../theme/messenger_theme.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    this.sending = false,
    this.replyPreview,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
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

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final hasText = widget.controller.text.trim().isNotEmpty;

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
              child: Row(
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
                      onTap: widget.sending ? null : (hasText ? widget.onSend : null),
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
