enum ConversationFilter { all, unread, groups, teams, operations, archived }

class LoginRequest {
  LoginRequest({required this.email, required this.password, this.deviceName = 'ERPComplete-Messenger'});

  final String email;
  final String password;
  final String deviceName;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'device_name': deviceName,
      };
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
  UserSummary({required this.id, required this.name, required this.email});

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String email;
}

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.title,
    this.avatarInitials,
    this.lastMessagePreview,
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
      avatarInitials: _initials(json['name'] as String?),
      lastMessagePreview: last?['body'] as String?,
      lastMessageTime: last?['time'] as String?,
      unreadCount: json['unread'] as int? ?? 0,
      isGroup: json['type'] == 'group',
      channelKind: json['channel_kind'] as String? ?? 'free',
      isPinned: json['is_pinned'] as bool? ?? false,
      isMuted: json['is_muted'] as bool? ?? false,
      isArchived: json['is_archived'] as bool? ?? false,
      online: json['online'] as bool?,
    );
  }

  final int id;
  final String title;
  final String? avatarInitials;
  final String? lastMessagePreview;
  final String? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final String channelKind;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool? online;

  static String? _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
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
    this.type = 'text',
    this.status,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId) {
    final senderId = json['sender_id'] as int? ?? 0;
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      body: json['body'] as String? ?? '',
      senderName: json['sender'] as String? ?? 'Unknown',
      senderId: senderId,
      isSent: json['sent'] as bool? ?? senderId == currentUserId,
      time: json['time'] as String?,
      type: json['type'] as String? ?? 'text',
      status: json['status'] as String?,
    );
  }

  final int id;
  final String body;
  final String senderName;
  final int senderId;
  final bool isSent;
  final String? time;
  final String type;
  final String? status;
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
