import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

const String _messagesChannelId = 'nawafeth_messages';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _lastRegisteredToken;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('⚠️ Firebase.initializeApp failed: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('🔔 Push permission: ${settings.authorizationStatus}');

    await _initLocalNotifications();

    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (e) {
      debugPrint('⚠️ Unable to fetch FCM token: $e');
    }

    messaging.onTokenRefresh.listen((token) async {
      await _registerToken(token);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _showForegroundNotification(message);
    });

    _initialized = true;
  }

  static Future<void> tryRegisterCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (_) {}
  }

  static Future<void> _registerToken(String token) async {
    if (token.isEmpty || token == _lastRegisteredToken) return;
    final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    final ok = await NotificationService.registerDeviceToken(token, platform);
    if (ok) {
      _lastRegisteredToken = token;
    }
  }

  static Future<void> _initLocalNotifications() async {
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
      await androidPlugin.requestNotificationsPermission();
    }
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'رسالة جديدة';
    final body = message.notification?.body ?? 'لديك إشعار جديد';

    const android = AndroidNotificationDetails(
      _messagesChannelId,
      'رسائل نوافذ',
      channelDescription: 'تنبيهات الرسائل الجديدة',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    await _local.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }
}
