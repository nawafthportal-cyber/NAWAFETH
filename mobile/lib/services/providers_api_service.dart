library;

import 'api_client.dart';
import 'app_logger.dart';

class SearchPromoBundle {
  final ApiResponse? categoryBanner;
  final ApiResponse searchBanner;
  final ApiResponse? categoryPopup;
  final ApiResponse searchResults;
  final ApiResponse featuredTop5;

  const SearchPromoBundle({
    required this.categoryBanner,
    required this.searchBanner,
    required this.categoryPopup,
    required this.searchResults,
    required this.featuredTop5,
  });
}

class ProvidersApiService {
  static Future<SearchPromoBundle> fetchSearchPromoBundle({
    required String selectedCategoryName,
    String selectedCategoryCity = '',
  }) async {
    final searchPromoUri = Uri(
      path: '/api/promo/active/',
      queryParameters: {
        'service_type': 'search_results',
        'limit': '10',
        'search_scope': selectedCategoryName.isNotEmpty
            ? 'default,main_results,category_match'
            : 'default,main_results',
        if (selectedCategoryName.isNotEmpty) 'category': selectedCategoryName,
      },
    );

    final categoryBannerFuture = selectedCategoryName.isNotEmpty
        ? ApiClient.get(
            Uri(
              path: '/api/promo/active/',
              queryParameters: {
                'ad_type': 'banner_category',
                'limit': '1',
                'category': selectedCategoryName,
                if (selectedCategoryCity.isNotEmpty) 'city': selectedCategoryCity,
              },
            ).toString(),
          )
        : Future<ApiResponse?>.value(null);

    final categoryPopupFuture = selectedCategoryName.isNotEmpty
        ? ApiClient.get(
            Uri(
              path: '/api/promo/active/',
              queryParameters: {
                'ad_type': 'popup_category',
                'limit': '1',
                'category': selectedCategoryName,
                if (selectedCategoryCity.isNotEmpty) 'city': selectedCategoryCity,
              },
            ).toString(),
          )
        : Future<ApiResponse?>.value(null);

    try {
      final results = await Future.wait<dynamic>([
        categoryBannerFuture,
        ApiClient.get('/api/promo/active/?ad_type=banner_search&limit=1'),
        categoryPopupFuture,
        ApiClient.get(searchPromoUri.toString()),
        ApiClient.get('/api/promo/active/?ad_type=featured_top5&limit=10'),
      ]);

      return SearchPromoBundle(
        categoryBanner: results[0] as ApiResponse?,
        searchBanner: results[1] as ApiResponse,
        categoryPopup: results[2] as ApiResponse?,
        searchResults: results[3] as ApiResponse,
        featuredTop5: results[4] as ApiResponse,
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ProvidersApiService.fetchSearchPromoBundle failed',
        error: error,
        stackTrace: stackTrace,
      );
      return SearchPromoBundle(
        categoryBanner: null,
        searchBanner: ApiResponse(statusCode: 0, error: 'failed'),
        categoryPopup: null,
        searchResults: ApiResponse(statusCode: 0, error: 'failed'),
        featuredTop5: ApiResponse(statusCode: 0, error: 'failed'),
      );
    }
  }

  static Future<ApiResponse> fetchProvidersList({
    int? pageSize,
    String? query,
    int? categoryId,
    Map<String, String>? extraQueryParameters,
  }) {
    final queryParameters = <String, String>{
      if (pageSize != null && pageSize > 0) 'page_size': '$pageSize',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (categoryId != null) 'category_id': categoryId.toString(),
    };
    if (extraQueryParameters != null && extraQueryParameters.isNotEmpty) {
      queryParameters.addAll(extraQueryParameters);
    }

    final uri = Uri(
      path: '/api/providers/list/',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return ApiClient.get(uri.toString());
  }

  static Future<int?> fetchCurrentProviderProfileId() async {
    try {
      final response = await ApiClient.get('/api/accounts/me/?mode=provider');
      if (!response.isSuccess || response.dataAsMap == null) {
        return null;
      }
      return _toInt(response.dataAsMap!['provider_profile_id']);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ProvidersApiService.fetchCurrentProviderProfileId failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
