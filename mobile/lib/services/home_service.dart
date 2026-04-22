import 'api_client.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/featured_specialist_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';
import 'app_logger.dart';

/// خدمة الصفحة الرئيسية — تجلب البيانات من الـ API
class HomeService {
  static const Duration _cacheTtl = Duration(minutes: 15);

  static _CacheEntry<List<CategoryModel>>? _categoriesCache;
  static final Map<int, _CacheEntry<List<ProviderPublicModel>>> _featuredProvidersCache = {};
  static final Map<int, _CacheEntry<List<FeaturedSpecialistModel>>> _featuredSpecialistsCache = {};
  static final Map<int, _CacheEntry<List<BannerModel>>> _homeBannersCache = {};
  static final Map<int, _CacheEntry<List<MediaItemModel>>> _spotlightsCache = {};

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
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static MediaItemModel? _snapshotItemFromPlacement(Map<String, dynamic> placement) {
    final nestedRaw = placement['spotlight_item'];
    final nested = nestedRaw is Map ? Map<String, dynamic>.from(nestedRaw) : null;

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
    final categories = _categoriesCache?.data ?? const <CategoryModel>[];
    final providers = _featuredProvidersCache[providersLimit]?.data ?? const <ProviderPublicModel>[];
    final banners = _homeBannersCache[bannersLimit]?.data ?? const <BannerModel>[];
    final spotlights = List<MediaItemModel>.from(
      _spotlightsCache[spotlightsLimit]?.data ?? const <MediaItemModel>[],
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
  static Future<List<CategoryModel>> fetchCategories({bool forceRefresh = false}) async {
    final cached = _categoriesCache;
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return List<CategoryModel>.from(cached.data);
    }

    final res = await ApiClient.get('/api/providers/categories/');
    if (res.isSuccess && res.data != null) {
      final list = res.data is List ? res.data as List : (res.data['results'] as List?) ?? [];
      final parsed = list.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
      _categoriesCache = _CacheEntry<List<CategoryModel>>(
        List<CategoryModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return parsed;
    }
    if (cached != null) {
      return List<CategoryModel>.from(cached.data);
    }
    return [];
  }

  // ── مزودو الخدمة (مميزون / أحدث) ──
  static Future<List<ProviderPublicModel>> fetchFeaturedProviders({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _featuredProvidersCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return List<ProviderPublicModel>.from(cached.data);
    }

    final res = await ApiClient.get('/api/providers/list/?page_size=$limit');
    if (res.isSuccess && res.data != null) {
      final list = res.data is List ? res.data as List : (res.data['results'] as List?) ?? [];
      final parsed = list.map((e) => ProviderPublicModel.fromJson(e as Map<String, dynamic>)).toList();
      _featuredProvidersCache[limit] = _CacheEntry<List<ProviderPublicModel>>(
        List<ProviderPublicModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return parsed;
    }
    if (cached != null) {
      return List<ProviderPublicModel>.from(cached.data);
    }
    return [];
  }

  static Future<List<FeaturedSpecialistModel>> fetchFeaturedSpecialists({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _featuredSpecialistsCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return List<FeaturedSpecialistModel>.from(cached.data);
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
          .where((item) => item.providerId > 0 && seenProviderIds.add(item.providerId))
          .toList(growable: false);
      _featuredSpecialistsCache[limit] = _CacheEntry<List<FeaturedSpecialistModel>>(
        List<FeaturedSpecialistModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return List<FeaturedSpecialistModel>.from(parsed);
    }

    if (cached != null) {
      return List<FeaturedSpecialistModel>.from(cached.data);
    }
    return [];
  }

  // ── البانرات الإعلانية ──
  static Future<List<BannerModel>> fetchHomeBanners({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _homeBannersCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return List<BannerModel>.from(cached.data);
    }

    // Promo home banners should not be capped by client-side limit.
    // We fetch all active promo banners, then only use fallback carousel when needed.
    final promoRes = await ApiClient.get('/api/promo/banners/home/');
    final promoFetched = promoRes.isSuccess;
    final promoBanners = (promoRes.isSuccess && promoRes.data != null)
      ? _parseBannerList(promoRes.data)
        : <BannerModel>[];

    final remaining = limit > promoBanners.length ? limit - promoBanners.length : 0;
    final fallbackLimit = remaining > 0 ? remaining : 0;

    List<BannerModel> carouselBanners = const <BannerModel>[];
    bool carouselFetched = false;
    if (fallbackLimit > 0 || promoBanners.isEmpty) {
      final carouselLimit = promoBanners.isEmpty ? limit : fallbackLimit;
      final carouselRes = await ApiClient.get('/api/promo/home-carousel/?limit=$carouselLimit');
      if (carouselRes.isSuccess && carouselRes.data != null) {
        carouselBanners = _parseBannerList(carouselRes.data);
      }
      carouselFetched = carouselRes.isSuccess;
    }

    final parsed = _dedupeBanners(<BannerModel>[
      ...promoBanners,
      ...carouselBanners,
    ]);

    if (parsed.isNotEmpty) {
      _homeBannersCache[limit] = _CacheEntry<List<BannerModel>>(
        List<BannerModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return parsed;
    }

    // إذا كانت الاستجابة ناجحة من المصدرين لكن بلا بنرات، اعتبرها
    // نتيجة نهائية (لا نرجع كاش قديم) حتى يظهر البنر الافتراضي من Django.
    if (promoFetched && carouselFetched) {
      _homeBannersCache[limit] = _CacheEntry<List<BannerModel>>(
        const <BannerModel>[],
        DateTime.now(),
      );
      return const <BannerModel>[];
    }

    if (cached != null) {
      return List<BannerModel>.from(cached.data);
    }
    return [];
  }

  // ── لمحات الصفحة الرئيسية (Spotlights feed) ──
  static Future<List<MediaItemModel>> fetchSpotlightFeed({
    int limit = 16,
    bool forceRefresh = false,
  }) async {
    final cached = _spotlightsCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      final copy = List<MediaItemModel>.from(cached.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return copy;
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
      return List<MediaItemModel>.from(parsed);
    }
    if (cached != null) {
      final copy = List<MediaItemModel>.from(cached.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return copy;
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> fetchPromoActiveRows({
    required String serviceType,
    int limit = 10,
  }) async {
    try {
      final res = await ApiClient.get(
        '/api/promo/active/?service_type=$serviceType&limit=$limit',
      );
      if (!res.isSuccess || res.data == null) return const <Map<String, dynamic>>[];
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
      final res = await ApiClient.get('/api/providers/portfolio/feed/?limit=$limit');
      if (!res.isSuccess || res.data == null) return const <Map<String, dynamic>>[];
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
      final res = await ApiClient.get('/api/promo/active/?ad_type=$adType&limit=$limit');
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
      categories.isNotEmpty || providers.isNotEmpty || banners.isNotEmpty || spotlights.isNotEmpty;
}

class _CacheEntry<T> {
  final T data;
  final DateTime fetchedAt;

  const _CacheEntry(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }
}
