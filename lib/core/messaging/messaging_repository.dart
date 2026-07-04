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

  Future<List<ConversationSummary>> fetchConversations({ConversationFilter filter = ConversationFilter.all}) async {
    final json = await _client().getJson('messaging/conversations', query: _filterQuery(filter));
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

  Future<ChatMessage> sendTextMessage({required int conversationId, required String body}) async {
    final json = await _client().postForm('messaging/messages', {
      'conversation_id': '$conversationId',
      'type': 'text',
      'body': body,
    });
    final data = json['data'] ?? json;
    final msg = (data is Map ? data['message'] : null) as Map<String, dynamic>? ?? (data as Map<String, dynamic>?);
    if (msg == null) throw ApiException('Unexpected send response');
    return ChatMessage.fromJson(msg, currentUserId ?? 0);
  }

  Future<void> markRead(int conversationId) async {
    await _client().postJson('messaging/conversations/$conversationId/mark-read');
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
