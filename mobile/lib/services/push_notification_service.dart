import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String _messagesChannelId = 'nawafeth_messages';

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _localReady = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('🔕 Firebase push is disabled (no Google services configured).');

    _initialized = true;
  }

  static Future<void> tryRegisterCurrentToken() async {
    debugPrint('🔕 Skipping device token registration: Firebase push is disabled.');
  }

  static Future<void> requestNotificationsPermission() async {
    await _ensureLocalNotificationsReady();
    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  static Future<void> _ensureLocalNotificationsReady() async {
    if (_localReady) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _local.initialize(initSettings);

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        _messagesChannelId,
        'رسائل نوافذ',
        description: 'تنبيهات الرسائل الجديدة',
        importance: Importance.max,
        playSound: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    _localReady = true;
  }
}
