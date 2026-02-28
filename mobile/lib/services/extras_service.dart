/// خدمة الخدمات الإضافية — /api/extras/*
library;

import 'api_client.dart';

class ExtrasService {
  /// جلب كتالوج الخدمات الإضافية
  static Future<ApiResponse> fetchCatalog() {
    return ApiClient.get('/api/extras/catalog/');
  }

  /// جلب مشترياتي من الخدمات الإضافية
  static Future<ApiResponse> fetchMyExtras() {
    return ApiClient.get('/api/extras/my/');
  }

  /// شراء خدمة إضافية
  static Future<ApiResponse> buy(String sku) {
    return ApiClient.post('/api/extras/buy/$sku/');
  }
}
