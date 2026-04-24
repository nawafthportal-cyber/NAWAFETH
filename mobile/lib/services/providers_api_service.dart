library;

import 'api_client.dart';
import 'app_logger.dart';
import 'local_cache_service.dart';
import '../models/provider_public_model.dart';

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
  static const Duration _searchCacheTtl = Duration(minutes: 10);
  static const String _lastSearchCacheKey = 'providers_search_last_cache_v2';
  static const String _lastSearchFiltersKey = 'providers_search_last_filters_v1';

  static final Map<String, _SearchProvidersCacheEntry> _searchPageCache =
      <String, _SearchProvidersCacheEntry>{};

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
    int page = 1,
    int? pageSize,
    String? query,
    int? categoryId,
    Map<String, String>? extraQueryParameters,
  }) {
    final queryParameters = <String, String>{
      if (page > 1) 'page': '$page',
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

  static Future<SearchProvidersPageResult> fetchProvidersPageResult({
    int page = 1,
    int pageSize = 20,
    String? query,
    int? categoryId,
    Map<String, String>? extraQueryParameters,
    bool forceRefresh = false,
  }) async {
    final normalizedExtras = _normalizeExtraQueryParameters(extraQueryParameters);
    final cacheKey = _buildSearchCacheKey(
      page: page,
      pageSize: pageSize,
      query: query,
      categoryId: categoryId,
      extraQueryParameters: normalizedExtras,
    );

    final memoryCache = _searchPageCache[cacheKey];
    if (!forceRefresh && memoryCache != null && memoryCache.isFresh(_searchCacheTtl)) {
      return memoryCache.result.copyWith(source: 'memory_cache');
    }

    SearchProvidersPageResult? diskCache;
    if (page == 1) {
      diskCache = await _readLastSearchDiskCache(cacheKey);
      if (!forceRefresh && diskCache != null && diskCache.isFresh(_searchCacheTtl)) {
        _searchPageCache[cacheKey] = _SearchProvidersCacheEntry(
          diskCache.copyWith(source: 'disk_cache'),
          DateTime.now(),
        );
        return diskCache.copyWith(source: 'disk_cache');
      }
    }

    final response = await fetchProvidersList(
      page: page,
      pageSize: pageSize,
      query: query,
      categoryId: categoryId,
      extraQueryParameters: normalizedExtras,
    );

    if (response.isSuccess && response.data != null) {
      final parsed = _parseProvidersPageResponse(
        response.data,
        page: page,
        pageSize: pageSize,
      );
      final result = SearchProvidersPageResult(
        data: parsed.items,
        source: 'network',
        totalCount: parsed.totalCount,
        hasMore: parsed.hasMore,
        nextPage: parsed.nextPage,
      );
      _searchPageCache[cacheKey] = _SearchProvidersCacheEntry(result, DateTime.now());
      if (page == 1) {
        await _writeLastSearchDiskCache(
          cacheKey: cacheKey,
          pageSize: pageSize,
          query: query,
          categoryId: categoryId,
          extraQueryParameters: normalizedExtras,
          result: result,
        );
      }
      return result;
    }

    if (memoryCache != null) {
      return memoryCache.result.copyWith(
        source: 'memory_cache_stale',
        errorMessage: response.error,
        statusCode: response.statusCode,
      );
    }
    if (diskCache != null) {
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: response.error,
        statusCode: response.statusCode,
      );
    }
    return SearchProvidersPageResult(
      data: const <ProviderPublicModel>[],
      source: 'empty',
      errorMessage: response.error,
      statusCode: response.statusCode,
      hasMore: false,
      totalCount: 0,
    );
  }

  static Future<void> saveLastSearchFilters({
    required String query,
    int? categoryId,
    String sort = 'default',
  }) {
    return LocalCacheService.writeJson(_lastSearchFiltersKey, {
      'query': query.trim(),
      'category_id': categoryId,
      'sort': sort.trim().isEmpty ? 'default' : sort.trim(),
    });
  }

  static Future<SearchFiltersSnapshot?> loadLastSearchFilters() async {
    final envelope = await LocalCacheService.readJson(_lastSearchFiltersKey);
    final payload = envelope?.payload;
    if (payload is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(payload);
    return SearchFiltersSnapshot(
      query: (map['query'] as String? ?? '').trim(),
      categoryId: _toInt(map['category_id']),
      sort: (map['sort'] as String? ?? 'default').trim(),
    );
  }

  static Future<void> clearSearchCache() async {
    _searchPageCache.clear();
    await LocalCacheService.remove(_lastSearchCacheKey);
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

  static Map<String, String> _normalizeExtraQueryParameters(
    Map<String, String>? extraQueryParameters,
  ) {
    if (extraQueryParameters == null || extraQueryParameters.isEmpty) {
      return const <String, String>{};
    }
    final entries = extraQueryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return <String, String>{
      for (final entry in entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
  }

  static String _buildSearchCacheKey({
    required int page,
    required int pageSize,
    String? query,
    int? categoryId,
    required Map<String, String> extraQueryParameters,
  }) {
    final extrasSignature = extraQueryParameters.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    return [
      'page=$page',
      'page_size=$pageSize',
      'query=${(query ?? '').trim()}',
      'category=${categoryId ?? ''}',
      'extra=$extrasSignature',
    ].join('|');
  }

  static _ParsedProvidersPage _parseProvidersPageResponse(
    dynamic responseData, {
    required int page,
    required int pageSize,
  }) {
    List<dynamic> rawItems = const <dynamic>[];
    int totalCount = 0;
    String? nextUrl;

    if (responseData is List) {
      rawItems = responseData;
      totalCount = rawItems.length;
    } else if (responseData is Map) {
      final map = Map<String, dynamic>.from(responseData);
      rawItems = map['results'] is List ? map['results'] as List<dynamic> : const <dynamic>[];
      totalCount = _toInt(map['count']) ?? rawItems.length;
      nextUrl = (map['next'] as String?)?.trim();
    }

    final items = rawItems
        .whereType<Map>()
        .map((item) => ProviderPublicModel.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);

    final nextPage = _extractNextPage(nextUrl) ??
        ((items.length >= pageSize || totalCount > page * pageSize) ? page + 1 : null);
    final hasMore = nextPage != null || totalCount > page * pageSize;

    return _ParsedProvidersPage(
      items: items,
      totalCount: totalCount < items.length ? items.length : totalCount,
      hasMore: hasMore,
      nextPage: hasMore ? nextPage ?? (page + 1) : null,
    );
  }

  static int? _extractNextPage(String? nextUrl) {
    final raw = (nextUrl ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      return _toInt(uri.queryParameters['page']);
    } catch (_) {
      return null;
    }
  }

  static Future<SearchProvidersPageResult?> _readLastSearchDiskCache(
    String cacheKey,
  ) async {
    final envelope = await LocalCacheService.readJson(_lastSearchCacheKey);
    if (envelope == null) {
      return null;
    }
    final payload = envelope.payload;
    if (payload is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(payload);
    if ((map['cache_key'] as String?) != cacheKey) {
      return null;
    }
    final rows = map['rows'];
    if (rows is! List) {
      return null;
    }
    final items = rows
        .whereType<Map>()
        .map((item) => ProviderPublicModel.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return SearchProvidersPageResult(
      data: items,
      source: 'disk_cache',
      totalCount: _toInt(map['total_count']) ?? items.length,
      hasMore: map['has_more'] == true,
      nextPage: _toInt(map['next_page']),
      cachedAt: envelope.cachedAt.toLocal(),
    );
  }

  static Future<void> _writeLastSearchDiskCache({
    required String cacheKey,
    required int pageSize,
    String? query,
    int? categoryId,
    required Map<String, String> extraQueryParameters,
    required SearchProvidersPageResult result,
  }) {
    return LocalCacheService.writeJson(_lastSearchCacheKey, {
      'cache_key': cacheKey,
      'page_size': pageSize,
      'query': (query ?? '').trim(),
      'category_id': categoryId,
      'extra': extraQueryParameters,
      'total_count': result.totalCount,
      'has_more': result.hasMore,
      'next_page': result.nextPage,
      'rows': result.data.map(_serializeProvider).toList(growable: false),
    });
  }

  static Map<String, dynamic> _serializeProvider(ProviderPublicModel provider) {
    return {
      'id': provider.id,
      'provider_type': provider.providerType,
      'provider_type_label': provider.providerTypeLabel,
      'display_name': provider.displayName,
      'username': provider.username,
      'profile_image': provider.profileImage,
      'cover_image': provider.coverImage,
      'bio': provider.bio,
      'about_details': provider.aboutDetails,
      'years_experience': provider.yearsExperience,
      'phone': provider.phone,
      'whatsapp': provider.whatsapp,
      'website': provider.website,
      'social_links': provider.socialLinks,
      'languages': provider.languages,
      'city': provider.city,
      'city_display': provider.cityDisplay,
      'lat': provider.lat,
      'lng': provider.lng,
      'coverage_radius_km': provider.coverageRadiusKm,
      'accepts_urgent': provider.acceptsUrgent,
      'is_verified_blue': provider.isVerifiedBlue,
      'is_verified_green': provider.isVerifiedGreen,
      'excellence_badges': provider.excellenceBadges
          .map((badge) => badge.toJson())
          .toList(growable: false),
      'qualifications': provider.qualifications,
      'content_sections': provider.contentSections,
      'rating_avg': provider.ratingAvg,
      'rating_count': provider.ratingCount,
      'created_at': provider.createdAt,
      'followers_count': provider.followersCount,
      'likes_count': provider.likesCount,
      'following_count': provider.followingCount,
      'completed_requests': provider.completedRequests,
      'primary_category_name': provider.primaryCategoryName,
      'primary_subcategory_name': provider.primarySubcategoryName,
      'main_categories': provider.mainCategories,
      'selected_subcategories': provider.selectedSubcategories,
      'subcategory_ids': provider.subcategoryIds,
    };
  }
}

class SearchProvidersPageResult {
  final List<ProviderPublicModel> data;
  final String source;
  final String? errorMessage;
  final int statusCode;
  final int totalCount;
  final bool hasMore;
  final int? nextPage;
  final DateTime? cachedAt;

  const SearchProvidersPageResult({
    required this.data,
    required this.source,
    this.errorMessage,
    this.statusCode = 200,
    required this.totalCount,
    required this.hasMore,
    this.nextPage,
    this.cachedAt,
  });

  bool get fromCache => source.contains('cache');

  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;

  bool get isStaleCache => source.endsWith('_stale');

  bool get isOfflineFallback => isStaleCache && statusCode == 0;

  bool isFresh(Duration ttl) {
    final value = cachedAt;
    if (value == null) {
      return false;
    }
    return DateTime.now().difference(value) <= ttl;
  }

  SearchProvidersPageResult copyWith({
    String? source,
    String? errorMessage,
    int? statusCode,
    DateTime? cachedAt,
  }) {
    return SearchProvidersPageResult(
      data: List<ProviderPublicModel>.from(data),
      source: source ?? this.source,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
      totalCount: totalCount,
      hasMore: hasMore,
      nextPage: nextPage,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}

class SearchFiltersSnapshot {
  final String query;
  final int? categoryId;
  final String sort;

  const SearchFiltersSnapshot({
    required this.query,
    required this.categoryId,
    required this.sort,
  });
}

class _SearchProvidersCacheEntry {
  final SearchProvidersPageResult result;
  final DateTime fetchedAt;

  const _SearchProvidersCacheEntry(this.result, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }
}

class _ParsedProvidersPage {
  final List<ProviderPublicModel> items;
  final int totalCount;
  final bool hasMore;
  final int? nextPage;

  const _ParsedProvidersPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextPage,
  });
}
