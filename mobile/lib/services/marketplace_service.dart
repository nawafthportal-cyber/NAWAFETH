/// خدمة الطلبات (Marketplace) — تتعامل مع /api/marketplace/*
///
/// تشمل:
/// - إنشاء طلب خدمة (عادي / تنافسي / عاجل)
/// - قوائم طلبات العميل والمزوّد
/// - تفاصيل الطلب
/// - قبول / رفض / بدء / إكمال / تحديث التقدم
/// - العروض (للتنافسي)
/// - الطلبات العاجلة المتاحة
library;

import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'upload_optimizer.dart';
import '../models/service_request_model.dart';

class MarketplaceService {
  // ──────────────────────────────────────
  // جلب الأقسام والتصنيفات الفرعية
  // ──────────────────────────────────────
  /// [{id, name, subcategories: [{id, name}]}]
  static Future<List<Map<String, dynamic>>> getCategories() async {
    final res = await ApiClient.get('/api/providers/categories/');
    if (!res.isSuccess) return [];
    final list = res.dataAsList;
    if (list == null) return [];
    return list.cast<Map<String, dynamic>>();
  }

  // ──────────────────────────────────────
  // إنشاء طلب (multipart — يدعم المرفقات)
  // ──────────────────────────────────────
  static Future<ApiResponse> createRequest({
    required String title,
    required String description,
    required String requestType,
    required int subcategory,
    String? city,
    int? provider,
    String? dispatchMode,
    String? quoteDeadline,
    List<File> images = const [],
    List<File> videos = const [],
    List<File> files = const [],
    File? audio,
  }) async {
    // تحسين الصور والملفات قبل الرفع
    final optimizedImages = <File>[];
    for (final img in images) {
      optimizedImages.add(
        await UploadOptimizer.optimizeForUpload(img, declaredType: 'image'),
      );
    }
    final optimizedFiles = <File>[];
    for (final f in files) {
      optimizedFiles.add(await UploadOptimizer.optimizeForUpload(f));
    }

    return ApiClient.sendMultipart(
      'POST',
      '/api/marketplace/requests/create/',
      (request) async {
        request.fields['title'] = title;
        request.fields['description'] = description;
        request.fields['request_type'] = requestType;
        request.fields['subcategory'] = subcategory.toString();

        if (city != null && city.isNotEmpty) {
          request.fields['city'] = city;
        }
        if (provider != null) {
          request.fields['provider'] = provider.toString();
        }
        if (dispatchMode != null) {
          request.fields['dispatch_mode'] = dispatchMode;
        }
        if (quoteDeadline != null) {
          request.fields['quote_deadline'] = quoteDeadline;
        }

        for (final img in optimizedImages) {
          request.files.add(
            await http.MultipartFile.fromPath('images', img.path),
          );
        }
        for (final vid in videos) {
          request.files.add(
            await http.MultipartFile.fromPath('videos', vid.path),
          );
        }
        for (final f in optimizedFiles) {
          request.files.add(
            await http.MultipartFile.fromPath('files', f.path),
          );
        }
        if (audio != null) {
          request.files.add(
            await http.MultipartFile.fromPath('audio', audio.path),
          );
        }
      },
      timeout: const Duration(seconds: 60),
    );
  }

  // ──────────────────────────────────────
  // قوائم طلبات العميل
  // ──────────────────────────────────────
  static Future<List<ServiceRequest>> getClientRequests({
    String? statusGroup,
    String? type,
    String? query,
  }) async {
    final params = <String>[];
    if (statusGroup != null) params.add('status_group=$statusGroup');
    if (type != null) params.add('type=$type');
    if (query != null && query.isNotEmpty) params.add('q=$query');

    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final res = await ApiClient.get('/api/marketplace/client/requests/$qs');
    if (!res.isSuccess) return [];

    final list = res.dataAsList;
    if (list == null) return [];
    return list
        .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// تفاصيل طلب العميل (مع المرفقات وسجل الحالة)
  static Future<ServiceRequest?> getClientRequestDetail(int requestId) async {
    final res = await ApiClient.get(
        '/api/marketplace/client/requests/$requestId/');
    if (!res.isSuccess) return null;
    final map = res.dataAsMap;
    if (map == null) return null;
    return ServiceRequest.fromJson(map);
  }

  /// تعديل عنوان/تفاصيل الطلب (فقط عندما status=new)
  static Future<ApiResponse> updateClientRequest(
    int requestId, {
    String? title,
    String? description,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    return ApiClient.patch(
      '/api/marketplace/client/requests/$requestId/',
      body: body,
    );
  }

  // ──────────────────────────────────────
  // قوائم طلبات المزوّد
  // ──────────────────────────────────────
  static Future<List<ServiceRequest>> getProviderRequests({
    String? statusGroup,
    int? clientUserId,
  }) async {
    final params = <String>[];
    if (statusGroup != null) params.add('status_group=$statusGroup');
    if (clientUserId != null) params.add('client_user_id=$clientUserId');

    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final res = await ApiClient.get('/api/marketplace/provider/requests/$qs');
    if (!res.isSuccess) return [];

    final list = res.dataAsList;
    if (list == null) return [];
    return list
        .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// تفاصيل طلب المزوّد
  static Future<ServiceRequest?> getProviderRequestDetail(
      int requestId) async {
    final res = await ApiClient.get(
        '/api/marketplace/provider/requests/$requestId/detail/');
    if (!res.isSuccess) return null;
    final map = res.dataAsMap;
    if (map == null) return null;
    return ServiceRequest.fromJson(map);
  }

  // ──────────────────────────────────────
  // إجراءات المزوّد
  // ──────────────────────────────────────

  /// قبول طلب معيّن (عادي/عاجل)
  static Future<ApiResponse> acceptRequest(int requestId) async {
    return ApiClient.post(
        '/api/marketplace/provider/requests/$requestId/accept/');
  }

  /// رفض / إلغاء طلب
  static Future<ApiResponse> rejectRequest(
    int requestId, {
    required String cancelReason,
    String? note,
  }) async {
    return ApiClient.post(
      '/api/marketplace/provider/requests/$requestId/reject/',
      body: {
        'canceled_at': DateTime.now().toIso8601String(),
        'cancel_reason': cancelReason,
        if (note != null) 'note': note,
      },
    );
  }

  /// إرسال مدخلات التنفيذ من المزوّد (يبقى الطلب NEW حتى اعتماد العميل)
  static Future<ApiResponse> startRequest(
    int requestId, {
    required String expectedDeliveryAt,
    required String estimatedServiceAmount,
    required String receivedAmount,
    String? note,
  }) async {
    return ApiClient.post(
      '/api/marketplace/requests/$requestId/start/',
      body: {
        'expected_delivery_at': expectedDeliveryAt,
        'estimated_service_amount': estimatedServiceAmount,
        'received_amount': receivedAmount,
        if (note != null) 'note': note,
      },
    );
  }

  /// قرار العميل على مدخلات المزوّد
  static Future<ApiResponse> decideProviderInputs(
    int requestId, {
    required bool approved,
    String? note,
  }) async {
    return ApiClient.post(
      '/api/marketplace/requests/$requestId/provider-inputs/decision/',
      body: {
        'approved': approved,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// تحديث التقدم أثناء التنفيذ
  static Future<ApiResponse> updateProgress(
    int requestId, {
    String? expectedDeliveryAt,
    String? estimatedServiceAmount,
    String? receivedAmount,
    String? note,
  }) async {
    final body = <String, dynamic>{};
    if (expectedDeliveryAt != null) {
      body['expected_delivery_at'] = expectedDeliveryAt;
    }
    if (estimatedServiceAmount != null) {
      body['estimated_service_amount'] = estimatedServiceAmount;
    }
    if (receivedAmount != null) body['received_amount'] = receivedAmount;
    if (note != null) body['note'] = note;

    return ApiClient.post(
      '/api/marketplace/provider/requests/$requestId/progress-update/',
      body: body,
    );
  }

  /// إكمال الطلب
  static Future<ApiResponse> completeRequest(
    int requestId, {
    required String deliveredAt,
    required String actualServiceAmount,
    String? note,
    List<File> attachments = const [],
  }) async {
    if (attachments.isNotEmpty) {
      final optimizedFiles = <File>[];
      for (final f in attachments) {
        optimizedFiles.add(await UploadOptimizer.optimizeForUpload(f));
      }

      return ApiClient.sendMultipart(
        'POST',
        '/api/marketplace/requests/$requestId/complete/',
        (request) async {
          request.fields['delivered_at'] = deliveredAt;
          request.fields['actual_service_amount'] = actualServiceAmount;
          if (note != null && note.trim().isNotEmpty) {
            request.fields['note'] = note.trim();
          }
          for (final file in optimizedFiles) {
            request.files.add(
              await http.MultipartFile.fromPath('attachments', file.path),
            );
          }
        },
        timeout: const Duration(seconds: 60),
      );
    }

    return ApiClient.post(
      '/api/marketplace/requests/$requestId/complete/',
      body: {
        'delivered_at': deliveredAt,
        'actual_service_amount': actualServiceAmount,
        if (note != null) 'note': note,
      },
    );
  }

  // ──────────────────────────────────────
  // الطلبات العاجلة
  // ──────────────────────────────────────

  /// طلبات عاجلة متاحة للمزوّد
  static Future<List<ServiceRequest>> getAvailableUrgentRequests() async {
    final res =
        await ApiClient.get('/api/marketplace/provider/urgent/available/');
    if (!res.isSuccess) return [];
    final list = res.dataAsList;
    if (list == null) return [];
    return list
        .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// المزوّد يقبل طلب عاجل
  static Future<ApiResponse> acceptUrgentRequest(int requestId) async {
    return ApiClient.post(
      '/api/marketplace/requests/urgent/accept/',
      body: {'request_id': requestId},
    );
  }

  // ──────────────────────────────────────
  // الطلبات التنافسية + العروض
  // ──────────────────────────────────────

  /// طلبات تنافسية متاحة للمزوّد
  static Future<List<ServiceRequest>>
      getAvailableCompetitiveRequests() async {
    final res = await ApiClient.get(
        '/api/marketplace/provider/competitive/available/');
    if (!res.isSuccess) return [];
    final list = res.dataAsList;
    if (list == null) return [];
    return list
        .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// المزوّد يقدّم عرض سعر
  static Future<ApiResponse> createOffer(
    int requestId, {
    required String price,
    required int durationDays,
    String? note,
  }) async {
    return ApiClient.post(
      '/api/marketplace/requests/$requestId/offers/create/',
      body: {
        'price': price,
        'duration_days': durationDays,
        if (note != null) 'note': note,
      },
    );
  }

  /// العميل يعرض العروض على طلب تنافسي
  static Future<List<Offer>> getRequestOffers(int requestId) async {
    final res =
        await ApiClient.get('/api/marketplace/requests/$requestId/offers/');
    if (!res.isSuccess) return [];
    final list = res.dataAsList;
    if (list == null) return [];
    return list
        .map((e) => Offer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// العميل يقبل عرض
  static Future<ApiResponse> acceptOffer(int offerId) async {
    return ApiClient.post('/api/marketplace/offers/$offerId/accept/');
  }

  // ──────────────────────────────────────
  // إلغاء / إعادة فتح الطلب
  // ──────────────────────────────────────

  /// إلغاء طلب
  static Future<ApiResponse> cancelRequest(int requestId, {String? reason}) async {
    return ApiClient.post(
      '/api/marketplace/requests/$requestId/cancel/',
      body: {if (reason != null) 'reason': reason},
    );
  }

  /// إعادة فتح طلب ملغي
  static Future<ApiResponse> reopenRequest(int requestId) async {
    return ApiClient.post('/api/marketplace/requests/$requestId/reopen/');
  }
}
