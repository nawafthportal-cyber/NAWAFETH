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
import '../models/provider_public_model.dart';
import '../models/user_public_model.dart';
import '../models/media_item_model.dart';

class InteractiveService {
  /// إضافة ?mode= إلى المسار
  static Future<String> _withMode(String path) async {
    final mode = await AccountModeService.apiMode();
    return path.contains('?') ? '$path&mode=$mode' : '$path?mode=$mode';
  }
  // ────────────────────────────────────────
  // 📋 جلب قوائم
  // ────────────────────────────────────────

  /// جلب المزودين الذين أتابعهم (معزول حسب الوضع)
  static Future<ListResult<ProviderPublicModel>> fetchFollowing() async {
    final path = await _withMode('/api/providers/me/following/');
    final resp = await ApiClient.get(path);
    if (!resp.isSuccess) {
      return ListResult(error: resp.error ?? 'خطأ في جلب المتابَعين');
    }

    final list = _parseList(resp);
    final items = list.map((e) => ProviderPublicModel.fromJson(e)).toList();
    return ListResult(data: items);
  }

  /// جلب المستخدمين المتابعين لي (مزود فقط)
  static Future<ListResult<UserPublicModel>> fetchFollowers() async {
    final resp = await ApiClient.get('/api/providers/me/followers/');
    if (!resp.isSuccess) {
      return ListResult(error: resp.error ?? 'خطأ في جلب المتابعين');
    }

    final list = _parseList(resp);
    final items = list.map((e) => UserPublicModel.fromJson(e)).toList();
    return ListResult(data: items);
  }

  /// جلب متابعين مزود محدد (عام)
  static Future<ListResult<UserPublicModel>> fetchProviderFollowers(
    int providerId,
  ) async {
    final path = await _withMode('/api/providers/$providerId/followers/');
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
    int providerId,
  ) async {
    final path = await _withMode('/api/providers/$providerId/following/');
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
    final mode = await AccountModeService.apiMode();
    // ✅ جلب المعرض والأضواء بالتوازي مع الوضع
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

    if (allItems.isEmpty &&
        !portfolioResp.isSuccess &&
        !spotlightResp.isSuccess) {
      return ListResult(error: portfolioResp.error ?? 'خطأ في جلب المفضلة');
    }

    // ترتيب حسب التاريخ (الأحدث أولاً)
    allItems.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

    return ListResult(data: allItems);
  }

  // ────────────────────────────────────────
  // 🔘 إجراءات
  // ────────────────────────────────────────

  /// متابعة مزود (معزول حسب الوضع)
  static Future<bool> followProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/follow/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// إلغاء متابعة مزود (معزول حسب الوضع)
  static Future<bool> unfollowProvider(int providerId) async {
    final path = await _withMode('/api/providers/$providerId/unfollow/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
  }

  /// إلغاء حفظ عنصر من المفضلة (معزول حسب الوضع)
  static Future<bool> unsaveItem(MediaItemModel item) async {
    final basePath = item.source == MediaItemSource.portfolio
        ? '/api/providers/portfolio/${item.id}/unsave/'
        : '/api/providers/spotlights/${item.id}/unsave/';
    final path = await _withMode(basePath);
    final resp = await ApiClient.post(path);
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
    return resp.isSuccess;
  }

  /// إلغاء حفظ عنصر أضواء (معزول حسب الوضع)
  static Future<bool> unsaveSpotlight(int itemId) async {
    final path = await _withMode('/api/providers/spotlights/$itemId/unsave/');
    final resp = await ApiClient.post(path);
    return resp.isSuccess;
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
