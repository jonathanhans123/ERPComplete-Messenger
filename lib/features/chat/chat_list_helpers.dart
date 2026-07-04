import '../../core/messaging/messaging_repository.dart';
import '../../core/models/api_models.dart';

/// Flatten messages + date dividers for ListView.builder.
sealed class ChatListEntry {}

class ChatDateDividerEntry extends ChatListEntry {
  ChatDateDividerEntry(this.label);
  final String label;
}

class ChatMessageEntry extends ChatListEntry {
  ChatMessageEntry(this.message);
  final ChatMessage message;
}

List<ChatListEntry> buildChatListEntries(List<ChatMessage> messages) {
  final entries = <ChatListEntry>[];
  String? lastDate;
  for (final msg in messages) {
    final dateKey = msg.date;
    if (dateKey != null && dateKey != lastDate) {
      entries.add(ChatDateDividerEntry(MessageDate.dividerLabel(dateKey)));
      lastDate = dateKey;
    }
    entries.add(ChatMessageEntry(msg));
  }
  return entries;
}

bool chatMessagesChanged(List<ChatMessage> a, List<ChatMessage> b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].contentEquals(b[i])) return true;
  }
  return false;
}

ChatMessage applyStarred(ChatMessage msg, Set<int> starredIds) {
  final starred = starredIds.contains(msg.id);
  if (msg.isStarred == starred) return msg;
  return msg.copyWith(isStarred: starred);
}

List<ChatMessage> applyStarredAll(List<ChatMessage> messages, Set<int> starredIds) {
  return messages.map((m) => applyStarred(m, starredIds)).toList();
}

Future<List<ConversationSummary>> fetchForwardTargets(MessagingRepository repo, {required int excludeConversationId}) async {
  final all = await repo.fetchConversations();
  return all.where((c) => c.id != excludeConversationId).toList();
}
