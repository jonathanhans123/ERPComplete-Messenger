import 'package:flutter/material.dart';

import '../../../core/media/attachment_kind.dart';
import '../../../core/models/api_models.dart';
import '../../../theme/messenger_theme.dart';
import '../../../widgets/message_media_widgets.dart';

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
    this.onPollVote,
    this.onMediaOpen,
    this.onCallRejoin,
    this.currentUserId,
  });

  final ChatMessage message;
  final bool showSender;
  final VoidCallback? onLongPress;
  final void Function(String optionId)? onPollVote;
  final void Function(ChatMessage message, AttachmentInfo info)? onMediaOpen;
  final void Function(ChatMessage message)? onCallRejoin;
  final int? currentUserId;

  @override
  Widget build(BuildContext context) {
    final ext = messengerExt(context);
    final sent = message.isSent;
    final bubbleColor = sent ? ext.sentBubble : ext.receivedBubble;
    final textColor = sent ? ext.sentText : ext.receivedText;
    final mediaHeavy = _isMediaHeavyMessage(message);

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
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * (mediaHeavy ? 0.72 : 0.78)),
              child: Container(
                padding: mediaHeavy ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    _MessageBody(
                      message: message,
                      textColor: textColor,
                      onPollVote: onPollVote,
                      onMediaOpen: onMediaOpen,
                      onCallRejoin: onCallRejoin,
                      currentUserId: currentUserId,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (message.isEdited && message.type != 'call')
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

  static bool _isMediaHeavyMessage(ChatMessage message) {
    if (message.type == 'image' || message.type == 'video' || message.type == 'voice' || message.type == 'location') {
      return true;
    }
    final att = message.primaryAttachment;
    if (att == null) return false;
    final kind = AttachmentInfo.from(att, messageType: message.type).kind;
    return kind == AttachmentKind.image ||
        kind == AttachmentKind.video ||
        kind == AttachmentKind.voice ||
        kind == AttachmentKind.location;
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.message,
    required this.textColor,
    this.onPollVote,
    this.onMediaOpen,
    this.onCallRejoin,
    this.currentUserId,
  });

  final ChatMessage message;
  final Color textColor;
  final void Function(String optionId)? onPollVote;
  final void Function(ChatMessage message, AttachmentInfo info)? onMediaOpen;
  final void Function(ChatMessage message)? onCallRejoin;
  final int? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (message.type == 'call') {
      final meta = message.callMeta;
      final video = meta?.isVideo == true || message.body.toLowerCase().contains('video');
      final canRejoin = message.isRejoinableCall && onCallRejoin != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(video ? Icons.videocam : Icons.call, size: 18, color: textColor.withValues(alpha: 0.85)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.callDisplayLine,
                  style: TextStyle(color: textColor, fontSize: 15.5, height: 1.35),
                ),
              ),
            ],
          ),
          if (canRejoin) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onCallRejoin!(message),
                icon: Icon(video ? Icons.videocam : Icons.call, size: 18),
                label: Text(video ? 'Rejoin video call' : 'Rejoin call'),
                style: FilledButton.styleFrom(
                  backgroundColor: MessengerPalette.whatsAppGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      );
    }

    final poll = message.pollAttachment;
    if (poll != null) {
      final options = (poll['options'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      final votes = poll['votes'] is Map ? Map<String, dynamic>.from(poll['votes'] as Map) : <String, dynamic>{};
      final myVote = currentUserId != null ? votes['$currentUserId']?.toString() : null;
      final question = poll['question'] as String? ?? message.body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: TextStyle(color: textColor, fontSize: 15.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...options.map((opt) {
            final id = '${opt['id']}';
            final selected = myVote == id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: selected ? MessengerPalette.whatsAppGreen.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onPollVote == null ? null : () => onPollVote!(id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('${opt['text']}', style: TextStyle(color: textColor, fontSize: 14))),
                        Text('${opt['votes'] ?? 0}', style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      );
    }

    final att = message.primaryAttachment;
    if (att != null) {
      final info = AttachmentInfo.from(att, messageType: message.type);
      switch (info.kind) {
        case AttachmentKind.image:
          if (info.url != null) {
            return ImageMessageTile(
              url: info.url!,
              onTap: onMediaOpen != null
                  ? () => onMediaOpen!(message, info)
                  : () => FullScreenImageViewer.open(context, info.url!),
            );
          }
          return MediaUnavailableTile(label: info.name ?? 'Photo', textColor: textColor, hint: 'File was not saved — resend');
        case AttachmentKind.video:
          if (info.url != null) {
            return VideoMessageTile(
              url: info.url!,
              name: info.name,
              onTap: onMediaOpen != null ? () => onMediaOpen!(message, info) : null,
            );
          }
          return MediaUnavailableTile(label: info.name ?? 'Video', textColor: textColor, hint: 'File was not saved — resend');
        case AttachmentKind.voice:
          if (info.url != null) {
            return VoiceMessagePlayer(url: info.url!, durationLabel: info.duration, textColor: textColor);
          }
          return MediaUnavailableTile(label: 'Voice message', textColor: textColor, hint: 'File was not saved — resend');
        case AttachmentKind.location:
          if (info.latitude != null && info.longitude != null) {
            return LocationMessageTile(
              latitude: info.latitude!,
              longitude: info.longitude!,
              address: info.address,
              mapsUrl: info.url,
              textColor: textColor,
            );
          }
          break;
        case AttachmentKind.contact:
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person, color: textColor.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${info.raw['name']}', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  Text('${info.raw['phone']}', style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 13)),
                ],
              ),
            ],
          );
        case AttachmentKind.file:
          return FileMessageTile(
            name: info.name ?? 'Attachment',
            url: info.url,
            textColor: textColor,
          );
        default:
          break;
      }
    }

    final urls = extractUrlsFromText(message.body);
    if (urls.isNotEmpty && message.body.trim().isNotEmpty) {
      final url = urls.first;
      final bodyWithoutUrl = message.body.replaceFirst(url, '').trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bodyWithoutUrl.isNotEmpty)
            Text(bodyWithoutUrl, style: TextStyle(color: textColor, fontSize: 15.5, height: 1.35)),
          if (bodyWithoutUrl.isNotEmpty) const SizedBox(height: 8),
          LinkPreviewTile(url: url, textColor: textColor),
        ],
      );
    }

    if (message.body.isEmpty) {
      return Text(_typeLabel(message.type), style: TextStyle(color: textColor, fontSize: 15.5, height: 1.35));
    }

    return Text(message.body, style: TextStyle(color: textColor, fontSize: 15.5, height: 1.35));
  }

  static String _typeLabel(String type) {
    return switch (type) {
      'file' => 'Attachment',
      'image' => 'Photo',
      'voice' => 'Voice message',
      'call' => 'Call',
      'erp_card' => 'ERP card',
      'location' => 'Location',
      'contact' => 'Contact',
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
