/// خدمة المراجعات — /api/reviews/*
library;

import 'api_client.dart';

class ReviewsService {
  /// إنشاء مراجعة لطلب مكتمل
  static Future<ApiResponse> createReview({
    required int requestId,
    required int rating,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      'rating': rating,
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
}
