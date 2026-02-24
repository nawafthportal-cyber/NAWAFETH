import 'package:dio/dio.dart';

import '../core/network/api_dio.dart';
import 'api_config.dart';
import 'dio_proxy.dart';

class ReviewsApi {
  final Dio _dio;

  ReviewsApi({Dio? dio}) : _dio = dio ?? ApiDio.dio {
    configureDioForLocalhost(_dio, ApiConfig.baseUrl);
  }

  Future<Map<String, dynamic>> getProviderRatingSummary(int providerId) async {
    final res = await _dio.get('${ApiConfig.apiPrefix}/reviews/providers/$providerId/rating/');
    if (res.data is Map<String, dynamic>) {
      return res.data as Map<String, dynamic>;
    }
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data as Map);
    }
    throw StateError('Unexpected rating summary response');
  }

  Future<List<Map<String, dynamic>>> getProviderReviews(int providerId) async {
    final res = await _dio.get('${ApiConfig.apiPrefix}/reviews/providers/$providerId/reviews/');
    final data = res.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final results = map['results'];
      if (results is List) {
        return results
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    throw StateError('Unexpected provider reviews response');
  }

  Future<int> createReview({
    required int requestId,
    int? rating,
    required int responseSpeed,
    required int costValue,
    required int quality,
    required int credibility,
    required int onTime,
    String? comment,
  }) async {
    final payload = <String, dynamic>{
      'response_speed': responseSpeed,
      'cost_value': costValue,
      'quality': quality,
      'credibility': credibility,
      'on_time': onTime,
    };

    final trimmedComment = (comment ?? '').trim();
    if (trimmedComment.isNotEmpty) {
      payload['comment'] = trimmedComment;
    }
    if (rating != null) {
      payload['rating'] = rating;
    }

    final res = await _dio.post(
      '${ApiConfig.apiPrefix}/reviews/requests/$requestId/review/',
      data: payload,
    );

    final data = res.data;
    Map<String, dynamic> json;
    if (data is Map<String, dynamic>) {
      json = data;
    } else if (data is Map) {
      json = Map<String, dynamic>.from(data);
    } else {
      throw StateError('Unexpected create review response');
    }

    final reviewId = json['review_id'];
    if (reviewId is int) return reviewId;
    if (reviewId is String) {
      final parsed = int.tryParse(reviewId);
      if (parsed != null) return parsed;
    }
    throw StateError('Missing review_id in create review response');
  }

  Future<Map<String, dynamic>> replyToReviewAsProvider({
    required int reviewId,
    required String reply,
  }) async {
    final trimmed = reply.trim();
    if (trimmed.isEmpty) {
      throw StateError('الرد مطلوب');
    }

    final res = await _dio.post(
      '${ApiConfig.apiPrefix}/reviews/reviews/$reviewId/provider-reply/',
      data: {'provider_reply': trimmed},
    );

    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Unexpected provider reply response');
  }

  Future<void> deleteReviewReplyAsProvider({required int reviewId}) async {
    await _dio.delete(
      '${ApiConfig.apiPrefix}/reviews/reviews/$reviewId/provider-reply/',
    );
  }
}
