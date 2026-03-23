import 'api_client.dart';
import '../models/category_model.dart';
import '../models/banner_model.dart';
import '../models/provider_public_model.dart';
import '../models/media_item_model.dart';

/// خدمة الصفحة الرئيسية — تجلب البيانات من الـ API
class HomeService {
  static const Duration _cacheTtl = Duration(minutes: 2);

  static _CacheEntry<List<CategoryModel>>? _categoriesCache;
  static final Map<int, _CacheEntry<List<ProviderPublicModel>>> _featuredProvidersCache = {};
  static final Map<int, _CacheEntry<List<BannerModel>>> _homeBannersCache = {};
  static final Map<int, _CacheEntry<List<MediaItemModel>>> _spotlightsCache = {};

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

  // ── البانرات الإعلانية ──
  static Future<List<BannerModel>> fetchHomeBanners({
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final cached = _homeBannersCache[limit];
    if (!forceRefresh && cached != null && cached.isFresh(_cacheTtl)) {
      return List<BannerModel>.from(cached.data);
    }

    List<BannerModel> parseBannerList(dynamic data) {
      final list = data is List ? data : const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(BannerModel.fromJson)
          .where((banner) => (banner.mediaUrl ?? '').isNotEmpty)
          .toList();
    }

    // Promo home banners should not be capped by client-side limit.
    // We fetch all active promo banners, then only use fallback carousel when needed.
    final promoRes = await ApiClient.get('/api/promo/banners/home/');
    final promoBanners = (promoRes.isSuccess && promoRes.data != null)
        ? parseBannerList(promoRes.data)
        : <BannerModel>[];

    final remaining = limit > promoBanners.length ? limit - promoBanners.length : 0;
    final fallbackLimit = remaining > 0 ? remaining : 0;

    List<BannerModel> carouselBanners = const <BannerModel>[];
    if (fallbackLimit > 0 || promoBanners.isEmpty) {
      final carouselLimit = promoBanners.isEmpty ? limit : fallbackLimit;
      final carouselRes = await ApiClient.get('/api/promo/home-carousel/?limit=$carouselLimit');
      if (carouselRes.isSuccess && carouselRes.data != null) {
        carouselBanners = parseBannerList(carouselRes.data);
      }
    }

    final parsed = <BannerModel>[
      ...promoBanners,
      ...carouselBanners,
    ];

    if (parsed.isNotEmpty) {
      _homeBannersCache[limit] = _CacheEntry<List<BannerModel>>(
        List<BannerModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return parsed;
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

    final res = await ApiClient.get('/api/providers/spotlights/feed/?limit=$limit');
    if (res.isSuccess && res.data != null) {
      final list = res.data is List ? res.data as List : (res.data['results'] as List?) ?? [];
      final parsed = list
          .map((e) => MediaItemModel.fromJson(e as Map<String, dynamic>, source: MediaItemSource.spotlight))
          .toList();
      _spotlightsCache[limit] = _CacheEntry<List<MediaItemModel>>(
        List<MediaItemModel>.unmodifiable(parsed),
        DateTime.now(),
      );
      return parsed;
    }
    if (cached != null) {
      final copy = List<MediaItemModel>.from(cached.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return copy;
    }
    return [];
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
