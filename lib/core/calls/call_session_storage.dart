import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists in-call metadata so a 1:1 call can be rejoined after process death.
class CallSessionStorage {
  CallSessionStorage._();

  static const _key = 'messenger_active_call_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> save(CallSessionSnapshot snapshot) async {
    await _storage.write(key: _key, value: jsonEncode(snapshot.toJson()));
  }

  static Future<CallSessionSnapshot?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CallSessionSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}

class CallSessionSnapshot {
  const CallSessionSnapshot({
    required this.conversationId,
    required this.messageId,
    required this.sessionId,
    required this.room,
    required this.displayName,
    required this.isVideo,
    required this.isGroup,
    required this.callWasAnswered,
    required this.isOutgoing,
    this.isMultiParty = false,
    this.remoteParticipantCount = 0,
  });

  factory CallSessionSnapshot.fromJson(Map<String, dynamic> json) {
    return CallSessionSnapshot(
      conversationId: json['conversation_id'] as int,
      messageId: json['message_id'] as int,
      sessionId: json['session_id'] as String,
      room: json['room'] as String,
      displayName: json['display_name'] as String? ?? 'User',
      isVideo: json['is_video'] == true,
      isGroup: json['is_group'] == true,
      callWasAnswered: json['call_was_answered'] == true,
      isOutgoing: json['is_outgoing'] == true,
      isMultiParty: json['is_multi_party'] == true,
      remoteParticipantCount: json['remote_participant_count'] as int? ?? 0,
    );
  }

  final int conversationId;
  final int messageId;
  final String sessionId;
  final String room;
  final String displayName;
  final bool isVideo;
  final bool isGroup;
  final bool callWasAnswered;
  final bool isOutgoing;
  final bool isMultiParty;
  final int remoteParticipantCount;

  bool get isGroupLike => isGroup || isMultiParty || remoteParticipantCount >= 2;

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'message_id': messageId,
        'session_id': sessionId,
        'room': room,
        'display_name': displayName,
        'is_video': isVideo,
        'is_group': isGroup,
        'call_was_answered': callWasAnswered,
        'is_outgoing': isOutgoing,
        'is_multi_party': isMultiParty,
        'remote_participant_count': remoteParticipantCount,
      };
}
