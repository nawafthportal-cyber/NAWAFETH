/// خدمة المميزات — /api/features/*
library;

import 'api_client.dart';

class FeaturesService {
  /// جلب المميزات المتاحة للمستخدم الحالي
  /// verify_* هنا لا تعني أن الاشتراك يمنح التوثيق؛ هي لمسارات مستقلة فقط.
  /// Response: {verify_blue: bool, verify_green: bool, promo_ads: bool,
  ///           priority_support: bool, max_upload_mb: int}
  static Future<ApiResponse> fetchMyFeatures() {
    return ApiClient.get('/api/features/my/');
  }
}
