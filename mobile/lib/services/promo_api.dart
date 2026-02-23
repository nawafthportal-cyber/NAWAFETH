import 'package:dio/dio.dart';

import '../core/network/api_dio.dart';
import '../models/provider_portfolio_item.dart';
import 'api_config.dart';
import 'dio_proxy.dart';

class PromoApi {
  final Dio _dio;

  PromoApi({Dio? dio}) : _dio = dio ?? ApiDio.dio {
    configureDioForLocalhost(_dio, ApiConfig.baseUrl);
  }

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> payload) async {
    final res = await _dio.post(
      '${ApiConfig.apiPrefix}/promo/requests/create/',
      data: payload,
    );
    return _asMap(res.data);
  }

  Future<List<Map<String, dynamic>>> getMyRequests() async {
    final res = await _dio.get('${ApiConfig.apiPrefix}/promo/requests/my/');
    final data = res.data;
    if (data is List) {
      return data.map((e) => _asMap(e)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> getRequestDetail(int requestId) async {
    final res = await _dio.get('${ApiConfig.apiPrefix}/promo/requests/$requestId/');
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> addAsset({
    required int requestId,
    required String filePath,
    String assetType = 'image',
    String? title,
  }) async {
    final formData = FormData.fromMap({
      'asset_type': assetType,
      if ((title ?? '').trim().isNotEmpty) 'title': title,
      'file': await MultipartFile.fromFile(filePath),
    });

    final res = await _dio.post(
      '${ApiConfig.apiPrefix}/promo/requests/$requestId/assets/',
      data: formData,
    );
    return _asMap(res.data);
  }

  /// Public home banner assets (admin-managed).
  ///
  /// Returns a list shaped like `ProviderPortfolioItem` to reuse existing
  /// banner UI widgets.
  Future<List<ProviderPortfolioItem>> getHomeBanners({int limit = 6}) async {
    try {
      final res = await _dio.get(
        '${ApiConfig.apiPrefix}/promo/banners/home/',
        queryParameters: {'limit': limit},
      );

      final data = res.data;
      if (data is List) {
        return data
            .whereType<dynamic>()
            .map((e) => ProviderPortfolioItem.fromJson(_asMap(e)))
            .toList();
      }
      return const [];
    } on DioException {
      // Endpoint might not exist yet on older deployments.
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Public active promo placements.
  ///
  /// This is a generalized endpoint for any promo `ad_type`.
  Future<List<Map<String, dynamic>>> getActivePromos({
    String? adType,
    String? city,
    String? category,
    int limit = 20,
  }) async {
    try {
      final qp = <String, dynamic>{'limit': limit};
      if ((adType ?? '').trim().isNotEmpty) qp['ad_type'] = adType;
      if ((city ?? '').trim().isNotEmpty) qp['city'] = city;
      if ((category ?? '').trim().isNotEmpty) qp['category'] = category;

      final res = await _dio.get(
        '${ApiConfig.apiPrefix}/promo/active/',
        queryParameters: qp,
      );
      final data = res.data;
      if (data is List) {
        return data.map((e) => _asMap(e)).toList();
      }
      return const [];
    } on DioException {
      // Endpoint might not exist yet on older deployments.
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}
