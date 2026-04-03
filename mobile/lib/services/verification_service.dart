import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/upload_optimizer.dart';

class VerificationService {
  /// جلب رسوم التوثيق الحالية للمستخدم حسب باقته الحالية.
  static Future<ApiResponse> fetchMyPricing() {
    return ApiClient.get('/api/verification/pricing/my/');
  }

  /// جلب كتالوج الشارات العامة (AllowAny)
  static Future<ApiResponse> fetchPublicBadgesCatalog() {
    return ApiClient.get('/api/public/badges/');
  }

  /// جلب تفاصيل شارة عامة (blue | green) لشرح معنى الشارة عند النقر
  static Future<ApiResponse> fetchPublicBadgeDetail(String badgeType) {
    final normalized = badgeType.trim().toLowerCase();
    return ApiClient.get('/api/public/badges/$normalized/');
  }

  /// إنشاء طلب توثيق جديد
  static Future<ApiResponse> createRequest({
    String? badgeType,
    List<Map<String, String>>? requirements,
    Map<String, dynamic>? blueProfile,
  }) async {
    final body = <String, dynamic>{};
    if (badgeType != null) body['badge_type'] = badgeType;
    if (requirements != null && requirements.isNotEmpty) {
      body['requirements'] = requirements;
    }
    if (blueProfile != null && blueProfile.isNotEmpty) {
      body['blue_profile'] = blueProfile;
    }
    return ApiClient.post('/api/verification/requests/create/', body: body);
  }

  /// معاينة بيانات الشارة الزرقاء قبل إنشاء الطلب
  static Future<ApiResponse> previewBlue({
    required String subjectType,
    required String officialNumber,
    required String officialDate,
  }) {
    return ApiClient.post(
      '/api/verification/blue-preview/',
      body: {
        'subject_type': subjectType,
        'official_number': officialNumber,
        'official_date': officialDate,
      },
    );
  }

  /// جلب طلبات التوثيق الخاصة بي
  static Future<ApiResponse> fetchMyRequests() {
    return ApiClient.get('/api/verification/requests/my/');
  }

  /// جلب تفاصيل طلب توثيق
  static Future<ApiResponse> fetchRequestDetail(int requestId) {
    return ApiClient.get('/api/verification/requests/$requestId/');
  }

  /// رفع مستند لطلب توثيق (multipart)
  static Future<ApiResponse> uploadDocument({
    required int requestId,
    required File file,
    required String docType,
    String title = '',
  }) async {
    final optimized = await UploadOptimizer.optimizeForUpload(file);
    return ApiClient.sendMultipart(
      'POST',
      '/api/verification/requests/$requestId/documents/',
      (request) async {
        request.fields['doc_type'] = docType;
        if (title.isNotEmpty) request.fields['title'] = title;
        request.files.add(
          await http.MultipartFile.fromPath('file', optimized.path),
        );
      },
    );
  }
}
