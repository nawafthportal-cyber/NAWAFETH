/// خدمة المحتوى العام — /api/content/*
library;

import 'api_client.dart';

class ContentService {
  /// جلب المحتوى العام (blocks, documents, links) — بدون مصادقة
  static Future<ApiResponse> fetchPublicContent() {
    return ApiClient.get('/api/content/public/');
  }
}
