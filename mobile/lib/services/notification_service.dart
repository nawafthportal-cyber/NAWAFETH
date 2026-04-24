import 'dart:async';

import '../models/notification_model.dart';
import 'api_client.dart';
import 'local_cache_service.dart';

/// خدمة الإشعارات — 10 endpoints
/// Base: /api/notifications/
class NotificationService {
  static const _base = '/api/notifications';
  static const Duration _cacheTtl = Duration(minutes: 10);
  static final StreamController<NotificationRealtimeEvent> _realtimeController =
      StreamController<NotificationRealtimeEvent>.broadcast();
  static final Map<String, _NotificationsCacheEntry> _memoryCache =
      <String, _NotificationsCacheEntry>{};

  static Stream<NotificationRealtimeEvent> get realtimeEvents =>
      _realtimeController.stream;

  static void emitRealtimeNotification(NotificationModel notification) {
    if (_realtimeController.isClosed) {
      return;
    }
    _realtimeController.add(
      NotificationCreatedRealtimeEvent(notification),
    );
  }

  static void emitRealtimeDeletion(List<int> notificationIds) {
    if (_realtimeController.isClosed || notificationIds.isEmpty) {
      return;
    }
    _realtimeController.add(
      NotificationDeletedRealtimeEvent(List<int>.from(notificationIds)),
    );
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
    final result = await fetchNotificationsResult(
      mode: mode,
      limit: limit,
      offset: offset,
    );
    return result.page;
  }

  static Future<CachedNotificationsPageResult> fetchNotificationsResult({
    String? mode,
    int limit = 20,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final cacheScope = _cacheScope(mode);
    final cacheKey = 'notifications_list_cache_$cacheScope';
    final shouldUseCache = offset == 0;
    final memoryCache = shouldUseCache ? _memoryCache[cacheScope] : null;
    if (!forceRefresh &&
        shouldUseCache &&
        memoryCache != null &&
        memoryCache.isFresh(_cacheTtl)) {
      return memoryCache.toResult(source: 'memory_cache');
    }

    final diskCache = !forceRefresh && shouldUseCache
        ? await _readDiskCache(cacheKey)
        : null;
    if (diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _memoryCache[cacheScope] = _NotificationsCacheEntry(
        diskCache.page,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(source: 'disk_cache');
    }

    final res = await ApiClient.get(_listPath(mode: mode, limit: limit, offset: offset));
    if (res.isSuccess) {
      final page = _parseNotificationsPage(res);
      final result = CachedNotificationsPageResult(
        page: page,
        source: 'network',
      );
      if (shouldUseCache) {
        _memoryCache[cacheScope] = _NotificationsCacheEntry(page, DateTime.now());
        await _writeDiskCache(cacheKey, page);
      }
      return result;
    }

    final errorMessage = res.error ?? 'تعذر تحميل الإشعارات الآن';
    if (memoryCache != null) {
      return memoryCache.toResult(
        source: 'memory_cache_stale',
        errorMessage: errorMessage,
        statusCode: res.statusCode,
      );
    }
    if (diskCache != null) {
      _memoryCache[cacheScope] = _NotificationsCacheEntry(
        diskCache.page,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: errorMessage,
        statusCode: res.statusCode,
      );
    }
    return CachedNotificationsPageResult(
      page: NotificationsPage(
        notifications: const <NotificationModel>[],
        totalCount: 0,
        hasMore: false,
      ),
      source: 'empty',
      errorMessage: errorMessage,
      statusCode: res.statusCode,
    );
  }

  // ─── 2. عدد غير المقروءة ───
  static Future<int> fetchUnreadCount({String? mode}) async {
    final normalizedMode = (mode ?? '').trim();
    String url = '/api/core/unread-badges/';
    if (normalizedMode.isNotEmpty) {
      url += '?mode=$normalizedMode';
    }
    final res = await ApiClient.get(url);
    if (!res.isSuccess) return 0;
    final data = res.dataAsMap ?? {};
    return data['notifications'] as int? ?? 0;
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
  static Future<NotificationPreferencesPayload> fetchPreferences(
      {String? mode}) async {
    final res = await ApiClient.get(_withMode('$_base/preferences/', mode));
    if (!res.isSuccess) {
      return NotificationPreferencesPayload(preferences: [], sections: []);
    }
    final data = res.dataAsMap ?? {};
    final results = data['results'] as List? ?? [];
    final sections = data['sections'] as List? ?? [];
    return NotificationPreferencesPayload(
      preferences: results
          .map((j) => NotificationPreference.fromJson(j as Map<String, dynamic>))
          .toList(),
      sections: sections
          .map((j) => NotificationPreferenceSection.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
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
            success: false, changed: 0, preferences: [], sections: []);
      }
      final data = res.dataAsMap ?? {};
      final results = (data['results'] as List? ?? [])
          .map(
              (j) => NotificationPreference.fromJson(j as Map<String, dynamic>))
          .toList();
      final sections = (data['sections'] as List? ?? [])
          .map(
              (j) => NotificationPreferenceSection.fromJson(j as Map<String, dynamic>))
          .toList();
      return PreferencesUpdateResult(
        success: true,
        changed: data['changed'] as int? ?? 0,
        preferences: results,
        sections: sections,
      );
    } catch (e) {
      return PreferencesUpdateResult(
          success: false, changed: 0, preferences: [], sections: []);
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

  // ─── 12. معاينة إشعار دعائي ───
  static Future<Map<String, dynamic>?> fetchPromoPreview(int notifId) async {
    try {
      final res = await ApiClient.get('$_base/promo-preview/$notifId/');
      if (!res.isSuccess) return null;
      return res.dataAsMap;
    } catch (_) {
      return null;
    }
  }

  static void debugResetCaches() {
    _memoryCache.clear();
  }

  static String _cacheScope(String? mode) {
    final normalized = (mode ?? '').trim().toLowerCase();
    return normalized.isEmpty ? 'shared' : normalized;
  }

  static String _listPath({String? mode, required int limit, required int offset}) {
    String url = '$_base/?limit=$limit&offset=$offset';
    if (mode != null && mode.trim().isNotEmpty) {
      url += '&mode=${mode.trim()}';
    }
    return url;
  }

  static NotificationsPage _parseNotificationsPage(ApiResponse response) {
    final data = response.dataAsMap ?? {};
    final results = (data['results'] as List? ?? [])
        .map((j) => NotificationModel.fromJson(j as Map<String, dynamic>))
        .toList(growable: false);
    return NotificationsPage(
      notifications: results,
      totalCount: data['count'] as int? ?? results.length,
      hasMore: data['next'] != null,
    );
  }

  static Future<void> _writeDiskCache(
    String cacheKey,
    NotificationsPage page,
  ) {
    final payload = {
      'count': page.totalCount,
      'has_more': page.hasMore,
      'results': page.notifications
          .take(30)
          .map(_serializeNotificationForCache)
          .toList(growable: false),
    };
    return LocalCacheService.writeJson(cacheKey, payload);
  }

  static Future<CachedNotificationsPageResult?> _readDiskCache(
    String cacheKey,
  ) async {
    final envelope = await LocalCacheService.readJson(cacheKey);
    final payload = envelope?.payload;
    if (payload is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(payload);
    final rows = (map['results'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((row) => NotificationModel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return CachedNotificationsPageResult(
      page: NotificationsPage(
        notifications: rows,
        totalCount: map['count'] as int? ?? rows.length,
        hasMore: map['has_more'] == true,
      ),
      source: 'disk_cache',
      cachedAt: envelope?.cachedAt,
    );
  }

  static Map<String, dynamic> _serializeNotificationForCache(
    NotificationModel notification,
  ) {
    final title = notification.title.trim();
    final body = notification.body.trim();
    return {
      'id': notification.id,
      'title': title.length > 120 ? '${title.substring(0, 120)}…' : title,
      'body': body.length > 160 ? '${body.substring(0, 160)}…' : body,
      'kind': notification.kind,
      'url': notification.url,
      'audience_mode': notification.audienceMode,
      'is_read': notification.isRead,
      'is_pinned': notification.isPinned,
      'is_follow_up': notification.isFollowUp,
      'is_urgent': notification.isUrgent,
      'created_at': notification.createdAt.toIso8601String(),
    };
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

class CachedNotificationsPageResult {
  final NotificationsPage page;
  final String source;
  final String? errorMessage;
  final int statusCode;
  final DateTime? cachedAt;

  const CachedNotificationsPageResult({
    required this.page,
    required this.source,
    this.errorMessage,
    this.statusCode = 200,
    this.cachedAt,
  });

  bool get fromCache => source.contains('cache');
  bool get isStaleCache => source.endsWith('_stale');
  bool get isOfflineFallback => isStaleCache && statusCode == 0;
  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;

  bool isFresh(Duration ttl) {
    final value = cachedAt;
    if (value == null) {
      return false;
    }
    return DateTime.now().difference(value) <= ttl;
  }

  CachedNotificationsPageResult copyWith({
    NotificationsPage? page,
    String? source,
    String? errorMessage,
    int? statusCode,
  }) {
    return CachedNotificationsPageResult(
      page: page ?? this.page,
      source: source ?? this.source,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
      cachedAt: cachedAt,
    );
  }
}

class _NotificationsCacheEntry {
  final NotificationsPage page;
  final DateTime fetchedAt;

  const _NotificationsCacheEntry(this.page, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }

  CachedNotificationsPageResult toResult({
    required String source,
    String? errorMessage,
    int statusCode = 200,
  }) {
    return CachedNotificationsPageResult(
      page: NotificationsPage(
        notifications: List<NotificationModel>.from(page.notifications),
        totalCount: page.totalCount,
        hasMore: page.hasMore,
      ),
      source: source,
      errorMessage: errorMessage,
      statusCode: statusCode,
      cachedAt: fetchedAt,
    );
  }
}

class PreferencesUpdateResult {
  final bool success;
  final int changed;
  final List<NotificationPreference> preferences;
  final List<NotificationPreferenceSection> sections;

  PreferencesUpdateResult({
    required this.success,
    required this.changed,
    required this.preferences,
    required this.sections,
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

abstract class NotificationRealtimeEvent {
  const NotificationRealtimeEvent();
}

class NotificationCreatedRealtimeEvent extends NotificationRealtimeEvent {
  final NotificationModel notification;

  const NotificationCreatedRealtimeEvent(this.notification);
}

class NotificationDeletedRealtimeEvent extends NotificationRealtimeEvent {
  final List<int> notificationIds;

  const NotificationDeletedRealtimeEvent(this.notificationIds);
}
