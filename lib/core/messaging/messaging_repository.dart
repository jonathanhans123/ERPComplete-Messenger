import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import '../models/api_models.dart';

class MessagingRepository {
  MessagingRepository(this._client, {this.currentUserId});

  final ApiClient Function() _client;
  final int? currentUserId;

  Map<String, String> _filterQuery(ConversationFilter filter) {
    switch (filter) {
      case ConversationFilter.archived:
        return {'archived': '1'};
      case ConversationFilter.groups:
        return {'type': 'group'};
      case ConversationFilter.teams:
        return {'channel_kind': 'team'};
      case ConversationFilter.operations:
        return {'channel_kind': 'operations'};
      case ConversationFilter.unread:
      case ConversationFilter.all:
        return {};
    }
  }

  Future<List<ConversationSummary>> fetchConversations({
    ConversationFilter filter = ConversationFilter.all,
    String? search,
  }) async {
    final query = _filterQuery(filter);
    if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();
    final json = await _client().getJson('messaging/conversations', query: query);
    final data = json['data'];
    List<dynamic> list;
    if (data is Map<String, dynamic>) {
      list = data['conversations'] as List? ?? [];
    } else {
      list = json['conversations'] as List? ?? (data is List ? data : []);
    }
    var items = list.whereType<Map<String, dynamic>>().map(ConversationSummary.fromJson).toList();
    if (filter == ConversationFilter.unread) {
      items = items.where((c) => c.unreadCount > 0 && !c.isArchived).toList();
    }
    return items;
  }

  Future<int> fetchUnreadCount() async {
    final json = await _client().getJson('messaging/unread-count');
    final data = json['data'] ?? json;
    if (data is Map) return data['count'] as int? ?? data['unread'] as int? ?? 0;
    return json['count'] as int? ?? 0;
  }

  Future<List<AccessibleUser>> fetchAccessibleUsers({String? search}) async {
    final json = await _client().getJson('messaging/users/accessible', query: search != null ? {'search': search} : null);
    final data = json['data'] ?? json;
    final list = (data is Map ? data['users'] : null) as List? ?? json['users'] as List? ?? (data is List ? data : []);
    return list.whereType<Map<String, dynamic>>().map(AccessibleUser.fromJson).toList();
  }

  Future<ConversationSummary> createConversation({
    required String type,
    required List<int> participantIds,
    String? name,
    String? description,
  }) async {
    final json = await _client().postJson('messaging/conversations', body: {
      'type': type,
      'participant_ids': participantIds,
      if (name != null && name.isNotEmpty) 'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    final data = json['data'] ?? json;
    final conv = (data is Map ? data['conversation'] : null) as Map<String, dynamic>? ?? data as Map<String, dynamic>;
    return ConversationSummary.fromJson(conv);
  }

  Future<ConversationDetail> fetchConversation(int conversationId) async {
    final json = await _client().getJson('messaging/conversations/$conversationId');
    final data = json['data'] ?? json;
    return ConversationDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<ConversationDetail> updateGroup({
    required int conversationId,
    required String name,
    String? description,
    required List<int> participantIds,
  }) async {
    final json = await _client().putJson('messaging/conversations/$conversationId', body: {
      'name': name,
      'description': description ?? '',
      'participant_ids': participantIds,
    });
    final data = json['data'] ?? json;
    return ConversationDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<String> exportChat(int conversationId) async {
    final json = await _client().getJson('messaging/conversations/$conversationId/export');
    final data = json['data'] ?? json;
    if (data is Map && data['content'] != null) return data['content'].toString();
    return jsonEncode(data);
  }

  Future<void> sendCallSignal({
    required int conversationId,
    required String action,
    required String callSessionId,
    required String roomName,
    int? messageId,
  }) async {
    await _client().postJson('messaging/conversations/$conversationId/call-signal', body: {
      'action': action,
      'call_session_id': callSessionId,
      'room_name': roomName,
      if (messageId != null) 'message_id': messageId,
    });
  }

  Future<List<ChatMessage>> fetchMessages(int conversationId, {int page = 1}) async {
    final json = await _client().getJson(
      'messaging/conversations/$conversationId/messages',
      query: {'page': '$page'},
    );
    final data = json['data'] ?? json;
    final list = (data is Map ? data['messages'] : null) as List? ?? json['messages'] as List? ?? [];
    final uid = currentUserId ?? 0;
    return list.whereType<Map<String, dynamic>>().map((m) => ChatMessage.fromJson(m, uid)).toList();
  }

  Future<ChatMessage> sendTextMessage({
    required int conversationId,
    required String body,
    int? replyToMessageId,
  }) async {
    final fields = {
      'conversation_id': '$conversationId',
      'type': 'text',
      'body': body,
      if (replyToMessageId != null) 'reply_to_message_id': '$replyToMessageId',
    };
    final json = await _client().postForm('messaging/messages', fields);
    return _parseMessage(json);
  }

  Future<ChatMessage> sendFileMessage({
    required int conversationId,
    required File file,
    String? caption,
  }) async {
    final json = await _client().postMultipart(
      'messaging/messages',
      fields: {
        'conversation_id': '$conversationId',
        'type': 'file',
        if (caption != null && caption.isNotEmpty) 'body': caption,
      },
      files: [(field: 'attachments[]', file: file, filename: file.path.split(Platform.pathSeparator).last)],
    );
    return _parseMessage(json);
  }

  ChatMessage _parseMessage(Map<String, dynamic> json, {ChatMessage? fallback}) {
    final data = json['data'] ?? json;
    final msg = (data is Map ? data['message'] : null) as Map<String, dynamic>? ?? (data as Map<String, dynamic>?);
    if (msg == null) throw ApiException('Unexpected message response');
    final parsed = ChatMessage.fromJson(msg, currentUserId ?? 0);
    if (fallback == null) return parsed;
    return parsed.copyWith(
      isSent: parsed.senderId != 0 ? parsed.isSent : fallback.isSent,
      isStarred: fallback.isStarred,
    );
  }

  Future<void> markRead(int conversationId) async {
    await _client().postJson('messaging/conversations/$conversationId/mark-read');
  }

  Future<void> sendTyping(int conversationId, bool isTyping) async {
    await _client().postJson('messaging/conversations/$conversationId/typing', body: {'typing': isTyping});
  }

  Future<void> togglePinConversation(int conversationId, bool pinned) async {
    await _client().postJson('messaging/conversations/$conversationId/toggle-pin', body: {'pin': pinned});
  }

  Future<void> toggleArchiveConversation(int conversationId, bool archived) async {
    await _client().postJson('messaging/conversations/$conversationId/toggle-archive', body: {'archive': archived});
  }

  Future<void> clearChat(int conversationId) async {
    await _client().postJson('messaging/conversations/$conversationId/clear');
  }

  Future<ChatMessage> updateMessage(int messageId, String body, {ChatMessage? fallback}) async {
    final json = await _client().putJson('messaging/messages/$messageId', body: {'body': body});
    return _parseMessage(json, fallback: fallback?.copyWith(body: body, isEdited: true));
  }

  Future<void> deleteMessage(int messageId) async {
    await _client().deleteJson('messaging/messages/$messageId');
  }

  Future<ChatMessage> toggleReaction(int messageId, String emoji, {ChatMessage? fallback}) async {
    final json = await _client().postJson('messaging/messages/$messageId/toggle-reaction', body: {'reaction': emoji});
    return _parseMessage(json, fallback: fallback);
  }

  Future<ChatMessage> togglePinMessage(int messageId, bool pinned, {ChatMessage? fallback}) async {
    final json = await _client().postJson('messaging/messages/$messageId/toggle-pin', body: {'pin': pinned});
    return _parseMessage(json, fallback: fallback?.copyWith(isPinned: pinned));
  }

  Future<int> forwardMessages({
    required int conversationId,
    required List<int> messageIds,
    required List<int> targetConversationIds,
    String? comment,
  }) async {
    final json = await _client().postJson('messaging/messages/forward', body: {
      'conversation_id': conversationId,
      'message_ids': messageIds,
      'target_conversation_ids': targetConversationIds,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    final data = json['data'] ?? json;
    if (data is Map) return data['forwarded_count'] as int? ?? messageIds.length;
    return messageIds.length;
  }

  Future<List<ErpCardSummary>> searchErpCards(String query) async {
    final json = await _client().getJson('messaging/erp-cards/search', query: {'q': query});
    final data = json['data'] ?? json;
    final list = (data is Map ? data['cards'] : null) as List? ?? json['cards'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(ErpCardSummary.fromJson).toList();
  }

  Future<LiveCallToken> liveCallToken({
    required String room,
    required String displayName,
    String? identity,
  }) async {
    final json = await _client().postJson('messaging/live-call/token', body: {
      'room': room,
      'name': displayName,
      if (identity != null) 'identity': identity,
    });
    return LiveCallToken.fromJson(json);
  }

  static String messengerCallRoom(int conversationId) => 'messaging-call-$conversationId';
}
