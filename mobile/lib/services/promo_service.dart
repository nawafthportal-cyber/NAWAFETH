import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nawafeth/services/api_client.dart';
import 'package:nawafeth/services/upload_optimizer.dart';

class PromoService {
  /// إنشاء طلب ترويج جديد.
  ///
  /// يدعم المسار الجديد متعدد البنود عبر [items]،
  /// ويحتفظ بالتوافق مع الطلب الأحادي القديم عند عدم تمرير البنود.
  static Future<ApiResponse> createRequest({
    String? title,
    String? adType,
    String? startAt,
    String? endAt,
    String frequency = '60s',
    String position = 'normal',
    String? targetCategory,
    String? targetCity,
    int? targetProvider,
    String? messageTitle,
    String? messageBody,
    String? redirectUrl,
    int? mobileScale,
    int? tabletScale,
    int? desktopScale,
    List<Map<String, dynamic>>? items,
  }) async {
    final body = <String, dynamic>{};
    if (items != null && items.isNotEmpty) {
      body['items'] = items;
      if (mobileScale != null) {
        body['mobile_scale'] = mobileScale;
      }
      if (tabletScale != null) {
        body['tablet_scale'] = tabletScale;
      }
      if (desktopScale != null) {
        body['desktop_scale'] = desktopScale;
      }
      return ApiClient.post('/api/promo/requests/create/', body: body);
    }
    final normalizedTitle = (title ?? '').trim();
    if (normalizedTitle.isNotEmpty) {
      body['title'] = normalizedTitle;
    }
    body.addAll({
      'ad_type': adType,
      'start_at': startAt,
      'end_at': endAt,
      'frequency': frequency,
      'position': position,
    });
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
    if (mobileScale != null) {
      body['mobile_scale'] = mobileScale;
    }
    if (tabletScale != null) {
      body['tablet_scale'] = tabletScale;
    }
    if (desktopScale != null) {
      body['desktop_scale'] = desktopScale;
    }
    return ApiClient.post('/api/promo/requests/create/', body: body);
  }

  static Future<ApiResponse> createBundleRequest({
    required List<Map<String, dynamic>> items,
    int? mobileScale,
    int? tabletScale,
    int? desktopScale,
  }) {
    return createRequest(
      items: items,
      mobileScale: mobileScale,
      tabletScale: tabletScale,
      desktopScale: desktopScale,
    );
  }

  static Future<ApiResponse> previewRequest({
    String? title,
    List<Map<String, dynamic>>? items,
    String? adType,
    String? startAt,
    String? endAt,
    String frequency = '60s',
    String position = 'normal',
    String? targetCategory,
    String? targetCity,
    int? targetProvider,
    String? messageTitle,
    String? messageBody,
    String? redirectUrl,
    int? mobileScale,
    int? tabletScale,
    int? desktopScale,
  }) async {
    final body = <String, dynamic>{};
    if (items != null && items.isNotEmpty) {
      body['items'] = items;
      if (mobileScale != null) {
        body['mobile_scale'] = mobileScale;
      }
      if (tabletScale != null) {
        body['tablet_scale'] = tabletScale;
      }
      if (desktopScale != null) {
        body['desktop_scale'] = desktopScale;
      }
      return ApiClient.post('/api/promo/requests/preview/', body: body);
    }
    final normalizedTitle = (title ?? '').trim();
    if (normalizedTitle.isNotEmpty) {
      body['title'] = normalizedTitle;
    }
    body.addAll({
      'ad_type': adType,
      'start_at': startAt,
      'end_at': endAt,
      'frequency': frequency,
      'position': position,
    });
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
    if (mobileScale != null) {
      body['mobile_scale'] = mobileScale;
    }
    if (tabletScale != null) {
      body['tablet_scale'] = tabletScale;
    }
    if (desktopScale != null) {
      body['desktop_scale'] = desktopScale;
    }
    return ApiClient.post('/api/promo/requests/preview/', body: body);
  }

  static Future<ApiResponse> previewBundleRequest({
    required List<Map<String, dynamic>> items,
    int? mobileScale,
    int? tabletScale,
    int? desktopScale,
  }) {
    return previewRequest(
      items: items,
      mobileScale: mobileScale,
      tabletScale: tabletScale,
      desktopScale: desktopScale,
    );
  }

  /// دليل الأسعار الفعلي من قواعد لوحة إدارة الترويج.
  static Future<ApiResponse> fetchPricingGuide() {
    return ApiClient.get('/api/promo/pricing/guide/');
  }

  /// جلب طلبات الترويج الخاصة بي
  static Future<ApiResponse> fetchMyRequests() {
    return ApiClient.get('/api/promo/requests/my/');
  }

  /// جلب تفاصيل طلب ترويج
  static Future<ApiResponse> fetchRequestDetail(int requestId) {
    return ApiClient.get('/api/promo/requests/$requestId/');
  }

  /// تجهيز فاتورة الدفع لطلب الترويج (للمالك)
  static Future<ApiResponse> preparePayment({
    required int requestId,
    String quoteNote = '',
  }) {
    final body = <String, dynamic>{};
    if (quoteNote.trim().isNotEmpty) {
      body['quote_note'] = quoteNote.trim();
    }
    return ApiClient.post(
      '/api/promo/requests/$requestId/prepare-payment/',
      body: body,
    );
  }

  /// رفع ملف (صورة/فيديو) لطلب ترويج (multipart)
  static Future<ApiResponse> uploadAsset({
    required int requestId,
    required File file,
    required String assetType,
    String title = '',
    int? itemId,
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
        if (itemId != null) request.fields['item_id'] = itemId.toString();
        request.files.add(
          await http.MultipartFile.fromPath('file', optimized.path),
        );
      },
    );
  }
}
