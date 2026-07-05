import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'incoming_call_action_handler.dart';

class MessengerNotificationService {
  MessengerNotificationService._();
  static final instance = MessengerNotificationService._();

  static const actionAccept = 'call_accept';
  static const actionDecline = 'call_decline';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _channelId = 'messenger_messages';
  static const _callChannelId = 'messenger_calls';
  static const _incomingCallChannelId = 'messenger_incoming_calls';
  static const _callNotificationId = 9001;
  static const _incomingCallNotificationId = 9002;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Messages',
          description: 'New chat messages',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _callChannelId,
          'Calls',
          description: 'Ongoing voice and video calls',
          importance: Importance.low,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _incomingCallChannelId,
          'Incoming calls',
          description: 'Incoming voice and video calls',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestFullScreenIntentPermission();
    }
    _initialized = true;
  }

  static void _onNotificationResponse(NotificationResponse response) {
    if (response.id == _callNotificationId) {
      IncomingCallActionHandler.handleOngoingCallTap();
      return;
    }
    IncomingCallActionHandler.handlePayload(
      actionId: response.actionId,
      payload: response.payload,
    );
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    if (response.id == _callNotificationId) {
      IncomingCallActionHandler.handleOngoingCallTap();
      return;
    }
    IncomingCallActionHandler.handlePayload(
      actionId: response.actionId,
      payload: response.payload,
    );
  }

  static String encodeIncomingCallPayload({
    required int conversationId,
    required int messageId,
    required String callerName,
    required bool isVideo,
  }) {
    return jsonEncode({
      'conversation_id': conversationId,
      'message_id': messageId,
      'caller_name': callerName,
      'is_video': isVideo,
    });
  }

  static Map<String, dynamic>? decodeIncomingCallPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      return {
        'conversation_id': decoded['conversation_id'] is int
            ? decoded['conversation_id'] as int
            : int.tryParse('${decoded['conversation_id']}'),
        'message_id': decoded['message_id'] is int
            ? decoded['message_id'] as int
            : int.tryParse('${decoded['message_id']}'),
        'caller_name': decoded['caller_name']?.toString(),
        'is_video': decoded['is_video'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Messages',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> showIncomingCallNotification({
    required int conversationId,
    required int messageId,
    required String callerName,
    required bool isVideo,
  }) async {
    if (!_initialized) return;
    final payload = encodeIncomingCallPayload(
      conversationId: conversationId,
      messageId: messageId,
      callerName: callerName,
      isVideo: isVideo,
    );
    await _plugin.show(
      _incomingCallNotificationId,
      isVideo ? 'Incoming video call' : 'Incoming voice call',
      callerName,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _incomingCallChannelId,
          'Incoming calls',
          channelDescription: 'Incoming voice and video calls',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
          actions: const [
            AndroidNotificationAction(
              actionDecline,
              'Decline',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              actionAccept,
              'Accept',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: payload,
    );
  }

  Future<void> clearIncomingCallNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_incomingCallNotificationId);
  }

  Future<void> clearAllCallNotifications() async {
    if (!_initialized) return;
    await _plugin.cancel(_incomingCallNotificationId);
    await _plugin.cancel(_callNotificationId);
  }

  Future<void> showOngoingCallNotification({
    required String title,
    required bool isVideo,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      _callNotificationId,
      isVideo ? 'Video call' : 'Voice call',
      title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannelId,
          'Calls',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.call,
        ),
      ),
    );
  }

  Future<void> clearOngoingCallNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_callNotificationId);
  }
}
