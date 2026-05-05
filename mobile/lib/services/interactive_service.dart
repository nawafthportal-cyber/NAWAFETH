/// خدمة التفاعلات الاجتماعية — متابعة، متابعيني، مفضلتي
///
/// جميع العمليات معزولة حسب الوضع (عميل/مزود) عبر ?mode=
///
/// الـ Endpoints:
/// - GET  /api/providers/me/following/          → المزودين اللي أتابعهم
/// - GET  /api/providers/me/followers/          → المستخدمين اللي يتابعوني (مزود فقط)
/// - GET  /api/providers/me/favorites/          → عناصر المعرض المحفوظة
/// - GET  /api/providers/me/favorites/spotlights/ → عناصر الأضواء المحفوظة
/// - POST /api/providers/{id}/follow/           → متابعة مزود
/// - POST /api/providers/{id}/unfollow/         → إلغاء متابعة مزود
/// - POST /api/providers/portfolio/{id}/unsave/ → إلغاء حفظ عنصر معرض
/// - POST /api/providers/spotlights/{id}/unsave/→ إلغاء حفظ عنصر أضواء
library;

import 'api_client.dart';
import 'account_mode_service.dart';
import 'auth_service.dart';
import 'local_cache_service.dart';
import '../models/provider_public_model.dart';
import '../models/user_public_model.dart';
import '../models/media_item_model.dart';

class InteractiveService {
  static const Duration _cacheTtl = Duration(minutes: 10);

  static final Map<String, _ListCacheEntry<ProviderPublicModel>>
      _followingCache = <String, _ListCacheEntry<ProviderPublicModel>>{};
  static final Map<String, _ListCacheEntry<UserPublicModel>> _followersCache =
      <String, _ListCacheEntry<UserPublicModel>>{};
  static final Map<String, _ListCacheEntry<MediaItemModel>> _favoritesCache =
      <String, _ListCacheEntry<MediaItemModel>>{};

  /// إضافة ?mode= إلى المسار
  static Future<String> _withMode(String path) async {
    final mode = await AccountModeService.apiMode();
    return path.contains('?') ? '$path&mode=$mode' : '$path?mode=$mode';
  }

  static String _contentBase(MediaItemSource source) {
    return source == MediaItemSource.portfolio
        ? '/api/providers/portfolio/'
        : '/api/providers/spotlights/';
  }

  static String _contentCommentsPath(MediaItemModel item, [String suffix = '']) {
    return '${_contentBase(item.source)}${item.id}/comments/$suffix';
  }
  // ────────────────────────────────────────
  // 📋 جلب قوائم
  // ────────────────────────────────────────

  /// جلب المزودين الذين أتابعهم (معزول حسب الوضع)
  static Future<ListResult<ProviderPublicModel>> fetchFollowing() async {
    final result = await fetchFollowingResult();
    return ListResult(
      data: result.data,
      error: result.hasError ? result.errorMessage : null,
    );
  }

  static Future<CachedListResult<ProviderPublicModel>> fetchFollowingResult({
    bool forceRefresh = false,
  }) async {
    final scope = await _cacheScope();
    final cacheKey = 'interactive_following_$scope';
    final memoryCache = _followingCache[scope];
    if (!forceRefresh &&
        memoryCache != null &&
        memoryCache.isFresh(_cacheTtl)) {
      return memoryCache.toResult(source: 'memory_cache');
    }

    final diskCache = await _readDiskListCache<ProviderPublicModel>(
      cacheKey,
      (rows) => rows.map(ProviderPublicModel.fromJson).toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _followingCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(source: 'disk_cache');
    }

    final path = await _withMode('/api/providers/me/following/');
    final resp = await ApiClient.get(path);
    if (resp.isSuccess) {
      final items = _parseList(resp)
          .map((entry) => ProviderPublicModel.fromJson(entry))
          .toList(growable: false);
      final result = CachedListResult<ProviderPublicModel>(
        data: items,
        source: 'network',
      );
      _followingCache[scope] = _ListCacheEntry(items, DateTime.now());
      await _writeDiskListCache(
        cacheKey,
        items.map(_serializeProvider).toList(growable: false),
      );
      return result;
    }

    if (memoryCache != null) {
      return memoryCache.toResult(
        source: 'memory_cache_stale',
        errorMessage: resp.error ?? 'تعذر تحديث قائمة المتابَعين الآن',
        statusCode: resp.statusCode,
      );
    }
    if (diskCache != null) {
      _followingCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: resp.error ?? 'تعذر تحديث قائمة المتابَعين الآن',
        statusCode: resp.statusCode,
      );
    }
    return CachedListResult<ProviderPublicModel>(
      data: const <ProviderPublicModel>[],
      source: 'empty',
      errorMessage: resp.error ?? 'خطأ في جلب المتابَعين',
      statusCode: resp.statusCode,
    );
  }

  /// جلب المستخدمين المتابعين لي (مزود فقط)
  static Future<ListResult<UserPublicModel>> fetchFollowers() async {
    final result = await fetchFollowersResult();
    return ListResult(
      data: result.data,
      error: result.hasError ? result.errorMessage : null,
    );
  }

  static Future<CachedListResult<UserPublicModel>> fetchFollowersResult({
    bool forceRefresh = false,
  }) async {
    final scope = await _cacheScope();
    final cacheKey = 'interactive_followers_$scope';
    final memoryCache = _followersCache[scope];
    if (!forceRefresh &&
        memoryCache != null &&
        memoryCache.isFresh(_cacheTtl)) {
      return memoryCache.toResult(source: 'memory_cache');
    }

    final diskCache = await _readDiskListCache<UserPublicModel>(
      cacheKey,
      (rows) => rows.map(UserPublicModel.fromJson).toList(growable: false),
    );
    if (!forceRefresh && diskCache != null && diskCache.isFresh(_cacheTtl)) {
      _followersCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(source: 'disk_cache');
    }

    final path = await _withMode('/api/providers/me/followers/');
    final resp = await ApiClient.get(path);
    if (resp.isSuccess) {
      final items = _parseList(resp)
          .map((entry) => UserPublicModel.fromJson(entry))
          .toList(growable: false);
      final result = CachedListResult<UserPublicModel>(
        data: items,
        source: 'network',
      );
      _followersCache[scope] = _ListCacheEntry(items, DateTime.now());
      await _writeDiskListCache(
        cacheKey,
        items.map(_serializeUser).toList(growable: false),
      );
      return result;
    }

    if (memoryCache != null) {
      return memoryCache.toResult(
        source: 'memory_cache_stale',
        errorMessage: resp.error ?? 'تعذر تحديث قائمة المتابعين الآن',
        statusCode: resp.statusCode,
      );
    }
    if (diskCache != null) {
      _followersCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: resp.error ?? 'تعذر تحديث قائمة المتابعين الآن',
        statusCode: resp.statusCode,
      );
    }
    return CachedListResult<UserPublicModel>(
      data: const <UserPublicModel>[],
      source: 'empty',
      errorMessage: resp.error ?? 'خطأ في جلب المتابعين',
      statusCode: resp.statusCode,
    );
  }

  /// جلب متابعين مزود محدد (عام)
  static Future<ListResult<UserPublicModel>> fetchProviderFollowers(
    int providerId, {
    bool scopeAll = false,
  }) async {
    var path = await _withMode('/api/providers/$providerId/followers/');
    if (scopeAll) {
      path = '$path&scope=all';
    }
    final resp = await ApiClient.get(path);
    if (!resp.isSuccess) {
      return ListResult(error: resp.error ?? 'خطأ في جلب متابعين المزود');
    }

    final list = _parseList(resp);
    final items = list.map((e) => UserPublicModel.fromJson(e)).toList();
    return ListResult(data: items);
  }

  /// جلب المزودين الذين يتابعهم مزود محدد (عام)
  static Future<ListResult<ProviderPublicModel>> fetchProviderFollowing(
    int providerId, {
    bool scopeAll = false,
  }) async {
    var path = await _withMode('/api/providers/$providerId/following/');
    if (scopeAll) {
      path = '$path&scope=all';
    }
    final resp = await ApiClient.get(path);
    if (!resp.isSuccess) {
      return ListResult(error: resp.error ?? 'خطأ في جلب قائمة المتابَعين');
    }

    final list = _parseList(resp);
    final items = list.map((e) => ProviderPublicModel.fromJson(e)).toList();
    return ListResult(data: items);
  }

  /// جلب المفضلة (معرض أعمال + أضواء) — معزول حسب الوضع
  static Future<ListResult<MediaItemModel>> fetchFavorites() async {
    final result = await fetchFavoritesResult();
    return ListResult(
      data: result.data,
      error: result.hasError ? result.errorMessage : null,
    );
  }

  static Future<CachedListResult<MediaItemModel>> fetchFavoritesResult({
    bool forceRefresh = false,
  }) async {
    final scope = await _cacheScope();
    final cacheKey = 'interactive_favorites_$scope';
    final memoryCache = _favoritesCache[scope];
    if (!forceRefresh &&
        memoryCache != null &&
        memoryCache.isFresh(_cacheTtl)) {
      final copy = List<MediaItemModel>.from(memoryCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return memoryCache.toResult(
        source: 'memory_cache',
        dataOverride: copy,
      );
    }

    final diskCache = await _readDiskListCache<MediaItemModel>(
      cacheKey,
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
      _favoritesCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      final copy = List<MediaItemModel>.from(diskCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return diskCache.copyWith(
        source: 'disk_cache',
        dataOverride: copy,
      );
    }

    final mode = await AccountModeService.apiMode();
    final results = await Future.wait([
      ApiClient.get('/api/providers/me/favorites/?mode=$mode'),
      ApiClient.get('/api/providers/me/favorites/spotlights/?mode=$mode'),
    ]);

    final portfolioResp = results[0];
    final spotlightResp = results[1];

    final List<MediaItemModel> allItems = [];

    // عناصر المعرض
    if (portfolioResp.isSuccess) {
      final pList = _parseList(portfolioResp);
      allItems.addAll(pList.map(
        (e) => MediaItemModel.fromJson(e, source: MediaItemSource.portfolio),
      ));
    }

    // عناصر الأضواء
    if (spotlightResp.isSuccess) {
      final sList = _parseList(spotlightResp);
      allItems.addAll(sList.map(
        (e) => MediaItemModel.fromJson(e, source: MediaItemSource.spotlight),
      ));
    }

    if (portfolioResp.isSuccess || spotlightResp.isSuccess) {
      allItems.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      final immutable = List<MediaItemModel>.unmodifiable(allItems);
      final result = CachedListResult<MediaItemModel>(
        data: immutable,
        source: 'network',
        errorMessage: (!portfolioResp.isSuccess || !spotlightResp.isSuccess)
            ? (portfolioResp.error ?? spotlightResp.error)
            : null,
        statusCode:
            (!portfolioResp.isSuccess && portfolioResp.statusCode != 200)
                ? portfolioResp.statusCode
                : spotlightResp.statusCode,
      );
      _favoritesCache[scope] = _ListCacheEntry(immutable, DateTime.now());
      await _writeDiskListCache(
        cacheKey,
        immutable.map(_serializeMediaItem).toList(growable: false),
      );
      return result;
    }

    if (memoryCache != null) {
      final copy = List<MediaItemModel>.from(memoryCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return memoryCache.toResult(
        source: 'memory_cache_stale',
        errorMessage: portfolioResp.error ??
            spotlightResp.error ??
            'تعذر تحديث المفضلة الآن',
        statusCode: portfolioResp.statusCode != 200
            ? portfolioResp.statusCode
            : spotlightResp.statusCode,
        dataOverride: copy,
      );
    }
    if (diskCache != null) {
      _favoritesCache[scope] = _ListCacheEntry(
        diskCache.data,
        diskCache.cachedAt ?? DateTime.now(),
      );
      final copy = List<MediaItemModel>.from(diskCache.data);
      MediaItemModel.applyInteractionOverrides(copy);
      return diskCache.copyWith(
        source: 'disk_cache_stale',
        errorMessage: portfolioResp.error ??
            spotlightResp.error ??
            'تعذر تحديث المفضلة الآن',
        statusCode: portfolioResp.statusCode != 200
            ? portfolioResp.statusCode
            : spotlightResp.statusCode,
        dataOverride: copy,
      );
    }
    return CachedListResult<MediaItemModel>(
      data: const <MediaItemModel>[],
      source: 'empty',
      errorMessage:
          portfolioResp.error ?? spotlightResp.error ?? 'خطأ في جلب المفضلة',
      statusCode: portfolioResp.statusCode != 200
          ? portfolioResp.statusCode
          : spotlightResp.statusCode,
    );
  }

  // ────────────────────────────────────────
  // 🔘 إجراءات
  // ────────────────────────────────────────

  /// متابعة مزود (معزول حسب الوضع)
  static Future<bool> followProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/follow/');
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFollowingCache();
    }
    return resp.isSuccess;
  }

  /// إلغاء متابعة مزود (معزول حسب الوضع)
  static Future<bool> unfollowProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/unfollow/');
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFollowingCache();
    }
    return resp.isSuccess;
  }

  /// إلغاء حفظ عنصر من المفضلة (معزول حسب الوضع)
  static Future<bool> unsaveItem(MediaItemModel item) async {
    final basePath = item.source == MediaItemSource.portfolio
        ? '/api/providers/portfolio/${item.id}/unsave/'
        : '/api/providers/spotlights/${item.id}/unsave/';
    final path = await _withMode(basePath);
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFavoritesCache();
    }
    return resp.isSuccess;
  }

  // ────────────────────────────────────────
  // 📷 البورتفوليو والأضواء — CRUD
  // ────────────────────────────────────────

  /// جلب معرض أعمالي
  static Future<ApiResponse> fetchMyPortfolio() {
    return ApiClient.get('/api/providers/me/portfolio/');
  }

  /// جلب أضوائي
  static Future<ApiResponse> fetchMySpotlights() {
    return ApiClient.get('/api/providers/me/spotlights/');
  }

  /// جلب معرض أعمال مزود آخر
  static Future<ApiResponse> fetchProviderPortfolio(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/portfolio/');
    return ApiClient.get(path);
  }

  /// جلب أضواء مزود آخر
  static Future<ApiResponse> fetchProviderSpotlights(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/spotlights/');
    return ApiClient.get(path);
  }

  /// حذف عنصر من المعرض
  static Future<ApiResponse> deletePortfolioItem(int itemId) {
    return ApiClient.delete('/api/providers/me/portfolio/$itemId/');
  }

  /// حذف عنصر من الأضواء
  static Future<ApiResponse> deleteSpotlightItem(int itemId) {
    return ApiClient.delete('/api/providers/me/spotlights/$itemId/');
  }

  /// إعجاب بعنصر معرض (معزول حسب الوضع)
  static Future<bool> likePortfolio(int itemId) async {
    final path = await _withMode('/api/providers/portfolio/$itemId/like/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بعنصر معرض (معزول حسب الوضع)
  static Future<bool> unlikePortfolio(int itemId) async {
    final path = await _withMode('/api/providers/portfolio/$itemId/unlike/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// حفظ عنصر معرض (معزول حسب الوضع)
  static Future<bool> savePortfolio(int itemId) async {
    final path = await _withMode('/api/providers/portfolio/$itemId/save/');
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFavoritesCache();
    }
    return resp.isSuccess;
  }

  /// إعجاب بعنصر أضواء (معزول حسب الوضع)
  static Future<bool> likeSpotlight(int itemId) async {
    final path = await _withMode('/api/providers/spotlights/$itemId/like/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بعنصر أضواء (معزول حسب الوضع)
  static Future<bool> unlikeSpotlight(int itemId) async {
    final path = await _withMode('/api/providers/spotlights/$itemId/unlike/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// حفظ عنصر أضواء (معزول حسب الوضع)
  static Future<bool> saveSpotlight(int itemId) async {
    final path = await _withMode('/api/providers/spotlights/$itemId/save/');
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFavoritesCache();
    }
    return resp.isSuccess;
  }

  /// إلغاء حفظ عنصر أضواء (معزول حسب الوضع)
  static Future<bool> unsaveSpotlight(int itemId) async {
    final path = await _withMode('/api/providers/spotlights/$itemId/unsave/');
    final resp = await ApiClient.post(path);
    if (resp.isSuccess) {
      await _clearFavoritesCache();
    }
    return resp.isSuccess;
  }

  static Future<ApiResponse> fetchComments(
    MediaItemModel item, {
    int limit = 50,
  }) async {
    final path = await _withMode('${_contentCommentsPath(item)}?limit=$limit');
    return ApiClient.get(path, forceRefresh: true);
  }

  static Future<ApiResponse> createComment(
    MediaItemModel item, {
    required String body,
    int? parentId,
  }) async {
    final path = await _withMode(_contentCommentsPath(item));
    return ApiClient.post(
      path,
      body: {
        'body': body,
        if (parentId != null) 'parent': parentId,
      },
    );
  }

  static Future<ApiResponse> deleteComment(
    MediaItemModel item,
    int commentId,
  ) async {
    final path = await _withMode(_contentCommentsPath(item, '$commentId/'));
    return ApiClient.delete(path);
  }

  static Future<ApiResponse> likeComment(
    MediaItemModel item,
    int commentId,
  ) async {
    final path = await _withMode(_contentCommentsPath(item, '$commentId/like/'));
    return ApiClient.post(path);
  }

  static Future<ApiResponse> unlikeComment(
    MediaItemModel item,
    int commentId,
  ) async {
    final path = await _withMode(_contentCommentsPath(item, '$commentId/unlike/'));
    return ApiClient.post(path);
  }

  static Future<ApiResponse> reportComment(
    MediaItemModel item,
    int commentId, {
    required String reason,
    String details = '',
  }) async {
    final path = await _withMode(_contentCommentsPath(item, '$commentId/report/'));
    return ApiClient.post(
      path,
      body: {
        'reason': reason,
        'details': details,
      },
    );
  }

  /// إعجاب بمزود (معزول حسب الوضع)
  static Future<bool> likeProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/like/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بمزود (معزول حسب الوضع)
  static Future<bool> unlikeProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/unlike/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// جلب تفاصيل مزود
  static Future<ApiResponse> fetchProviderDetail(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/');
    return ApiClient.get(path);
  }

  /// جلب خدمات مزود
  static Future<ApiResponse> fetchProviderServices(int providerId) {
    return ApiClient.get('/api/providers/$providerId/services/');
  }

  /// جلب إحصائيات مزود
  static Future<ApiResponse> fetchProviderStats(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/stats/');
    return ApiClient.get(path);
  }

  // ────────────────────────────────────────
  // 🛠️ مساعدات داخلية
  // ────────────────────────────────────────

  /// تحليل الاستجابة كقائمة — يدعم paginated و flat
  static List<Map<String, dynamic>> _parseList(ApiResponse resp) {
    final data = resp.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    if (data is Map && data.containsKey('results')) {
      return (data['results'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<String> _cacheScope() async {
    final mode = await AccountModeService.apiMode();
    final userId = await AuthService.getUserId();
    return '${userId ?? 0}_$mode';
  }

  static Future<CachedListResult<T>?> _readDiskListCache<T>(
    String key,
    List<T> Function(List<Map<String, dynamic>> rows) parser,
  ) async {
    final envelope = await LocalCacheService.readJson(key);
    final payload = envelope?.payload;
    if (payload is! List) {
      return null;
    }
    final rows = payload
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return CachedListResult<T>(
      data: parser(rows),
      source: 'disk_cache',
      cachedAt: envelope!.cachedAt.toLocal(),
    );
  }

  static Future<void> _writeDiskListCache(
    String key,
    List<Map<String, dynamic>> rows,
  ) {
    return LocalCacheService.writeJson(key, rows);
  }

  static Future<void> _clearFollowingCache() async {
    final scope = await _cacheScope();
    _followingCache.remove(scope);
    await LocalCacheService.remove('interactive_following_$scope');
  }

  static Future<void> _clearFavoritesCache() async {
    final scope = await _cacheScope();
    _favoritesCache.remove(scope);
    await LocalCacheService.remove('interactive_favorites_$scope');
  }

  static Future<void> debugResetCaches() async {
    _followingCache.clear();
    _followersCache.clear();
    _favoritesCache.clear();
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

  static Map<String, dynamic> _serializeUser(UserPublicModel user) {
    return {
      'id': user.id,
      'username': user.username,
      'display_name': user.displayName,
      'provider_id': user.providerId,
      'profile_image': user.profileImage,
      'follow_role_context': user.followRoleContext,
    };
  }

  static Map<String, dynamic> _serializeMediaItem(MediaItemModel item) {
    return {
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
    };
  }
}

/// نتيجة عملية جلب قائمة
class ListResult<T> {
  final List<T>? data;
  final String? error;

  ListResult({this.data, this.error});

  bool get isSuccess => data != null;
  List<T> get items => data ?? [];
  bool get isEmpty => items.isEmpty;
}

class CachedListResult<T> {
  final List<T> data;
  final String source;
  final String? errorMessage;
  final int statusCode;
  final DateTime? cachedAt;

  const CachedListResult({
    required this.data,
    required this.source,
    this.errorMessage,
    this.statusCode = 200,
    this.cachedAt,
  });

  bool get fromCache => source.contains('cache');
  bool get isStaleCache => source.endsWith('_stale');
  bool get isOfflineFallback => isStaleCache && statusCode == 0;
  bool get hasError => (errorMessage ?? '').trim().isNotEmpty;

  bool isFresh(Duration ttl) {
    final value = cachedAt;
    if (value == null) {
      return false;
    }
    return DateTime.now().difference(value) <= ttl;
  }

  CachedListResult<T> copyWith({
    List<T>? dataOverride,
    String? source,
    String? errorMessage,
    int? statusCode,
  }) {
    return CachedListResult<T>(
      data: dataOverride ?? List<T>.from(data),
      source: source ?? this.source,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
      cachedAt: cachedAt,
    );
  }
}

class _ListCacheEntry<T> {
  final List<T> data;
  final DateTime fetchedAt;

  const _ListCacheEntry(this.data, this.fetchedAt);

  bool isFresh(Duration ttl) {
    return DateTime.now().difference(fetchedAt) <= ttl;
  }

  CachedListResult<T> toResult({
    required String source,
    String? errorMessage,
    int statusCode = 200,
    List<T>? dataOverride,
  }) {
    return CachedListResult<T>(
      data: dataOverride ?? List<T>.from(data),
      source: source,
      errorMessage: errorMessage,
      statusCode: statusCode,
      cachedAt: fetchedAt,
    );
  }
}
