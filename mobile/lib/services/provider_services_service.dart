/// خدمة المزود — /api/providers/me/services/* + categories
library;

import 'api_client.dart';

class ProviderServicesService {
  /// جلب خدمات المزود
  static Future<ApiResponse> fetchMyServices() async {
    return ApiClient.get('/api/providers/me/services/');
  }

  /// إنشاء خدمة جديدة
  static Future<ApiResponse> createService(Map<String, dynamic> data) async {
    return ApiClient.post('/api/providers/me/services/', body: data);
  }

  /// تحديث خدمة
  static Future<ApiResponse> updateService(int serviceId, Map<String, dynamic> data) async {
    return ApiClient.patch('/api/providers/me/services/$serviceId/', body: data);
  }

  /// حذف خدمة
  static Future<ApiResponse> deleteService(int serviceId) async {
    return ApiClient.delete('/api/providers/me/services/$serviceId/');
  }

  /// جلب التصنيفات (مع التصنيفات الفرعية)
  static Future<ApiResponse> fetchCategories() async {
    return ApiClient.get('/api/providers/categories/');
  }

  /// جلب التصنيفات الفرعية المرتبطة بالمزود الحالي
  static Future<ApiResponse> fetchMySubcategories() async {
    return ApiClient.get('/api/providers/me/subcategories/');
  }
}
