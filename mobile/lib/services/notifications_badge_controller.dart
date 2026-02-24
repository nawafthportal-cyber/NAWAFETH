import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'notifications_api.dart';
import 'role_controller.dart';

class NotificationsBadgeController with WidgetsBindingObserver {
  NotificationsBadgeController._();

  static final NotificationsBadgeController instance = NotificationsBadgeController._();

  final ValueNotifier<int?> unreadNotifier = ValueNotifier<int?>(null);

  final NotificationsApi _api = NotificationsApi();

  bool _initialized = false;
  bool _active = true;
  bool _refreshing = false;
  Timer? _timer;

  /// Polling interval while app is in foreground.
  static const Duration _interval = Duration(seconds: 30);

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    _active = true;
    RoleController.instance.notifier.addListener(_onRoleChanged);
    _startTimer();
    refresh();
  }

  void _onRoleChanged() {
    // Role switched (client/provider). Refresh unread count for the active account.
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _startTimer();
      refresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _active = false;
      _stopTimer();
    }
  }

  Future<void> refresh() async {
    if (!_active || _refreshing) return;
    _refreshing = true;

    try {
      final count = await _api.getUnreadCount();
      unreadNotifier.value = count;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // Not authenticated or not allowed: do not keep hammering the endpoint.
        unreadNotifier.value = null;
        _stopTimer();
      }
      // For offline/timeout/etc: keep last known value.
    } catch (_) {
      // Keep last known value on unknown errors.
    } finally {
      _refreshing = false;
    }
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) {
      refresh();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  void resetForTests() {
    _stopTimer();
    unreadNotifier.value = null;
    _active = true;
    _refreshing = false;
    _initialized = false;
  }
}
