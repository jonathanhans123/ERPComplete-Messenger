import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/api_models.dart';

/// Persists conversations and messages locally for offline / rate-limit fallback.
class MessengerLocalCache {
  MessengerLocalCache._();
  static final instance = MessengerLocalCache._();

  Future<File> _cacheFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/messenger_cache');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return File('${folder.path}/$name');
  }

  Future<void> saveConversations(List<ConversationSummary> items) async {
    try {
      final payload = items
          .map(
            (c) => {
              'id': c.id,
              'name': c.title,
              'avatar': c.avatarUrl,
              'last_message': {
                'body': c.lastMessagePreview,
                'type': c.lastMessageType,
                'time': c.lastMessageTime,
              },
              'unread': c.unreadCount,
              'type': c.isGroup ? 'group' : 'direct',
              'channel_kind': c.channelKind,
              'is_pinned': c.isPinned,
              'is_muted': c.isMuted,
              'is_archived': c.isArchived,
              'online': c.online,
            },
          )
          .toList();
      await (await _cacheFile('conversations.json')).writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<List<ConversationSummary>> loadConversations() async {
    try {
      final file = await _cacheFile('conversations.json');
      if (!file.existsSync()) return [];
      final list = jsonDecode(await file.readAsString());
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(ConversationSummary.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(int conversationId, List<ChatMessage> messages) async {
    try {
      final payload = messages
          .map(
            (m) => {
              'id': m.id,
              'body': m.body,
              'type': m.type,
              'sender_name': m.senderName,
              'sender_id': m.senderId,
              'is_sent': m.isSent,
              'time': m.time,
              'date': m.date,
              'status': m.status,
              'attachments': m.attachments,
              'reply_to_id': m.replyToId,
              'reply_preview': m.replyPreview,
              'reply_to_sender': m.replyToSender,
            },
          )
          .toList();
      await (await _cacheFile('messages_$conversationId.json')).writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<List<ChatMessage>> loadMessages(int conversationId, {int? currentUserId}) async {
    try {
      final file = await _cacheFile('messages_$conversationId.json');
      if (!file.existsSync()) return [];
      final list = jsonDecode(await file.readAsString());
      if (list is! List) return [];
      final uid = currentUserId ?? 0;
      return list.whereType<Map<String, dynamic>>().map((m) => ChatMessage.fromJson(m, uid)).toList();
    } catch (_) {
      return [];
    }
  }
}
