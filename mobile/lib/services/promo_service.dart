import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/upload_optimizer.dart';

class PromoService {
  /// إنشاء طلب ترويج (إعلان) جديد
  static Future<ApiResponse> createRequest({
    required String title,
    required String adType,
    required String startAt,
    required String endAt,
    String frequency = '60s',
    String position = 'normal',
    String? targetCategory,
    String? targetCity,
    int? targetProvider,
    String? messageTitle,
    String? messageBody,
    String? redirectUrl,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'ad_type': adType,
      'start_at': startAt,
      'end_at': endAt,
      'frequency': frequency,
      'position': position,
    };
    if (targetCategory != null && targetCategory.isNotEmpty) {
      body['target_category'] = targetCategory;
    }
    if (targetCity != null && targetCity.isNotEmpty) {
      body['target_city'] = targetCity;
    }
    if (targetProvider != null) {
      body['target_provider'] = targetProvider;
    }
    if (messageTitle != null && messageTitle.isNotEmpty) {
      body['message_title'] = messageTitle;
    }
    if (messageBody != null && messageBody.isNotEmpty) {
      body['message_body'] = messageBody;
    }
    if (redirectUrl != null && redirectUrl.isNotEmpty) {
      body['redirect_url'] = redirectUrl;
    }
    return ApiClient.post('/api/promo/requests/create/', body: body);
  }

  /// جلب طلبات الترويج الخاصة بي
  static Future<ApiResponse> fetchMyRequests() {
    return ApiClient.get('/api/promo/requests/my/');
  }

  /// جلب تفاصيل طلب ترويج
  static Future<ApiResponse> fetchRequestDetail(int requestId) {
    return ApiClient.get('/api/promo/requests/$requestId/');
  }

  /// رفع ملف (صورة/فيديو) لطلب ترويج (multipart)
  static Future<ApiResponse> uploadAsset({
    required int requestId,
    required File file,
    required String assetType,
    String title = '',
  }) async {
    final optimized = await UploadOptimizer.optimizeForUpload(
      file,
      declaredType: assetType,
    );
    return ApiClient.sendMultipart(
      'POST',
      '/api/promo/requests/$requestId/assets/',
      (request) async {
        request.fields['asset_type'] = assetType;
        if (title.isNotEmpty) request.fields['title'] = title;
        request.files.add(
          await http.MultipartFile.fromPath('file', optimized.path),
        );
      },
    );
  }
}
