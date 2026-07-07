import '../media/media_url_resolver.dart';

enum ConversationFilter { all, unread, groups, teams, operations, archived }

class LoginRequest {
  LoginRequest({
    required this.email,
    required this.password,
    this.twoFactorCode,
    this.deviceName = 'ERPComplete-Messenger',
  });

  final String email;
  final String password;
  final String? twoFactorCode;
  final String deviceName;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'email': email,
      'password': password,
      'device_name': deviceName,
    };
    final code = twoFactorCode?.trim();
    if (code != null && code.isNotEmpty) {
      map['two_factor_code'] = code;
    }
    return map;
  }
}

class LoginResponse {
  LoginResponse({this.accessToken, this.user});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'] as String?,
      user: json['user'] != null ? UserSummary.fromJson(json['user'] as Map<String, dynamic>) : null,
    );
  }

  final String? accessToken;
  final UserSummary? user;
}

class UserSummary {
  UserSummary({
    required this.id,
    required this.name,
    required this.email,
    this.currentBusinessUnitId,
    this.currentTeamId,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      currentBusinessUnitId: json['current_business_unit_id'] as int?,
      currentTeamId: json['current_team_id'] as int?,
    );
  }

  final int id;
  final String name;
  final String email;
  final int? currentBusinessUnitId;
  final int? currentTeamId;
}

class AccessibleUser {
  AccessibleUser({required this.id, required this.name, this.email, this.avatarUrl});

  factory AccessibleUser.fromJson(Map<String, dynamic> json) {
    return AccessibleUser(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final int id;
  final String name;
  final String? email;
  final String? avatarUrl;

  String get initials => ConversationSummary.initialsFrom(name);
}

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.title,
    this.avatarInitials,
    this.avatarUrl,
    this.lastMessagePreview,
    this.lastMessageType,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isGroup = false,
    this.channelKind = 'free',
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.online,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'] as Map<String, dynamic>?;
    return ConversationSummary(
      id: json['id'] as int,
      title: json['name'] as String? ?? 'Conversation',
      avatarInitials: initialsFrom(json['name'] as String?),
      avatarUrl: json['avatar'] as String?,
      lastMessagePreview: last?['body'] as String? ?? last?['preview'] as String?,
      lastMessageType: last?['type'] as String?,
      lastMessageTime: last?['time'] as String?,
      unreadCount: json['unread'] as int? ?? json['unread_count'] as int? ?? 0,
      isGroup: json['type'] == 'group',
      channelKind: json['channel_kind'] as String? ?? 'free',
      isPinned: json['is_pinned'] as bool? ?? json['pinned'] as bool? ?? false,
      isMuted: json['is_muted'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? json['archived'] as bool? ?? false,
      online: json['online'] as bool?,
    );
  }

  ConversationSummary copyWith({
    bool? isPinned,
    bool? isArchived,
    bool? isMuted,
    String? title,
  }) {
    return ConversationSummary(
      id: id,
      title: title ?? this.title,
      avatarInitials: avatarInitials,
      avatarUrl: avatarUrl,
      lastMessagePreview: lastMessagePreview,
      lastMessageType: lastMessageType,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      isGroup: isGroup,
      channelKind: channelKind,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      online: online,
    );
  }

  final int id;
  final String title;
  final String? avatarInitials;
  final String? avatarUrl;
  final String? lastMessagePreview;
  final String? lastMessageType;
  final String? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final String channelKind;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool? online;

  static String initialsFrom(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class ConversationParticipant {
  ConversationParticipant({required this.id, required this.name, this.email, this.avatarUrl});

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      avatarUrl: json['avatar'] as String?,
    );
  }

  final int id;
  final String name;
  final String? email;
  final String? avatarUrl;

  String get initials => ConversationSummary.initialsFrom(name);
}

class ConversationDetail {
  ConversationDetail({
    required this.id,
    required this.title,
    required this.type,
    this.description,
    this.avatarUrl,
    this.participants = const [],
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.channelKind = 'free',
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    final parts = json['participants'];
    return ConversationDetail(
      id: json['id'] as int,
      title: json['name'] as String? ?? 'Conversation',
      type: json['type'] as String? ?? 'direct',
      description: json['description'] as String?,
      avatarUrl: json['avatar'] as String?,
      participants: parts is List
          ? parts.whereType<Map<String, dynamic>>().map(ConversationParticipant.fromJson).toList()
          : [],
      isPinned: json['is_pinned'] as bool? ?? false,
      isMuted: json['is_muted'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
      channelKind: json['channel_kind'] as String? ?? 'free',
    );
  }

  bool get isGroup => type == 'group';

  ConversationSummary toSummary() {
    return ConversationSummary(
      id: id,
      title: title,
      avatarInitials: ConversationSummary.initialsFrom(title),
      avatarUrl: avatarUrl,
      isGroup: isGroup,
      channelKind: channelKind,
      isPinned: isPinned,
      isMuted: isMuted,
      isArchived: isArchived,
    );
  }

  final int id;
  final String title;
  final String type;
  final String? description;
  final String? avatarUrl;
  final List<ConversationParticipant> participants;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final String channelKind;
}

class CallMessageMeta {
  CallMessageMeta({
    required this.callSessionId,
    required this.roomName,
    this.phase = 'ringing',
    this.callKind = 'voice',
    this.durationSeconds,
    this.callOutcome,
    this.callConnected = false,
  });

  factory CallMessageMeta.fromJson(Map<String, dynamic> json) {
    return CallMessageMeta(
      callSessionId: json['call_session_id'] as String? ?? '',
      roomName: json['room_name'] as String? ?? '',
      phase: json['phase'] as String? ?? 'ringing',
      callKind: json['call_kind'] as String? ?? 'voice',
      durationSeconds: json['duration_seconds'] as int?,
      callOutcome: json['call_outcome'] as String?,
      callConnected: json['call_connected'] == true || json['call_connected'] == 1,
    );
  }

  final String callSessionId;
  final String roomName;
  final String phase;
  final String callKind;
  final int? durationSeconds;
  final String? callOutcome;
  final bool callConnected;

  bool get isVideo => callKind == 'video';
}

extension ChatMessageCallX on ChatMessage {
  /// True when the server still considers this call joinable (live or ringing).
  bool get isRejoinableCall {
    if (type != 'call') return false;
    final meta = callMeta;
    if (meta == null || meta.roomName.isEmpty || meta.callSessionId.isEmpty) return false;
    final phase = meta.phase.toLowerCase();
    if (phase == 'declined' || phase == 'ended') return false;
    return phase == 'live' || phase == 'ringing';
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.body,
    required this.senderName,
    required this.senderId,
    required this.isSent,
    this.time,
    this.date,
    this.createdAt,
    this.type = 'text',
    this.status,
    this.isPinned = false,
    this.isForwarded = false,
    this.isEdited = false,
    this.isStarred = false,
    this.isPending = false,
    this.reactions = const {},
    this.replyToId,
    this.replyPreview,
    this.replyToSender,
    this.attachments = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId) {
    final senderId = json['sender_id'] as int? ?? json['user_id'] as int? ?? 0;
    final user = json['user'];
    final senderName = json['sender'] as String? ??
        json['sender_name'] as String? ??
        (user is Map ? user['name'] as String? : null) ??
        'Unknown';
    final msgType = json['type'] as String? ?? 'text';

    final replyTo = json['reply_to'];
    String? replyPreview;
    String? replyToSender;
    int? replyToId;
    if (replyTo is Map<String, dynamic>) {
      replyToId = replyTo['id'] as int?;
      replyPreview = replyTo['body'] as String?;
      replyToSender = replyTo['sender'] as String?;
    } else {
      replyToId = json['reply_to_message_id'] as int?;
      replyPreview = json['reply_preview'] as String?;
      replyToSender = json['reply_to_sender'] as String?;
    }

    final atts = _parseAttachments(json['attachments']);

    return ChatMessage(
      id: json['id'] as int? ?? 0,
      body: json['body'] as String? ?? '',
      senderName: senderName,
      senderId: senderId,
      isSent: json['sent'] as bool? ?? (senderId == currentUserId && senderId != 0),
      time: json['time'] as String? ?? _timeFromIso(json['created_at']),
      date: json['date'] as String? ?? _dateFromIso(json['created_at']),
      createdAt: json['created_at'] as String?,
      type: msgType,
      status: json['status'] as String?,
      isPinned: json['is_pinned'] as bool? ?? json['pinned'] as bool? ?? false,
      isForwarded: json['is_forwarded'] as bool? ?? false,
      isEdited: msgType == 'call' ? false : (json['edited'] as bool? ?? _isEdited(json)),
      reactions: normalizeReactions(json['reactions']),
      replyToId: replyToId,
      replyPreview: replyPreview,
      replyToSender: replyToSender,
      attachments: atts,
    );
  }

  static List<Map<String, dynamic>> _parseAttachments(dynamic raw) {
    List<Map<String, dynamic>> list;
    if (raw is List) {
      list = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } else if (raw is Map) {
      list = [Map<String, dynamic>.from(raw)];
    } else {
      return [];
    }
    return list.map((att) {
      final copy = Map<String, dynamic>.from(att);
      final path = copy['path'];
      if (path == false || path == null || path == '') {
        copy.remove('path');
      }
      final url = copy['url'];
      if (url == null || url == false || (url is String && url.trim().isEmpty)) {
        copy.remove('url');
      } else if (url is String) {
        copy['url'] = MediaUrlResolver.resolve(url);
      }
      if (path is String && path.isNotEmpty && (copy['url'] == null || copy['url'] == '')) {
        copy['url'] = MediaUrlResolver.resolve('/storage/$path');
      }
      return copy;
    }).toList();
  }

  static bool _isEdited(Map<String, dynamic> json) {
    if (json['type'] == 'call') return false;
    if (json['edited'] == true) return true;
    final created = json['created_at'] as String?;
    final updated = json['updated_at'] as String?;
    if (created == null || updated == null) return false;
    try {
      return DateTime.parse(updated).isAfter(DateTime.parse(created).add(const Duration(seconds: 1)));
    } catch (_) {
      return false;
    }
  }

  static String? _dateFromIso(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value).toIso8601String().substring(0, 10);
    } catch (_) {
      return null;
    }
  }

  static String? _timeFromIso(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    try {
      final dt = DateTime.parse(value).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    } catch (_) {
      return null;
    }
  }

  static Map<String, int> normalizeReactions(dynamic reactionsRaw) {
    final result = <String, int>{};
    if (reactionsRaw is! Map) return result;

    final keys = reactionsRaw.keys.map((k) => k.toString()).toList();
    final isUserIdMap = keys.isNotEmpty && keys.every((k) => RegExp(r'^\d+$').hasMatch(k));

    if (isUserIdMap) {
      for (final entry in reactionsRaw.entries) {
        final emoji = entry.value?.toString() ?? '';
        if (emoji.isEmpty) continue;
        result[emoji] = (result[emoji] ?? 0) + 1;
      }
    } else {
      for (final entry in reactionsRaw.entries) {
        final emoji = entry.key.toString();
        final val = entry.value;
        if (val is List) {
          result[emoji] = val.length;
        } else if (val is int) {
          result[emoji] = val;
        } else if (val != null) {
          result[emoji] = 1;
        }
      }
    }
    return result;
  }

  ChatMessage copyWith({
    Map<String, int>? reactions,
    String? body,
    bool? isPinned,
    bool? isEdited,
    bool? isStarred,
    String? status,
    bool? isPending,
    int? id,
    bool? isSent,
    int? replyToId,
    String? replyPreview,
    String? replyToSender,
    List<Map<String, dynamic>>? attachments,
    String? type,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      body: body ?? this.body,
      senderName: senderName,
      senderId: senderId,
      isSent: isSent ?? this.isSent,
      time: time,
      date: date,
      createdAt: createdAt,
      type: type ?? this.type,
      status: status ?? this.status,
      isPinned: isPinned ?? this.isPinned,
      isForwarded: isForwarded,
      isEdited: isEdited ?? this.isEdited,
      isStarred: isStarred ?? this.isStarred,
      isPending: isPending ?? this.isPending,
      reactions: reactions ?? this.reactions,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      replyToSender: replyToSender ?? this.replyToSender,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic>? get primaryAttachment => attachments.isNotEmpty ? attachments.first : null;

  CallMessageMeta? get callMeta {
    if (type != 'call') return null;
    for (final a in attachments) {
      if (a.containsKey('call_session_id') || a.containsKey('room_name')) {
        return CallMessageMeta.fromJson(a);
      }
    }
    return null;
  }

  Map<String, dynamic>? get pollAttachment {
    for (final a in attachments) {
      if (a['type'] == 'poll') return a;
    }
    final p = primaryAttachment;
    return p != null && p['type'] == 'poll' ? p : null;
  }

  String get callDisplayLine {
    final meta = callMeta;
    if (meta == null) return body.isNotEmpty ? body : 'Call';
    final video = meta.isVideo || body.toLowerCase().contains('video');
    final outcome = (meta.callOutcome ?? '').toLowerCase();
    final sentByMe = isSent;

    if (meta.phase == 'live') {
      return video ? 'Video call in progress' : 'Voice call in progress';
    }

    if (meta.phase == 'declined' ||
        outcome == 'missed' ||
        outcome == 'rejected' ||
        outcome == 'cancelled') {
      final o = outcome.isNotEmpty ? outcome : 'missed';
      if (o == 'rejected') {
        return sentByMe
            ? (video ? 'Video call declined' : 'Call declined')
            : (video ? 'Declined video call' : 'Declined call');
      }
      if (o == 'cancelled') {
        return sentByMe
            ? (video ? 'Video call cancelled' : 'Call cancelled')
            : (video ? 'Missed video call' : 'Missed voice call');
      }
      return sentByMe
          ? 'No answer'
          : (video ? 'Missed video call' : 'Missed voice call');
    }

    if (meta.phase == 'ended') {
      if (meta.callConnected && meta.durationSeconds != null && meta.durationSeconds! > 0) {
        final s = meta.durationSeconds!;
        return 'Duration ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      }
      if (!meta.callConnected) {
        return sentByMe
            ? 'No answer'
            : (video ? 'Missed video call' : 'Missed voice call');
      }
      if (meta.durationSeconds != null && meta.durationSeconds! > 0) {
        final s = meta.durationSeconds!;
        return 'Duration ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      }
      return video ? 'Video call ended' : 'Voice call ended';
    }

    return body.isNotEmpty ? body : (video ? 'Video call' : 'Voice call');
  }

  final List<Map<String, dynamic>> attachments;

  String get reactionsFingerprint {
    if (reactions.isEmpty) return '';
    return reactions.entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  bool contentEquals(ChatMessage other) {
    return id == other.id &&
        body == other.body &&
        isPinned == other.isPinned &&
        isEdited == other.isEdited &&
        isForwarded == other.isForwarded &&
        status == other.status &&
        reactionsFingerprint == other.reactionsFingerprint &&
        replyPreview == other.replyPreview;
  }

  final int id;
  final String body;
  final String senderName;
  final int senderId;
  final bool isSent;
  final String? time;
  final String? date;
  final String? createdAt;
  final String type;
  final String? status;
  final bool isPinned;
  final bool isForwarded;
  final bool isEdited;
  final bool isStarred;
  final bool isPending;
  final Map<String, int> reactions;
  final int? replyToId;
  final String? replyPreview;
  final String? replyToSender;
}

class MessageDate {
  static String dividerLabel(String? ymd) {
    if (ymd == null || ymd.isEmpty) return 'Today';
    DateTime msgDate;
    try {
      msgDate = DateTime.parse('${ymd}T00:00:00');
    } catch (_) {
      return ymd;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(msgDate.year, msgDate.month, msgDate.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    if (day.year != today.year) {
      return '${months[day.month - 1]} ${day.day}, ${day.year}';
    }
    return '${months[day.month - 1]} ${day.day}';
  }
}

class LiveCallToken {
  LiveCallToken({required this.token, required this.url, required this.room, required this.identity, required this.name});

  factory LiveCallToken.fromJson(Map<String, dynamic> json) {
    return LiveCallToken(
      token: json['token'] as String? ?? '',
      url: json['url'] as String? ?? '',
      room: json['room'] as String? ?? '',
      identity: json['identity'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  final String token;
  final String url;
  final String room;
  final String identity;
  final String name;
}

class ErpCardSummary {
  ErpCardSummary({required this.type, required this.id, required this.title, this.subtitle});

  factory ErpCardSummary.fromJson(Map<String, dynamic> json) {
    return ErpCardSummary(
      type: json['type'] as String? ?? '',
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
    );
  }

  final String type;
  final String id;
  final String title;
  final String? subtitle;
}
