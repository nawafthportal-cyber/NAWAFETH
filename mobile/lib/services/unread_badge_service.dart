import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/notification_model.dart';
import 'account_mode_service.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class UnreadBadges {
  final int notifications;
  final int chats;
  final bool degraded;
  final bool stale;

  const UnreadBadges({
    required this.notifications,
    required this.chats,
    this.degraded = false,
    this.stale = false,
  });

  static const empty = UnreadBadges(notifications: 0, chats: 0);

  factory UnreadBadges.fromMap(Map<String, dynamic> data) {
    return UnreadBadges(
      notifications: _readInt(data['notifications']),
      chats: _readInt(data['chats']),
      degraded: data['degraded'] == true,
      stale: data['stale'] == true,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

class UnreadBadgeService {
  static final _UnreadBadgeManager _manager = _UnreadBadgeManager();

  static ValueListenable<UnreadBadges> acquire() => _manager.acquire();

  static void release() => _manager.release();

  static Future<UnreadBadges> refresh({bool force = false}) =>
      _manager.refresh(force: force);

  static Future<UnreadBadges> fetch() => refresh(force: true);

  static Future<void> debugReset() => _manager.resetForTests();

  static bool debugHasActiveTimer() => _manager.hasActiveTimer;

  static int debugSubscriberCount() => _manager.subscriberCount;
}

class _UnreadBadgeManager with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 45);

  final ValueNotifier<UnreadBadges> _badges =
      ValueNotifier<UnreadBadges>(UnreadBadges.empty);
  Timer? _timer;
  Timer? _reconnectTimer;
  WebSocket? _socket;
  Future<UnreadBadges>? _inFlight;
  int _subscriberCount = 0;
  int _reconnectAttempts = 0;
  bool _observerAttached = false;
  bool _isForeground = true;
  bool _realtimeEnabled = true;

  ValueListenable<UnreadBadges> acquire() {
    _subscriberCount += 1;
    _ensureHooks();
    unawaited(_syncPolling(forceRefresh: true));
    return _badges;
  }

  void release() {
    if (_subscriberCount > 0) {
      _subscriberCount -= 1;
    }
    if (_subscriberCount == 0) {
      _stopTimer();
      _detachRealtime();
    }
  }

  Future<UnreadBadges> refresh({bool force = false}) {
    if (_inFlight != null) {
      return _inFlight!;
    }
    _inFlight = _refreshInternal(force: force).whenComplete(() {
      _inFlight = null;
    });
    return _inFlight!;
  }

  int get subscriberCount => _subscriberCount;

  bool get hasActiveTimer => _timer?.isActive ?? false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      unawaited(_syncPolling(forceRefresh: true));
      return;
    }
    _stopTimer();
    _detachRealtime();
  }

  Future<void> resetForTests() async {
    _stopTimer();
    _realtimeEnabled = false;
    _detachRealtime();
    _inFlight = null;
    _subscriberCount = 0;
    _reconnectAttempts = 0;
    _badges.value = UnreadBadges.empty;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
    AuthService.removeLogoutListener(_handleLogout);
    AccountModeService.removeListener(_handleModeChange);
  }

  void _ensureHooks() {
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
      _isForeground = true;
      AuthService.addLogoutListener(_handleLogout);
      AccountModeService.addListener(_handleModeChange);
    }
  }

  Future<void> _syncPolling({bool forceRefresh = false}) async {
    if (_subscriberCount <= 0) {
      _stopTimer();
      _detachRealtime();
      return;
    }
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      _handleLogout();
      return;
    }
    if (!_isForeground) {
      _stopTimer();
      _detachRealtime();
      return;
    }
    _ensureTimer();
    await _ensureRealtimeConnection();
    if (forceRefresh) {
      unawaited(refresh(force: true));
    }
  }

  void _ensureTimer() {
    if (_timer?.isActive ?? false) {
      return;
    }
    _timer = Timer.periodic(_pollInterval, (_) {
      unawaited(refresh());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _detachRealtime() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close(WebSocketStatus.normalClosure, 'inactive'));
    }
  }

  void _handleLogout() {
    _stopTimer();
    _detachRealtime();
    _badges.value = UnreadBadges.empty;
  }

  void _handleModeChange(bool _) {
    if (_subscriberCount <= 0) {
      return;
    }
    unawaited(refresh(force: true));
  }

  Uri? _notificationSocketUri(String token) {
    if (token.isEmpty) {
      return null;
    }
    try {
      final baseUri = Uri.parse(ApiClient.baseUrl);
      return baseUri.resolve('/ws/notifications/').replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
        queryParameters: <String, String>{'token': token},
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureRealtimeConnection() async {
    if (!_realtimeEnabled || _subscriberCount <= 0 || !_isForeground) {
      _detachRealtime();
      return;
    }
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      _handleLogout();
      return;
    }
    if (_socket != null || (_reconnectTimer?.isActive ?? false)) {
      return;
    }
    final token = await AuthService.getAccessToken();
    if (token == null || token.isEmpty) {
      return;
    }
    final uri = _notificationSocketUri(token);
    if (uri == null) {
      return;
    }

    try {
      final socket = await WebSocket.connect(uri.toString());
      if (!_realtimeEnabled || _subscriberCount <= 0 || !_isForeground) {
        await socket.close(WebSocketStatus.normalClosure, 'inactive');
        return;
      }
      _socket = socket;
      _reconnectAttempts = 0;
      socket.listen(
        _handleRealtimePayload,
        onDone: () => _handleRealtimeClosed(socket),
        onError: (_) => _handleRealtimeClosed(socket),
        cancelOnError: true,
      );
      unawaited(refresh(force: true));
    } catch (_) {
      _scheduleRealtimeReconnect();
    }
  }

  void _scheduleRealtimeReconnect() {
    if (!_realtimeEnabled || _subscriberCount <= 0 || !_isForeground) {
      return;
    }
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    final shift = _reconnectAttempts < 5 ? _reconnectAttempts : 5;
    final delay = Duration(seconds: 1 << shift);
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_ensureRealtimeConnection());
    });
  }

  Future<void> _handleRealtimeClosed(WebSocket socket) async {
    if (!identical(_socket, socket)) {
      return;
    }
    _socket = null;
    if (!_realtimeEnabled || _subscriberCount <= 0 || !_isForeground) {
      return;
    }
    if (socket.closeCode == 4401) {
      await refresh(force: true);
    }
    _scheduleRealtimeReconnect();
  }

  void _handleRealtimePayload(dynamic rawPayload) {
    try {
      final decoded = rawPayload is String
          ? Map<String, dynamic>.from(jsonDecode(rawPayload) as Map)
          : Map<String, dynamic>.from(rawPayload as Map);
      final type = (decoded['type'] ?? '').toString();
      if (type == 'notification.created') {
        final notificationPayload = decoded['notification'];
        if (notificationPayload is Map) {
          NotificationService.emitRealtimeNotification(
            NotificationModel.fromJson(
              Map<String, dynamic>.from(notificationPayload),
            ),
          );
        }
      } else if (type == 'notification.deleted') {
        final ids = (decoded['notification_ids'] as List? ?? [])
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .toList();
        if (ids.isNotEmpty) {
          NotificationService.emitRealtimeDeletion(ids);
        }
      } else {
        return;
      }
      unawaited(refresh(force: true));
    } catch (_) {}
  }

  Future<UnreadBadges> _refreshInternal({required bool force}) async {
    if (_subscriberCount <= 0 && !force) {
      return _badges.value;
    }
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      _handleLogout();
      return _badges.value;
    }
    if (!_isForeground && !force) {
      return _badges.value;
    }

    final mode = await AccountModeService.apiMode();
    final response = await ApiClient.get('/api/core/unread-badges/?mode=$mode');
    final data = response.dataAsMap;
    if (data != null &&
        data.containsKey('notifications') &&
        data.containsKey('chats')) {
      final next = UnreadBadges.fromMap(data);
      _badges.value = next;
      return next;
    }
    return _badges.value;
  }
}
