import 'dart:async';

import '../models/notification_model.dart';
import 'api_client.dart';

/// خدمة الإشعارات — 10 endpoints
/// Base: /api/notifications/
class NotificationService {
  static const _base = '/api/notifications';
  static final StreamController<NotificationModel> _realtimeController =
      StreamController<NotificationModel>.broadcast();

  static Stream<NotificationModel> get realtimeEvents =>
      _realtimeController.stream;

  static void emitRealtimeNotification(NotificationModel notification) {
    if (_realtimeController.isClosed) {
      return;
    }
    _realtimeController.add(notification);
  }

  static String _withMode(String path, String? mode) {
    if (mode == null || mode.isEmpty) return path;
    return path.contains('?') ? '$path&mode=$mode' : '$path?mode=$mode';
  }

  // ─── 1. قائمة الإشعارات (مع صفحة) ───
  static Future<NotificationsPage> fetchNotifications({
    String? mode, // client | provider
    int limit = 20,
    int offset = 0,
  }) async {
    String url = '$_base/?limit=$limit&offset=$offset';
    if (mode != null) url += '&mode=$mode';

    final res = await ApiClient.get(url);
    if (!res.isSuccess) {
      return NotificationsPage(
          notifications: [], totalCount: 0, hasMore: false);
    }

    final data = res.dataAsMap ?? {};
    final results = (data['results'] as List? ?? [])
        .map((j) => NotificationModel.fromJson(j as Map<String, dynamic>))
        .toList();
    return NotificationsPage(
      notifications: results,
      totalCount: data['count'] as int? ?? 0,
      hasMore: data['next'] != null,
    );
  }

  // ─── 2. عدد غير المقروءة ───
  static Future<int> fetchUnreadCount({String? mode}) async {
    String url = '$_base/unread-count/';
    if (mode != null) url += '?mode=$mode';
    final res = await ApiClient.get(url);
    if (!res.isSuccess) return 0;
    final data = res.dataAsMap ?? {};
    return data['unread'] as int? ?? 0;
  }

  // ─── 3. تمييز كمقروء ───
  static Future<bool> markRead(int notifId, {String? mode}) async {
    try {
      final res =
          await ApiClient.post(_withMode('$_base/mark-read/$notifId/', mode));
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ─── 4. تمييز الكل كمقروء ───
  static Future<bool> markAllRead({String? mode}) async {
    try {
      final res =
          await ApiClient.post(_withMode('$_base/mark-all-read/', mode));
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ─── 5. تبديل التثبيت ───
  static Future<bool> togglePin(int notifId, {String? mode}) async {
    try {
      final res = await ApiClient.post(
          _withMode('$_base/actions/$notifId/', mode),
          body: {'action': 'pin'});
      if (!res.isSuccess) return false;
      final data = res.dataAsMap ?? {};
      return data['is_pinned'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── 6. تبديل المتابعة ───
  static Future<bool> toggleFollowUp(int notifId, {String? mode}) async {
    try {
      final res = await ApiClient.post(
          _withMode('$_base/actions/$notifId/', mode),
          body: {'action': 'follow_up'});
      if (!res.isSuccess) return false;
      final data = res.dataAsMap ?? {};
      return data['is_follow_up'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── 7. حذف إشعار ───
  static Future<bool> deleteNotification(int notifId, {String? mode}) async {
    try {
      final res =
          await ApiClient.delete(_withMode('$_base/actions/$notifId/', mode));
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ─── 8. جلب إعدادات التفضيلات ───
  static Future<List<NotificationPreference>> fetchPreferences(
      {String? mode}) async {
    final res = await ApiClient.get(_withMode('$_base/preferences/', mode));
    if (!res.isSuccess) return [];
    final data = res.dataAsMap ?? {};
    final results = data['results'] as List? ?? [];
    return results
        .map((j) => NotificationPreference.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ─── 9. تحديث إعدادات التفضيلات (batch) ───
  static Future<PreferencesUpdateResult> updatePreferences(
    List<Map<String, dynamic>> updates, {
    String? mode,
  }) async {
    try {
      final res = await ApiClient.patch(_withMode('$_base/preferences/', mode),
          body: {'updates': updates});
      if (!res.isSuccess) {
        return PreferencesUpdateResult(
            success: false, changed: 0, preferences: []);
      }
      final data = res.dataAsMap ?? {};
      final results = (data['results'] as List? ?? [])
          .map(
              (j) => NotificationPreference.fromJson(j as Map<String, dynamic>))
          .toList();
      return PreferencesUpdateResult(
        success: true,
        changed: data['changed'] as int? ?? 0,
        preferences: results,
      );
    } catch (e) {
      return PreferencesUpdateResult(
          success: false, changed: 0, preferences: []);
    }
  }

  // ─── 10. تسجيل توكن FCM ───
  static Future<bool> registerDeviceToken(String token, String platform) async {
    try {
      final res = await ApiClient.post('$_base/device-token/', body: {
        'token': token,
        'platform': platform,
      });
      return res.isSuccess;
    } catch (_) {
      return false;
    }
  }

  // ─── 11. حذف الأقدم ───
  static Future<DeleteOldResult> deleteOld({String? mode}) async {
    try {
      final res = await ApiClient.post(_withMode('$_base/delete-old/', mode));
      if (!res.isSuccess) {
        return DeleteOldResult(success: false, deleted: 0, retentionDays: 90);
      }
      final data = res.dataAsMap ?? {};
      return DeleteOldResult(
        success: true,
        deleted: data['deleted'] as int? ?? 0,
        retentionDays: data['retention_days'] as int? ?? 90,
      );
    } catch (_) {
      return DeleteOldResult(success: false, deleted: 0, retentionDays: 90);
    }
  }
}

// ─── أنواع مساعدة ───

class NotificationsPage {
  final List<NotificationModel> notifications;
  final int totalCount;
  final bool hasMore;

  NotificationsPage({
    required this.notifications,
    required this.totalCount,
    required this.hasMore,
  });
}

class PreferencesUpdateResult {
  final bool success;
  final int changed;
  final List<NotificationPreference> preferences;

  PreferencesUpdateResult({
    required this.success,
    required this.changed,
    required this.preferences,
  });
}

class DeleteOldResult {
  final bool success;
  final int deleted;
  final int retentionDays;

  DeleteOldResult({
    required this.success,
    required this.deleted,
    required this.retentionDays,
  });
}
