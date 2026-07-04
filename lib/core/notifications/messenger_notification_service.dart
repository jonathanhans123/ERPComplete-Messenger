import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MessengerNotificationService {
  MessengerNotificationService._();
  static final instance = MessengerNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _channelId = 'messenger_messages';
  static const _callChannelId = 'messenger_calls';
  static const _callNotificationId = 9001;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
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
      await androidPlugin?.requestNotificationsPermission();
    }
    _initialized = true;
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
