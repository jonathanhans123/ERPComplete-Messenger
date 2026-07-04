import 'package:flutter/material.dart';

import '../../../core/models/api_models.dart';
import '../../../theme/messenger_theme.dart';

class DateDivider extends StatelessWidget {
  const DateDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 2)],
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ext.subtext)),
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showSender = false,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool showSender;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final sent = message.isSent;
    final bubbleColor = sent ? ext.sentBubble : ext.receivedBubble;
    final textColor = sent ? ext.sentText : ext.receivedText;

    return Padding(
      padding: EdgeInsets.only(left: sent ? 48 : 12, right: sent ? 12 : 48, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: sent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !sent)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Text(message.senderName, style: const TextStyle(color: MessengerPalette.whatsAppGreen, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(sent ? 12 : 2),
                  bottomRight: Radius.circular(sent ? 2 : 12),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isStarred)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 12, color: Colors.amber.shade700),
                          const SizedBox(width: 4),
                          Text('Starred', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.75), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (message.isForwarded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 12, color: textColor.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text('Forwarded', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: textColor.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                  if (message.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 12, color: textColor.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text('Pinned', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                  if (message.replyPreview != null)
                    _ReplyQuote(
                      sender: message.replyToSender,
                      preview: message.replyPreview!,
                      textColor: textColor,
                    ),
                  Text(
                    message.body.isEmpty ? _typeLabel(message.type) : message.body,
                    style: TextStyle(color: textColor, fontSize: 15.5, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.isEdited)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text('edited', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: textColor.withValues(alpha: 0.65))),
                        ),
                      if (message.time != null)
                        Text(message.time!, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.65))),
                      if (sent) ...[
                        const SizedBox(width: 4),
                        _StatusTicks(status: message.status, isPending: message.isPending, color: textColor.withValues(alpha: 0.65)),
                      ],
                    ],
                  ),
                  if (message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: message.reactions.entries
                          .map(
                            (e) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: ext.subtext.withValues(alpha: 0.15)),
                              ),
                              child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String type) {
    return switch (type) {
      'file' => '📎 Attachment',
      'image' => '🖼 Photo',
      'voice' => '🎤 Voice message',
      'call' => '📞 Call',
      'erp_card' => '📋 ERP card',
      _ => '[$type]',
    };
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({this.sender, required this.preview, required this.textColor});

  final String? sender;
  final String preview;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: MessengerPalette.whatsAppGreen, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sender != null)
            Text(
              sender!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MessengerPalette.whatsAppGreen, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 13, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _StatusTicks extends StatelessWidget {
  const _StatusTicks({required this.status, required this.isPending, required this.color});

  final String? status;
  final bool isPending;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: color));
    }
    final normalized = status == 'read' ? 'read' : (status == 'sending' ? 'sending' : 'sent');
    if (normalized == 'read') {
      return Icon(Icons.done_all, size: 16, color: MessengerPalette.accent);
    }
    if (normalized == 'sending') {
      return Icon(Icons.done, size: 14, color: color.withValues(alpha: 0.5));
    }
    return Icon(Icons.done_all, size: 16, color: color);
  }
}
