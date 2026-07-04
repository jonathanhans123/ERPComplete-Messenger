import '../api/api_client.dart';
import '../models/api_models.dart';

class MessagingRepository {
  MessagingRepository(this._client);

  final ApiClient Function() _client;

  Future<List<ConversationSummary>> fetchConversations() async {
    final json = await _client().getJson('messaging/conversations');
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final list = data['conversations'];
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map(ConversationSummary.fromJson)
            .toList();
      }
    }
    final raw = json['conversations'] ?? data ?? json;
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ConversationSummary.fromJson)
        .toList();
  }
}
