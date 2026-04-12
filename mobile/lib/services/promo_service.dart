import 'dart:async';
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
    final directResponse = await _uploadAssetDirect(
      requestId: requestId,
      file: optimized,
      assetType: assetType,
      title: title,
      itemId: itemId,
    );
    if (directResponse != null) {
      return directResponse;
    }
    if (assetType.trim().toLowerCase() == 'video') {
      return ApiResponse(
        statusCode: 400,
        error:
            'رفع الفيديو عبر الخادم غير مسموح. يرجى إعادة المحاولة باستخدام الرفع المباشر.',
      );
    }
    return _uploadAssetMultipartLegacy(
      requestId: requestId,
      file: optimized,
      assetType: assetType,
      title: title,
      itemId: itemId,
    );
  }

  static Future<ApiResponse?> _uploadAssetDirect({
    required int requestId,
    required File file,
    required String assetType,
    required String title,
    int? itemId,
  }) async {
    final fileName = _basename(file.path);
    final fileSize = await file.length();
    final contentType = _guessContentType(fileName, assetType);
    final initBody = <String, dynamic>{
      'asset_type': assetType,
      'file_name': fileName,
      'file_size': fileSize,
      'content_type': contentType,
    };
    if (itemId != null) {
      initBody['item_id'] = itemId.toString();
    }
    if (title.trim().isNotEmpty) {
      initBody['title'] = title.trim();
    }

    final initRes = await ApiClient.post(
      '/api/promo/requests/$requestId/assets/init-upload/',
      body: initBody,
    );
    if (!initRes.isSuccess) {
      final initDetail =
          (initRes.dataAsMap?['detail'] as String?)?.trim() ?? '';
      if (initRes.statusCode == 404 || initRes.statusCode == 405) {
        return null;
      }
      if (initRes.statusCode == 400 && initDetail.contains('غير متاح')) {
        return null;
      }
      return initRes;
    }

    final upload =
        (initRes.dataAsMap?['upload'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final uploadUrl = (upload['url'] as String?)?.trim() ?? '';
    final objectKey =
        ((upload['object_key'] ?? upload['key']) as String?)?.trim() ?? '';
    if (uploadUrl.isEmpty || objectKey.isEmpty) {
      return ApiResponse(
        statusCode: 0,
        error: 'استجابة الرفع المباشر غير مكتملة.',
      );
    }

    final uploadHeaders = <String, String>{};
    final rawHeaders = upload['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key != null && value != null) {
          uploadHeaders[key.toString()] = value.toString();
        }
      });
    }
    if (!uploadHeaders.keys
        .any((k) => k.toLowerCase() == 'content-type')) {
      uploadHeaders['Content-Type'] = contentType;
    }
    final method = ((upload['method'] as String?) ?? 'PUT').toUpperCase();

    final uploadUri = Uri.tryParse(uploadUrl);
    if (uploadUri == null) {
      return ApiResponse(
        statusCode: 0,
        error: 'رابط الرفع المباشر غير صالح.',
      );
    }

    try {
      final bytes = await file.readAsBytes();
      final response = await (method == 'PUT'
              ? http.put(uploadUri, headers: uploadHeaders, body: bytes)
              : http.post(uploadUri, headers: uploadHeaders, body: bytes))
          .timeout(const Duration(seconds: 120));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiResponse(
          statusCode: response.statusCode,
          error: 'فشل رفع الملف مباشرة إلى التخزين.',
        );
      }
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }

    final completeBody = <String, dynamic>{
      'asset_type': assetType,
      'object_key': objectKey,
      'content_type': contentType,
    };
    if (itemId != null) {
      completeBody['item_id'] = itemId.toString();
    }
    if (title.trim().isNotEmpty) {
      completeBody['title'] = title.trim();
    }
    return ApiClient.post(
      '/api/promo/requests/$requestId/assets/complete-upload/',
      body: completeBody,
    );
  }

  static Future<ApiResponse> _uploadAssetMultipartLegacy({
    required int requestId,
    required File file,
    required String assetType,
    required String title,
    int? itemId,
  }) {
    return ApiClient.sendMultipart(
      'POST',
      '/api/promo/requests/$requestId/assets/',
      (request) async {
        request.fields['asset_type'] = assetType;
        if (title.isNotEmpty) request.fields['title'] = title;
        if (itemId != null) request.fields['item_id'] = itemId.toString();
        request.files.add(
          await http.MultipartFile.fromPath('file', file.path),
        );
      },
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.isEmpty) return path;
    return parts.last.trim().isEmpty ? path : parts.last;
  }

  static String _guessContentType(String fileName, String assetType) {
    final ext = fileName.toLowerCase().split('.').length > 1
        ? '.${fileName.toLowerCase().split('.').last}'
        : '';
    if (ext == '.jpg' || ext == '.jpeg') return 'image/jpeg';
    if (ext == '.png') return 'image/png';
    if (ext == '.gif') return 'image/gif';
    if (ext == '.mp4') return 'video/mp4';
    if (ext == '.pdf') return 'application/pdf';
    if (assetType.toLowerCase() == 'video') return 'video/mp4';
    if (assetType.toLowerCase() == 'image') return 'image/jpeg';
    return 'application/octet-stream';
  }
}
