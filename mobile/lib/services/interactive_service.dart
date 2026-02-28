/// خدمة التفاعلات الاجتماعية — متابعة، متابعيني، مفضلتي
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
import '../models/provider_public_model.dart';
import '../models/user_public_model.dart';
import '../models/media_item_model.dart';

class InteractiveService {
  // ────────────────────────────────────────
  // 📋 جلب قوائم
  // ────────────────────────────────────────

  /// جلب المزودين الذين أتابعهم
  static Future<ListResult<ProviderPublicModel>> fetchFollowing() async {
    final resp = await ApiClient.get('/api/providers/me/following/');
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

  /// جلب المفضلة (معرض أعمال + أضواء)
  static Future<ListResult<MediaItemModel>> fetchFavorites() async {
    // ✅ جلب المعرض والأضواء بالتوازي
    final results = await Future.wait([
      ApiClient.get('/api/providers/me/favorites/'),
      ApiClient.get('/api/providers/me/favorites/spotlights/'),
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

    if (allItems.isEmpty && !portfolioResp.isSuccess && !spotlightResp.isSuccess) {
      return ListResult(error: portfolioResp.error ?? 'خطأ في جلب المفضلة');
    }

    // ترتيب حسب التاريخ (الأحدث أولاً)
    allItems.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

    return ListResult(data: allItems);
  }

  // ────────────────────────────────────────
  // 🔘 إجراءات
  // ────────────────────────────────────────

  /// متابعة مزود
  static Future<bool> followProvider(int providerId) async {
    final resp = await ApiClient.post('/api/providers/$providerId/follow/');
    return resp.isSuccess;
  }

  /// إلغاء متابعة مزود
  static Future<bool> unfollowProvider(int providerId) async {
    final resp = await ApiClient.post('/api/providers/$providerId/unfollow/');
    return resp.isSuccess;
  }

  /// إلغاء حفظ عنصر من المفضلة
  static Future<bool> unsaveItem(MediaItemModel item) async {
    final path = item.source == MediaItemSource.portfolio
        ? '/api/providers/portfolio/${item.id}/unsave/'
        : '/api/providers/spotlights/${item.id}/unsave/';
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
  static Future<ApiResponse> fetchProviderPortfolio(int providerId) {
    return ApiClient.get('/api/providers/$providerId/portfolio/');
  }

  /// جلب أضواء مزود آخر
  static Future<ApiResponse> fetchProviderSpotlights(int providerId) {
    return ApiClient.get('/api/providers/$providerId/spotlights/');
  }

  /// حذف عنصر من المعرض
  static Future<ApiResponse> deletePortfolioItem(int itemId) {
    return ApiClient.delete('/api/providers/me/portfolio/$itemId/');
  }

  /// حذف عنصر من الأضواء
  static Future<ApiResponse> deleteSpotlightItem(int itemId) {
    return ApiClient.delete('/api/providers/me/spotlights/$itemId/');
  }

  /// إعجاب بعنصر معرض
  static Future<bool> likePortfolio(int itemId) async {
    final resp = await ApiClient.post('/api/providers/portfolio/$itemId/like/');
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بعنصر معرض
  static Future<bool> unlikePortfolio(int itemId) async {
    final resp = await ApiClient.post('/api/providers/portfolio/$itemId/unlike/');
    return resp.isSuccess;
  }

  /// حفظ عنصر معرض
  static Future<bool> savePortfolio(int itemId) async {
    final resp = await ApiClient.post('/api/providers/portfolio/$itemId/save/');
    return resp.isSuccess;
  }

  /// إعجاب بعنصر أضواء
  static Future<bool> likeSpotlight(int itemId) async {
    final resp = await ApiClient.post('/api/providers/spotlights/$itemId/like/');
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بعنصر أضواء
  static Future<bool> unlikeSpotlight(int itemId) async {
    final resp = await ApiClient.post('/api/providers/spotlights/$itemId/unlike/');
    return resp.isSuccess;
  }

  /// حفظ عنصر أضواء
  static Future<bool> saveSpotlight(int itemId) async {
    final resp = await ApiClient.post('/api/providers/spotlights/$itemId/save/');
    return resp.isSuccess;
  }

  /// إعجاب بمزود
  static Future<bool> likeProvider(int providerId) async {
    final resp = await ApiClient.post('/api/providers/$providerId/like/');
    return resp.isSuccess;
  }

  /// إلغاء إعجاب بمزود
  static Future<bool> unlikeProvider(int providerId) async {
    final resp = await ApiClient.post('/api/providers/$providerId/unlike/');
    return resp.isSuccess;
  }

  /// جلب تفاصيل مزود
  static Future<ApiResponse> fetchProviderDetail(int providerId) {
    return ApiClient.get('/api/providers/$providerId/');
  }

  /// جلب خدمات مزود
  static Future<ApiResponse> fetchProviderServices(int providerId) {
    return ApiClient.get('/api/providers/$providerId/services/');
  }

  /// جلب إحصائيات مزود
  static Future<ApiResponse> fetchProviderStats(int providerId) {
    return ApiClient.get('/api/providers/$providerId/stats/');
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
