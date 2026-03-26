/// خدمة المراجعات — /api/reviews/*
library;

import 'api_client.dart';

class ReviewsService {
  /// إنشاء مراجعة لطلب مكتمل
  static Future<ApiResponse> createReview({
    required int requestId,
    required int responseSpeed,
    required int costValue,
    required int quality,
    required int credibility,
    required int onTime,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      'response_speed': responseSpeed,
      'cost_value': costValue,
      'quality': quality,
      'credibility': credibility,
      'on_time': onTime,
    };
    if (comment != null && comment.isNotEmpty) {
      body['comment'] = comment;
    }
    return ApiClient.post(
      '/api/reviews/requests/$requestId/review/',
      body: body,
    );
  }

  /// جلب مراجعات مزود معين
  static Future<ApiResponse> fetchProviderReviews(int providerId) async {
    return ApiClient.get('/api/reviews/providers/$providerId/reviews/');
  }

  /// جلب ملخص التقييم لمزود معين
  static Future<ApiResponse> fetchProviderRating(int providerId) async {
    return ApiClient.get('/api/reviews/providers/$providerId/rating/');
  }

  /// رد المزود على مراجعة
  static Future<ApiResponse> replyToReview(int reviewId, String replyText) async {
    return ApiClient.post(
      '/api/reviews/reviews/$reviewId/provider-reply/',
      body: {'provider_reply': replyText},
    );
  }

  /// تبديل/ضبط إعجاب المزود بالتقييم
  static Future<ApiResponse> toggleProviderLike(int reviewId, {bool? liked}) async {
    final body = <String, dynamic>{};
    if (liked != null) {
      body['liked'] = liked;
    }
    return ApiClient.post(
      '/api/reviews/reviews/$reviewId/provider-like/',
      body: body,
    );
  }

  /// إنشاء/جلب محادثة مباشرة مع صاحب التقييم
  static Future<ApiResponse> getOrCreateProviderReviewChatThread(int reviewId) async {
    return ApiClient.post('/api/reviews/reviews/$reviewId/provider-chat-thread/');
  }
}
