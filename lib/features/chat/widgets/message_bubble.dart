import 'package:flutter/material.dart';

import '../../../core/models/api_models.dart';
import '../../../theme/messenger_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.showSender = false});

  final ChatMessage message;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final sent = message.isSent;
    return Padding(
      padding: EdgeInsets.only(
        left: sent ? 56 : 12,
        right: sent ? 12 : 56,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: sent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !sent)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(message.senderName, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: MessengerColors.textSecondary)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sent ? MessengerColors.sentBubble : MessengerColors.receivedBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(sent ? 16 : 4),
                bottomRight: Radius.circular(sent ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.body.isEmpty ? '[${message.type}]' : message.body,
                  style: TextStyle(color: sent ? MessengerColors.sentText : MessengerColors.receivedText, fontSize: 15, height: 1.35),
                ),
                if (message.time != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.time!,
                    style: TextStyle(
                      fontSize: 11,
                      color: (sent ? MessengerColors.sentText : MessengerColors.receivedText).withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
