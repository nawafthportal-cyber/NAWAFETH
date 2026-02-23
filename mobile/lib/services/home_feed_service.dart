import '../models/provider.dart';
import '../models/provider_portfolio_item.dart';
import 'providers_api.dart';
import 'promo_api.dart';
import 'reviews_api.dart';

class HomeFeedService {
  HomeFeedService._();

  static final HomeFeedService instance = HomeFeedService._();

  final ProvidersApi _providersApi = ProvidersApi();
  final ReviewsApi _reviewsApi = ReviewsApi();
  final PromoApi _promoApi = PromoApi();

  static const Duration _ttl = Duration(minutes: 3);

  DateTime? _providersAt;
  List<ProviderProfile>? _providersCache;
  Future<List<ProviderProfile>>? _providersInFlight;

  DateTime? _portfolioAt;
  List<ProviderPortfolioItem>? _portfolioCache;
  Future<List<ProviderPortfolioItem>>? _portfolioInFlight;

  DateTime? _bannersAt;
  List<ProviderPortfolioItem>? _bannersCache;
  Future<List<ProviderPortfolioItem>>? _bannersInFlight;

  DateTime? _testimonialsAt;
  List<Map<String, dynamic>>? _testimonialsCache;
  Future<List<Map<String, dynamic>>>? _testimonialsInFlight;

  final Map<String, DateTime> _activePromosAtByKey = {};
  final Map<String, List<Map<String, dynamic>>> _activePromosCacheByKey = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _activePromosInFlightByKey = {};

  bool _isFresh(DateTime? at) {
    if (at == null) return false;
    return DateTime.now().difference(at) <= _ttl;
  }

  String _promoKey({String? city, String? categoryName, int limit = 50}) {
    final c1 = (city ?? '').trim();
    final c2 = (categoryName ?? '').trim();
    return '$c1||$c2||$limit';
  }

  Future<List<Map<String, dynamic>>> _getActivePromosCached({
    String? city,
    String? categoryName,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    final key = _promoKey(city: city, categoryName: categoryName, limit: limit);

    if (!forceRefresh) {
      final at = _activePromosAtByKey[key];
      final cached = _activePromosCacheByKey[key];
      if (cached != null && _isFresh(at)) {
        return cached;
      }

      final inflight = _activePromosInFlightByKey[key];
      if (inflight != null) {
        try {
          return await inflight;
        } catch (_) {
          return const [];
        }
      }
    }

    final future = _promoApi.getActivePromos(
      city: city,
      category: categoryName,
      limit: limit,
    );

    _activePromosInFlightByKey[key] = future;
    try {
      final data = await future;
      _activePromosCacheByKey[key] = data;
      _activePromosAtByKey[key] = DateTime.now();
      return data;
    } catch (_) {
      _activePromosCacheByKey[key] = const [];
      _activePromosAtByKey[key] = DateTime.now();
      return const [];
    } finally {
      _activePromosInFlightByKey.remove(key);
    }
  }

  int? _asIntOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString());
  }

  Future<List<int>> getPromotedProviderIds({
    String? city,
    String? categoryName,
    bool forceRefresh = false,
  }) async {
    final placements = await _getActivePromosCached(
      city: city,
      categoryName: categoryName,
      limit: 60,
      forceRefresh: forceRefresh,
    );

    if (placements.isEmpty) return const [];

    List<int> _collect(String adType) {
      final out = <int>[];
      for (final p in placements) {
        if ((p['ad_type'] ?? '').toString() != adType) continue;
        final id = _asIntOrNull(p['target_provider_id']);
        if (id != null && id > 0) out.add(id);
      }
      return out;
    }

    final ordered = <int>[];
    final seen = <int>{};

    for (final id in _collect('featured_top5')) {
      if (seen.add(id)) ordered.add(id);
    }
    for (final id in _collect('featured_top10')) {
      if (seen.add(id)) ordered.add(id);
    }
    for (final id in _collect('boost_profile')) {
      if (seen.add(id)) ordered.add(id);
    }

    return ordered;
  }

  Future<List<ProviderProfile>> reorderProvidersForPromos({
    required List<ProviderProfile> providers,
    String? city,
    String? categoryName,
    bool forceRefresh = false,
  }) async {
    if (providers.isEmpty) return providers;

    final promotedIds = await getPromotedProviderIds(
      city: city,
      categoryName: categoryName,
      forceRefresh: forceRefresh,
    );
    if (promotedIds.isEmpty) return providers;

    final idsSet = promotedIds.toSet();
    final byId = <int, ProviderProfile>{
      for (final p in providers) p.id: p,
    };

    final promoted = <ProviderProfile>[];
    for (final id in promotedIds) {
      final p = byId[id];
      if (p != null) promoted.add(p);
    }

    final rest = providers.where((p) => !idsSet.contains(p.id)).toList();
    return [...promoted, ...rest];
  }

  List<ProviderProfile> _rankProviders(List<ProviderProfile> providers) {
    final list = [...providers];
    list.sort((a, b) {
      final likesCmp = b.likesCount.compareTo(a.likesCount);
      if (likesCmp != 0) return likesCmp;
      final ratingCmp = b.ratingAvg.compareTo(a.ratingAvg);
      if (ratingCmp != 0) return ratingCmp;
      return b.followersCount.compareTo(a.followersCount);
    });
    return list;
  }

  Future<List<ProviderProfile>> getProviders({bool forceRefresh = false}) async {
    if (
        !forceRefresh &&
        _providersCache != null &&
        _providersCache!.isNotEmpty &&
        _isFresh(_providersAt)) {
      return _providersCache!;
    }
    if (!forceRefresh && _providersInFlight != null) {
      return _providersInFlight!;
    }

    final future = _providersApi.getProviders().then(_rankProviders);
    _providersInFlight = future;
    try {
      final data = await future;
      _providersCache = data;
      _providersAt = DateTime.now();
      return data;
    } finally {
      _providersInFlight = null;
    }
  }

  Future<List<ProviderProfile>> getTopProviders({
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    final providers = await getProviders(forceRefresh: forceRefresh);

    // Bring promoted providers to the top (paid placements).
    // If promos API is not available, this is a no-op.
    final boosted = await reorderProvidersForPromos(
      providers: providers,
      forceRefresh: forceRefresh,
    );

    return boosted.take(limit).toList();
  }

  Future<List<ProviderPortfolioItem>> _getPortfolioPool({bool forceRefresh = false}) async {
    if (
        !forceRefresh &&
        _portfolioCache != null &&
        _portfolioCache!.isNotEmpty &&
        _isFresh(_portfolioAt)) {
      return _portfolioCache!;
    }
    if (!forceRefresh && _portfolioInFlight != null) {
      return _portfolioInFlight!;
    }

    final future = () async {
      final providers = await getTopProviders(limit: 8, forceRefresh: forceRefresh);
      if (providers.isEmpty) return <ProviderPortfolioItem>[];

      final portfolios = await Future.wait(
        providers.map((p) => _providersApi.getProviderPortfolio(p.id)),
      );

      final merged = <ProviderPortfolioItem>[
        for (final list in portfolios) ...list.where((e) => e.fileUrl.trim().isNotEmpty),
      ];
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return merged;
    }();

    _portfolioInFlight = future;
    try {
      final data = await future;
      _portfolioCache = data;
      _portfolioAt = DateTime.now();
      return data;
    } finally {
      _portfolioInFlight = null;
    }
  }

  Future<List<ProviderPortfolioItem>> getBannerItems({
    int limit = 6,
    bool forceRefresh = false,
  }) async {
    // Home banners are a paid feature and must be admin-managed.
    // Do NOT derive them from provider portfolio media.
    if (!forceRefresh && _bannersCache != null && _isFresh(_bannersAt)) {
      return _bannersCache!.take(limit).toList();
    }
    if (!forceRefresh && _bannersInFlight != null) {
      try {
        final data = await _bannersInFlight!;
        return data.take(limit).toList();
      } catch (_) {
        return const [];
      }
    }

    final future = _promoApi.getHomeBanners(limit: limit);
    _bannersInFlight = future;
    try {
      final data = await future;
      _bannersCache = data;
      _bannersAt = DateTime.now();
      return data.take(limit).toList();
    } catch (_) {
      _bannersCache = const [];
      _bannersAt = DateTime.now();
      return const [];
    } finally {
      _bannersInFlight = null;
    }
  }

  Future<List<ProviderPortfolioItem>> getSearchBannerItems({
    int limit = 3,
    String? city,
    String? categoryName,
    bool forceRefresh = false,
  }) async {
    final placements = await _getActivePromosCached(
      city: city,
      categoryName: categoryName,
      limit: 60,
      forceRefresh: forceRefresh,
    );

    if (placements.isEmpty) return const [];

    final out = <ProviderPortfolioItem>[];
    for (final p in placements) {
      if ((p['ad_type'] ?? '').toString() != 'banner_search') continue;
      final assets = p['assets'];
      if (assets is! List) continue;
      for (final raw in assets) {
        if (raw is! Map) continue;
        out.add(ProviderPortfolioItem.fromJson(Map<String, dynamic>.from(raw)));
      }
    }

    if (out.isEmpty) return const [];

    final seen = <int>{};
    final uniq = <ProviderPortfolioItem>[];
    for (final item in out) {
      if (seen.add(item.id)) uniq.add(item);
    }

    return uniq.take(limit).toList();
  }

  Future<List<ProviderPortfolioItem>> getMediaItems({
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    final pool = await _getPortfolioPool(forceRefresh: forceRefresh);
    return pool.take(limit).toList();
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString());
  }

  Future<List<Map<String, dynamic>>> getTestimonials({
    int limit = 8,
    bool forceRefresh = false,
  }) async {
    if (
        !forceRefresh &&
        _testimonialsCache != null &&
        _testimonialsCache!.isNotEmpty &&
        _isFresh(_testimonialsAt)) {
      return _testimonialsCache!.take(limit).toList();
    }
    if (!forceRefresh && _testimonialsInFlight != null) {
      final data = await _testimonialsInFlight!;
      return data.take(limit).toList();
    }

    final future = () async {
      final providers = await getTopProviders(limit: 8, forceRefresh: forceRefresh);
      if (providers.isEmpty) return <Map<String, dynamic>>[];

      final reviewsByProvider = await Future.wait(
        providers.map((p) async {
          final reviews = await _reviewsApi.getProviderReviews(p.id);
          return {'provider': p, 'reviews': reviews};
        }),
      );

      final items = <Map<String, dynamic>>[];
      for (final row in reviewsByProvider) {
        final reviews = (row['reviews'] as List).whereType<Map>().toList();
        for (final raw in reviews) {
          final review = Map<String, dynamic>.from(raw);
          final comment = (review['comment'] ?? '').toString().trim();
          if (comment.isEmpty) continue;
          final rating = (_asInt(review['rating']) ?? 5).clamp(1, 5);
          items.add({
            'name': (review['client_name'] ?? review['client_phone'] ?? 'عميل').toString(),
            'comment': comment,
            'rating': rating,
          });
          if (items.length >= 20) break;
        }
        if (items.length >= 20) break;
      }
      return items;
    }();

    _testimonialsInFlight = future;
    try {
      final data = await future;
      _testimonialsCache = data;
      _testimonialsAt = DateTime.now();
      return data.take(limit).toList();
    } finally {
      _testimonialsInFlight = null;
    }
  }
}
