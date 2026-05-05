import 'dart:math';

import 'api_client.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/featured_specialist_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import 'app_logger.dart';
import 'local_cache_service.dart';

/// خدمة الصفحة الرئيسية — تجلب البيانات من الـ API
class HomeService {
  static const Duration _cacheTtl = Duration(minutes: 15);
  static const String _categoriesCacheKey = 'home_categories_cache_v1';
  static const String _featuredProvidersCacheKey =
      'home_featured_providers_cache_v1';
  static const String _featuredSpecialistsCacheKey =
      'home_featured_specialists_cache_v1';
  static const String _homeBannersCacheKey = 'home_banners_cache_v1';
  static const String _spotlightsCacheKey = 'home_spotlights_cache_v1';

  static _CacheEntry<List<CategoryModel>>? _categoriesCache;
  static final Map<int, _CacheEntry<List<ProviderPublicModel>>>
      _featuredProvidersCache = {};
  static final Map<int, _CacheEntry<List<FeaturedSpecialistModel>>>
      _featuredSpecialistsCache = {};
  static final Map<int, _CacheEntry<List<BannerModel>>> _homeBannersCache = {};
  static final Map<int, _CacheEntry<List<MediaItemModel>>> _spotlightsCache =
      {};

  static List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final results = map['results'];
      if (results is List) return results;
    }
    return const [];
  }

  static List<BannerModel> _parseBannerList(dynamic data) {
    return _extractList(data)
        .whereType<Map>()
        .map((item) => BannerModel.fromJson(Map<String, dynamic>.from(item)))
        .where((banner) => (banner.mediaUrl ?? '').isNotEmpty)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _serializeCategories(
    List<CategoryModel> categories,
  ) {
    return categories
        .map((category) => {
              'id': category.id,
              'name': category.name,
              'subcategories': category.subcategories
                  .map((sub) => {
                        'id': sub.id,
                        'name': sub.name,
                      })
                  .toList(growable: false),
            })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _serializeProviders(
    List<ProviderPublicModel> providers,
  ) {
    return providers
        .map((provider) => {
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
            })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _serializeBanners(
      List<BannerModel> banners) {
    return banners
        .map((banner) => {
              'id': banner.id,
              'title': banner.title,
              'media_type': banner.mediaType,
              'media_url': banner.mediaUrl,
              'link_url': banner.linkUrl,
              'provider_id': banner.providerId,
              'provider_display_name': banner.providerDisplayName,
              'display_order': banner.displayOrder,
              'duration_seconds': banner.durationSeconds,
              'mobile_scale': banner.mobileScale,
              'tablet_scale': banner.tabletScale,
              'desktop_scale': banner.desktopScale,
            })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _serializeSpotlights(
    List<MediaItemModel> items,
  ) {
    return items
        .map((item) => {
              'id': item.id,
              'provider_id': item.providerId,
              'provider_display_name': item.providerDisplayName,
              'provider_username': item.providerUsername,
              'provider_profile_image': item.providerProfileImage,
              'file_type': item.fileType,
              'file_url': item.fileUrl,
              'thumbnail_url': item.thumbnailUrl,
              'caption': item.caption,
              'section_title': item.sectionTitle,
              'sponsored_badge_only': item.sponsoredBadgeOnly,
              'likes_count': item.likesCount,
              'comments_count': item.commentsCount,
              'saves_count': item.savesCount,
              'is_liked': item.isLiked,
              'is_saved': item.isSaved,
              'created_at': item.createdAt,
              'source': item.source.name,
            })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _serializeFeaturedSpecialists(
    List<FeaturedSpecialistModel> items,
  ) {
    return items
        .map((item) => {
              'id': item.placementId,
              'item_id': item.placementId,
              'target_provider_id': item.providerId,
              'target_provider_display_name': item.displayName,
              'target_provider_profile_image': item.profileImage,
              'target_provider_city': item.city,
              'target_provider_city_display': item.cityDisplay,
              'redirect_url': item.redirectUrl,
              'target_provider_is_verified_blue': item.isVerifiedBlue,
              'target_provider_is_verified_green': item.isVerifiedGreen,
              'target_provider_rating_avg': item.ratingAvg,
              'target_provider_rating_count': item.ratingCount,
              'target_provider_excellence_badges': item.excellenceBadges
                  .map((badge) => badge.toJson())
                  .toList(growable: false),
            })
        .toList(growable: false);
  }

  static _CacheEntry<List<T>>? _readDiskListCache<T>(
    String key,
    List<T> Function(List<Map<String, dynamic>> rows) parser,
  ) {
    final envelope = LocalCacheService.readJsonSync(key);
    final payload = envelope?.payload;
    if (payload is! List) {
      return null;
    }
    final rows = payload
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return _CacheEntry<List<T>>(parser(rows), envelope!.cachedAt.toLocal());
  }

  static Future<void> _writeDiskListCache(
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    await LocalCacheService.writeJson(key, rows);
  }

  static CachedFetchResult<List<T>> _buildCachedResult<T>({
    required List<T> data,
    required String source,
    String? errorMessage,
    int statusCode = 200,
  }) {
    return CachedFetchResult<List<T>>(
      data: data,
      source: source,
      errorMessage: errorMessage,
      statusCode: statusCode,
    );
  }

  static List<BannerModel> _dedupeBanners(List<BannerModel> banners) {
    final seen = <String>{};
    final result = <BannerModel>[];
    for (final banner in banners) {
      final signature = [
        banner.id,
        banner.mediaUrl ?? '',
        banner.linkUrl ?? '',
        banner.providerId ?? 0,
        banner.displayOrder,
      ].join('|');
      if (!seen.add(signature)) {
        continue;
      }
      result.add(banner);
    }
    return List<BannerModel>.unmodifiable(result);
  }

  static List<BannerModel> _shuffleBanners(List<BannerModel> banners) {
    final random = Random();
    final rows = List<BannerModel>.from(banners);
    for (var i = rows.length - 1; i > 0; i -= 1) {
      final j = random.nextInt(i + 1);
      final temp = rows[i];
      rows[i] = rows[j];
      rows[j] = temp;
    }
    return rows;
  }

  static List<BannerModel> _mergePrioritizedHomeBanners({
    required List<BannerModel> sponsored,
    required List<BannerModel> organic,
    required int limit,
  }) {
    final cap = limit <= 0 ? 16 : limit;
    final sponsoredRows = _dedupeBanners(sponsored);
    final organicRows = _shuffleBanners(_dedupeBanners(organic));
    if (sponsoredRows.length >= cap) {
      return List<BannerModel>.unmodifiable(sponsoredRows.take(cap));
    }
    final remaining = cap - sponsoredRows.length;
    return List<BannerModel>.unmodifiable(
      <BannerModel>[
        ...sponsoredRows,
        ...organicRows.take(remaining),
      ],
    );
  }

  static String _readText(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = _readText(value).toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static List<Map<String, dynamic>> _extractMapList(dynamic data) {
    return _extractList(data)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static DateTime _spotlightTimestamp(MediaItemModel item) {
    final raw = _readText(item.createdAt);
    if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(raw) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static MediaItemModel? _snapshotItemFromPlacement(
      Map<String, dynamic> placement) {
    final nestedRaw = placement['spotlight_item'];
    final nested =
        nestedRaw is Map ? Map<String, dynamic>.from(nestedRaw) : null;

    final fileUrl = nested == null
        ? _readText(placement['target_spotlight_item_file'])
        : _readText(nested['file_url']);
    if (fileUrl.isEmpty) return null;

    final rawCaption = nested == null
        ? _readText(placement['title'])
        : _readText(nested['caption']);
    final caption = (rawCaption == 'لمحة ممولة' || rawCaption == 'ترويج ممول')
        ? ''
        : rawCaption;

    final id = nested == null
        ? _readInt(placement['target_spotlight_item_id'])
        : _readInt(nested['id']);
    final providerId = nested == null
        ? _readInt(placement['target_provider_id'])
        : _readInt(nested['provider_id']);
    final providerName = nested == null
        ? _readText(placement['target_provider_display_name'])
        : _readText(nested['provider_display_name']);
    final profileImage = nested == null
        ? _readText(placement['target_provider_profile_image'])
        : _readText(nested['provider_profile_image']);
    final fileType = (nested == null
            ? _readText(placement['target_spotlight_item_file_type'])
            : _readText(nested['file_type']))
        .toLowerCase();
    final thumbnailUrl =
        nested == null ? '' : _readText(nested['thumbnail_url']);
    final createdAt = nested == null ? '' : _readText(nested['created_at']);
    final likesCount = nested == null ? 0 : _readInt(nested['likes_count']);
    final savesCount = nested == null ? 0 : _readInt(nested['saves_count']);
    final isLiked = nested == null ? false : _readBool(nested['is_liked']);
    final isSaved = nested == null ? false : _readBool(nested['is_saved']);

    final model = MediaItemModel(
      id: id,
      providerId: providerId,
      providerDisplayName: providerName.isEmpty ? 'مقدم خدمة' : providerName,
      providerProfileImage: profileImage.isEmpty ? null : profileImage,
      isVerifiedBlue: nested == null
        ? _readBool(placement['target_provider_is_verified_blue'])
        : _readBool(nested['is_verified_blue']),
      isVerifiedGreen: nested == null
        ? _readBool(placement['target_provider_is_verified_green'])
        : _readBool(nested['is_verified_green']),
      fileType: fileType.isEmpty ? 'image' : fileType,
      fileUrl: fileUrl,
      thumbnailUrl: thumbnailUrl.isEmpty ? null : thumbnailUrl,
      caption: caption,
      sectionTitle: 'ترويج ممول',
      sponsoredBadgeOnly: true,
      likesCount: likesCount,
      savesCount: savesCount,
      isLiked: isLiked,
      isSaved: isSaved,
      createdAt: createdAt.isEmpty ? null : createdAt,
      source: MediaItemSource.spotlight,
    );
    model.applyInteractionOverride();
    model.rememberInteractionState();
    return model;
  }

  static List<MediaItemModel> _mergeSpotlightItems({
    required List<MediaItemModel> promoItems,
    required List<MediaItemModel> feedItems,
    required int limit,
  }) {
    final maxItems = limit > 0 ? limit : 1;
    final merged = <MediaItemModel>[];
    final seen = <String>{};

    final sortedFeed = List<MediaItemModel>.from(feedItems)
      ..sort((a, b) {
        final byTime = _spotlightTimestamp(b).compareTo(_spotlightTimestamp(a));
        if (byTime != 0) return byTime;
        return b.id.compareTo(a.id);
      });

    void push(MediaItemModel item) {
      final mediaKey = _readText(item.fileUrl).isNotEmpty
          ? _readText(item.fileUrl)
          : _readText(item.thumbnailUrl);
      if (mediaKey.isEmpty) return;
      final key = '${item.providerId}|$mediaKey|${item.source.name}';
      if (!seen.add(key)) return;
      merged.add(item);
    }

    for (final item in promoItems) {
      if (merged.length >= maxItems) break;
      push(item);
    }
    for (final item in sortedFeed) {
      if (merged.length >= maxItems) break;
      push(item);
    }
    return List<MediaItemModel>.unmodifiable(merged);
  }

  static HomeCachedData getCachedHomeData({
    int providersLimit = 10,
    int bannersLimit = 6,
    int spotlightsLimit = 16,
  }) {
    final categories = _categoriesCache?.data ??
        _readDiskListCache<CategoryModel>(
          _categoriesCacheKey,
          (rows) => rows.map(CategoryModel.fromJson).toList(growable: false),
        )?.data ??
        const <CategoryModel>[];
    final providers = _featuredProvidersCache[providersLimit]?.data ??
        _readDiskListCache<ProviderPublicModel>(
          _featuredProvidersCacheKey,
          (rows) =>
              rows.map(ProviderPublicModel.fromJson).toList(growable: false),
        )?.data ??
        const <ProviderPublicModel>[];
    final banners = _homeBannersCache[bannersLimit]?.data ??
        _readDiskListCache<BannerModel>(
          _homeBannersCacheKey,
          (rows) => rows.map(BannerModel.fromJson).toList(growable: false),
        )?.data ??
        const <BannerModel>[];
    final spotlights = List<MediaItemModel>.from(
      _spotlightsCache[spotlightsLimit]?.data ??
          _readDiskListCache<MediaItemModel>(
            _spotlightsCacheKey,
            (rows) => rows
                .map(
                  (row) => MediaItemModel.fromJson(
                    row,
                    source: row['source'] == MediaItemSource.spotlight.name
                        ? MediaItemSource.spotlight
                        : MediaItemSource.portfolio,
                  ),
                )
                .toList(growable: false),
          )?.data ??
          const <MediaItemModel>[],
    );
    MediaItemModel.applyInteractionOverrides(spotlights);
    return HomeCachedData(
      categories: List<CategoryModel>.from(categories),
      providers: List<ProviderPublicModel>.from(providers),
      banners: List<BannerModel>.from(banners),
      spotlights: spotlights,
    );
  }

  // ── التصنيفات ──
  static Future<List<CategoryModel>> fetchCategories(
      {bool forceRefresh = false}) async {
    final result = await fetchCategoriesResult(forceRefresh: forceRefresh);
    return result.data;
  }

  static Future<CachedFetchResult<List<CategoryModel>>> fetchCategoriesResult({
    bool forceRefresh = false,
  }) async {
    final cached = _categoriesCache;
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return _buildCachedResult(
        data: List<CategoryModel>.from(cached.data),
        source: 'memory_cache',
      );
    }

    final diskCache = _readDiskListCache<CategoryModel>(
      _categoriesCacheKey,
      (rows) => rows.map(CategoryModel.fromJson).toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _categoriesCache = diskCache;
      return _buildCachedResult(
        data: List<CategoryModel>.from(diskCache.data),
        source: 'disk_cache',
      );
    }

    final res = await ApiClient.get('/api/providers/categories/');
    if (res.isSuccess && res.data != null) {
      final list = res.data is List
          ? res.data as List
          : (res.data['results'] as List?) ?? [];
      final parsed = list
          .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _categoriesCache = _CacheEntry<List<CategoryModel>>(
        List<CategoryModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      await _writeDiskListCache(
          _categoriesCacheKey, _serializeCategories(parsed));
      return _buildCachedResult(data: parsed, source: 'network');
    }
    if (cached != null) {
      return _buildCachedResult(
        data: List<CategoryModel>.from(cached.data),
        source: 'memory_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    if (diskCache != null) {
      _categoriesCache = diskCache;
      return _buildCachedResult(
        data: List<CategoryModel>.from(diskCache.data),
        source: 'disk_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    return _buildCachedResult(
      data: const <CategoryModel>[],
      source: 'empty',
      errorMessage: res.error,
      statusCode: res.statusCode,
    );
  }

  // ── مزودو الخدمة (مميزون / أحدث) ──
  static Future<List<ProviderPublicModel>> fetchFeaturedProviders({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final result = await fetchFeaturedProvidersResult(
      limit: limit,
      forceRefresh: forceRefresh,
    );
    return result.data;
  }

  static Future<CachedFetchResult<List<ProviderPublicModel>>>
      fetchFeaturedProvidersResult({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _featuredProvidersCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return _buildCachedResult(
        data: List<ProviderPublicModel>.from(cached.data),
        source: 'memory_cache',
      );
    }

    final diskCache = _readDiskListCache<ProviderPublicModel>(
      _featuredProvidersCacheKey,
      (rows) => rows.map(ProviderPublicModel.fromJson).toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _featuredProvidersCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<ProviderPublicModel>.from(diskCache.data),
        source: 'disk_cache',
      );
    }

    final res = await ApiClient.get('/api/providers/list/?page_size=$limit');
    if (res.isSuccess && res.data != null) {
      final list = res.data is List
          ? res.data as List
          : (res.data['results'] as List?) ?? [];
      final parsed = list
          .map((e) => ProviderPublicModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _featuredProvidersCache[limit] = _CacheEntry<List<ProviderPublicModel>>(
        List<ProviderPublicModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      await _writeDiskListCache(
        _featuredProvidersCacheKey,
        _serializeProviders(parsed),
      );
      return _buildCachedResult(data: parsed, source: 'network');
    }
    if (cached != null) {
      return _buildCachedResult(
        data: List<ProviderPublicModel>.from(cached.data),
        source: 'memory_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    if (diskCache != null) {
      _featuredProvidersCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<ProviderPublicModel>.from(diskCache.data),
        source: 'disk_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    return _buildCachedResult(
      data: const <ProviderPublicModel>[],
      source: 'empty',
      errorMessage: res.error,
      statusCode: res.statusCode,
    );
  }

  static Future<List<FeaturedSpecialistModel>> fetchFeaturedSpecialists({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final result = await fetchFeaturedSpecialistsResult(
      limit: limit,
      forceRefresh: forceRefresh,
    );
    return result.data;
  }

  static Future<CachedFetchResult<List<FeaturedSpecialistModel>>>
      fetchFeaturedSpecialistsResult({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _featuredSpecialistsCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return _buildCachedResult(
        data: List<FeaturedSpecialistModel>.from(cached.data),
        source: 'memory_cache',
      );
    }

    final diskCache = _readDiskListCache<FeaturedSpecialistModel>(
      _featuredSpecialistsCacheKey,
      (rows) => rows
          .map(FeaturedSpecialistModel.fromPromoPlacement)
          .toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _featuredSpecialistsCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<FeaturedSpecialistModel>.from(diskCache.data),
        source: 'disk_cache',
      );
    }

    final res = await ApiClient.get(
      '/api/promo/active/?service_type=featured_specialists&limit=$limit',
    );
    if (res.isSuccess && res.data != null) {
      final list = res.data is List
          ? res.data as List
          : (res.data['results'] as List?) ?? [];
      final seenProviderIds = <int>{};
      final parsed = list
          .whereType<Map>()
          .map((item) => FeaturedSpecialistModel.fromPromoPlacement(
                Map<String, dynamic>.from(item),
              ))
          .where((item) =>
              item.providerId > 0 && seenProviderIds.add(item.providerId))
          .toList(growable: false);
      _featuredSpecialistsCache[limit] =
          _CacheEntry<List<FeaturedSpecialistModel>>(
        List<FeaturedSpecialistModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      await _writeDiskListCache(
        _featuredSpecialistsCacheKey,
        _serializeFeaturedSpecialists(parsed),
      );
      return _buildCachedResult(
        data: List<FeaturedSpecialistModel>.from(parsed),
        source: 'network',
      );
    }

    if (cached != null) {
      return _buildCachedResult(
        data: List<FeaturedSpecialistModel>.from(cached.data),
        source: 'memory_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    if (diskCache != null) {
      _featuredSpecialistsCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<FeaturedSpecialistModel>.from(diskCache.data),
        source: 'disk_cache_stale',
        errorMessage: res.error,
        statusCode: res.statusCode,
      );
    }
    return _buildCachedResult(
      data: const <FeaturedSpecialistModel>[],
      source: 'empty',
      errorMessage: res.error,
      statusCode: res.statusCode,
    );
  }

  // ── البانرات الإعلانية ──
  static Future<List<BannerModel>> fetchHomeBanners({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final result = await fetchHomeBannersResult(
      limit: limit,
      forceRefresh: forceRefresh,
    );
    return result.data;
  }

  static Future<CachedFetchResult<List<BannerModel>>> fetchHomeBannersResult({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _homeBannersCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return _buildCachedResult(
        data: List<BannerModel>.from(cached.data),
        source: 'memory_cache',
      );
    }

    final diskCache = _readDiskListCache<BannerModel>(
      _homeBannersCacheKey,
      (rows) => rows.map(BannerModel.fromJson).toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _homeBannersCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<BannerModel>.from(diskCache.data),
        source: 'disk_cache',
      );
    }

    // Promo home banners should not be capped by client-side limit.
    // We fetch all active promo banners, then only use fallback carousel when needed.
    final promoRes = await ApiClient.get('/api/promo/banners/home/');
    final promoFetched = promoRes.isSuccess;
    final promoBanners = (promoRes.isSuccess && promoRes.data != null)
        ? _parseBannerList(promoRes.data)
        : <BannerModel>[];

    List<BannerModel> carouselBanners = const <BannerModel>[];
    bool carouselFetched = false;
    if (promoBanners.length < limit || promoBanners.isEmpty) {
      final carouselLimit = limit;
      final carouselRes =
          await ApiClient.get('/api/promo/home-carousel/?limit=$carouselLimit');
      if (carouselRes.isSuccess && carouselRes.data != null) {
        carouselBanners = _parseBannerList(carouselRes.data);
      }
      carouselFetched = carouselRes.isSuccess;
    }

    final parsed = _mergePrioritizedHomeBanners(
      sponsored: promoBanners,
      organic: carouselBanners,
      limit: limit,
    );

    if (parsed.isNotEmpty) {
      _homeBannersCache[limit] = _CacheEntry<List<BannerModel>>(
        List<BannerModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      await _writeDiskListCache(
          _homeBannersCacheKey, _serializeBanners(parsed));
      return _buildCachedResult(data: parsed, source: 'network');
    }

    // إذا كانت الاستجابة ناجحة من المصدرين لكن بلا بنرات، اعتبرها
    // نتيجة نهائية (لا نرجع كاش قديم) حتى يظهر البنر الافتراضي من Django.
    if (promoFetched && carouselFetched) {
      _homeBannersCache[limit] = _CacheEntry<List<BannerModel>>(
        const <BannerModel>[],
        DateTime.now(),
      );
      await _writeDiskListCache(
          _homeBannersCacheKey, const <Map<String, dynamic>>[]);
      return _buildCachedResult(
        data: const <BannerModel>[],
        source: 'network',
      );
    }

    if (cached != null) {
      return _buildCachedResult(
        data: List<BannerModel>.from(cached.data),
        source: 'memory_cache_stale',
        errorMessage: promoRes.error ??
            (carouselFetched ? null : 'تعذر تحديث البانرات حالياً'),
        statusCode: promoRes.statusCode == 200 ? 0 : promoRes.statusCode,
      );
    }
    if (diskCache != null) {
      _homeBannersCache[limit] = diskCache;
      return _buildCachedResult(
        data: List<BannerModel>.from(diskCache.data),
        source: 'disk_cache_stale',
        errorMessage: promoRes.error ??
            (carouselFetched ? null : 'تعذر تحديث البانرات حالياً'),
        statusCode: promoRes.statusCode == 200 ? 0 : promoRes.statusCode,
      );
    }
    return _buildCachedResult(
      data: const <BannerModel>[],
      source: 'empty',
      errorMessage: promoRes.error ??
          (carouselFetched ? null : 'تعذر تحديث البانرات حالياً'),
      statusCode: promoRes.statusCode == 200 ? 0 : promoRes.statusCode,
    );
  }

  // ── لمحات الصفحة الرئيسية (Spotlights feed) ──
  static Future<List<MediaItemModel>> fetchSpotlightFeed({
    int limit = 16,
    bool forceRefresh = false,
  }) async {
    final result = await fetchSpotlightFeedResult(
      limit: limit,
      forceRefresh: forceRefresh,
    );
    return result.data;
  }

  static Future<CachedFetchResult<List<MediaItemModel>>>
      fetchSpotlightFeedResult({
    int limit = 16,
    bool forceRefresh = false,
  }) async {
    final cached = _spotlightsCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      final copy = List<MediaItemModel>.from(cached.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return _buildCachedResult(data: copy, source: 'memory_cache');
    }

    final diskCache = _readDiskListCache<MediaItemModel>(
      _spotlightsCacheKey,
      (rows) => rows
          .map(
            (row) => MediaItemModel.fromJson(
              row,
              source: row['source'] == MediaItemSource.spotlight.name
                  ? MediaItemSource.spotlight
                  : MediaItemSource.portfolio,
            ),
          )
          .toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _spotlightsCache[limit] = diskCache;
      final copy = List<MediaItemModel>.from(diskCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return _buildCachedResult(data: copy, source: 'disk_cache');
    }

    final responses = await Future.wait<ApiResponse>([
      ApiClient.get('/api/providers/spotlights/feed/?limit=$limit'),
      ApiClient.get('/api/promo/active/?service_type=snapshots&limit=$limit'),
    ]);
    final feedRes = responses[0];
    final snapshotsRes = responses[1];

    // نفس شرط الويب: نحدّث اللمحات فقط إذا كان feed ناجحًا.
    if (feedRes.isSuccess && feedRes.data != null) {
      final feedItems = _extractMapList(feedRes.data)
          .map((row) => MediaItemModel.fromJson(
                row,
                source: MediaItemSource.spotlight,
              ))
          .toList(growable: false);
      final promoItems = (snapshotsRes.isSuccess && snapshotsRes.data != null)
          ? _extractMapList(snapshotsRes.data)
              .map(_snapshotItemFromPlacement)
              .whereType<MediaItemModel>()
              .toList(growable: false)
          : const <MediaItemModel>[];
      final parsed = _mergeSpotlightItems(
        promoItems: promoItems,
        feedItems: feedItems,
        limit: limit,
      );
      _spotlightsCache[limit] = _CacheEntry<List<MediaItemModel>>(
        List<MediaItemModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      await _writeDiskListCache(
          _spotlightsCacheKey, _serializeSpotlights(parsed));
      return _buildCachedResult(
        data: List<MediaItemModel>.from(parsed),
        source: 'network',
      );
    }
    if (cached != null) {
      final copy = List<MediaItemModel>.from(cached.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return _buildCachedResult(
        data: copy,
        source: 'memory_cache_stale',
        errorMessage: feedRes.error ?? snapshotsRes.error,
        statusCode: feedRes.statusCode,
      );
    }
    if (diskCache != null) {
      _spotlightsCache[limit] = diskCache;
      final copy = List<MediaItemModel>.from(diskCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return _buildCachedResult(
        data: copy,
        source: 'disk_cache_stale',
        errorMessage: feedRes.error ?? snapshotsRes.error,
        statusCode: feedRes.statusCode,
      );
    }
    return _buildCachedResult(
      data: const <MediaItemModel>[],
      source: 'empty',
      errorMessage: feedRes.error ?? snapshotsRes.error,
      statusCode: feedRes.statusCode,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchPromoActiveRows({
    required String serviceType,
    int limit = 10,
  }) async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=$serviceType&limit=$limit',
      );
      if (!res.isSuccess || res.data == null) {
        return const <Map<String, dynamic>>[];
      }
      return _extractMapList(res.data);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeService.fetchPromoActiveRows failed ($serviceType)',
        error: error,
        stackTrace: stackTrace,
      );
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPortfolioFeedRows({
    int limit = 10,
  }) async {
    try {
      final res =
          await ApiClient.get('/api/providers/portfolio/feed/?limit=$limit');
      if (!res.isSuccess || res.data == null) {
        return const <Map<String, dynamic>>[];
      }
      return _extractMapList(res.data);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeService.fetchPortfolioFeedRows failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<Map<String, dynamic>?> fetchPromoByAdType({
    required String adType,
    int limit = 1,
  }) async {
    try {
      final res = await ApiClient.get(
          '/api/promo/active/?ad_type=$adType&limit=$limit');
      if (!res.isSuccess || res.data == null) return null;
      final rows = _extractMapList(res.data);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'HomeService.fetchPromoByAdType failed ($adType)',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<void> debugResetCaches() async {
    _categoriesCache = null;
    _featuredProvidersCache.clear();
    _featuredSpecialistsCache.clear();
    _homeBannersCache.clear();
    _spotlightsCache.clear();
    await LocalCacheService.remove(_categoriesCacheKey);
    await LocalCacheService.remove(_featuredProvidersCacheKey);
    await LocalCacheService.remove(_featuredSpecialistsCacheKey);
    await LocalCacheService.remove(_homeBannersCacheKey);
    await LocalCacheService.remove(_spotlightsCacheKey);
  }
}

class HomeCachedData {
  final List<CategoryModel> categories;
  final List<ProviderPublicModel> providers;
  final List<BannerModel> banners;
  final List<MediaItemModel> spotlights;

  const HomeCachedData({
    required this.categories,
    required this.providers,
    required this.banners,
    required this.spotlights,
  });

  bool get hasAnyData =>
      categories.isNotEmpty ||
      providers.isNotEmpty ||
      banners.isNotEmpty ||
      spotlights.isNotEmpty;
}

class CachedFetchResult<T> {
  final T data;
  final String source;
  final String? errorMessage;
  final int statusCode;

  const CachedFetchResult({
    required this.data,
    required this.source,
    this.errorMessage,
    this.statusCode = 200,
  });

  bool get fromCache => source.contains('cache');
  bool get isStaleCache => source.endsWith('_stale');
  bool get isOfflineFallback => isStaleCache && statusCode == 0;
  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;
}

class _CacheEntry<T> {
  final T data;
  final DateTime fetchedAt;

  const _CacheEntry(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }
}
