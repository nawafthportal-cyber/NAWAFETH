/// خدمة المحتوى العام — /api/content/*
library;

import 'api_client.dart';
import 'local_cache_service.dart';

class ContentService {
  // ─── In-memory cache (TTL = 5 دقائق) ───
  static ApiResponse? _cachedResponse;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 5);
  static const _diskCacheKey = 'public_content_cache_v1';

  /// جلب المحتوى العام (blocks, documents, links) — بدون مصادقة
  /// يستخدم cache في الذاكرة وعلى الجهاز لتقليل زمن الإقلاع ودعم offline.
  static Future<ApiResponse> fetchPublicContent(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedResponse != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedResponse!;
    }

    if (!forceRefresh) {
      final diskCache = LocalCacheService.readJsonSync(_diskCacheKey);
      final cachedMap = _asCacheablePayload(diskCache?.payload);
      if (diskCache != null &&
          cachedMap != null &&
          diskCache.isFresh(_cacheTtl)) {
        return _setMemoryCache(ApiResponse(statusCode: 200, data: cachedMap),
            diskCache.cachedAt.toLocal());
      }
    }

    final response = await ApiClient.get('/api/content/public/');

    if (response.isSuccess && response.data != null) {
      final payload = _asCacheablePayload(response.data);
      if (payload != null) {
        await LocalCacheService.writeJson(_diskCacheKey, payload);
        return _setMemoryCache(
          ApiResponse(statusCode: response.statusCode, data: payload),
          DateTime.now(),
        );
      }
    }

    final fallback = LocalCacheService.readJsonSync(_diskCacheKey);
    final fallbackPayload = _asCacheablePayload(fallback?.payload);
    if (fallbackPayload != null) {
      return _setMemoryCache(
        ApiResponse(statusCode: 200, data: fallbackPayload),
        fallback?.cachedAt.toLocal() ?? DateTime.now(),
      );
    }

    return response;
  }

  /// مسح الـ cache يدوياً (مثلاً بعد تحديث المحتوى)
  static Future<void> clearCache() async {
    _cachedResponse = null;
    _cachedAt = null;
    await LocalCacheService.remove(_diskCacheKey);
  }

  static ApiResponse _setMemoryCache(ApiResponse response, DateTime cachedAt) {
    _cachedResponse = response;
    _cachedAt = cachedAt;
    return response;
  }

  static dynamic _asCacheablePayload(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List) {
      return List<dynamic>.from(data);
    }
    return null;
  }
}
