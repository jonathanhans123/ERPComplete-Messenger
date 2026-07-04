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
    this.lastMessagePreview,
    this.unreadCount = 0,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as int? ?? json['conversation_id'] as int? ?? 0,
      title: json['title'] as String? ??
          json['name'] as String? ??
          json['display_name'] as String? ??
          'Conversation',
      lastMessagePreview: json['last_message_preview'] as String? ??
          json['last_message'] as String?,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  final int id;
  final String title;
  final String? lastMessagePreview;
  final int unreadCount;
}
