/// خدمة البروفايل — جلب وتحديث بيانات المستخدم والمزود
library;

import '../models/user_profile.dart';
import '../models/provider_profile_model.dart';
import 'api_client.dart';

class ProfileService {
  /// جلب بيانات المستخدم الحالي (عميل أو مزود)
  static Future<ProfileResult<UserProfile>> fetchMyProfile() async {
    final response = await ApiClient.get('/api/accounts/me/');

    if (response.isSuccess && response.dataAsMap != null) {
      try {
        final profile = UserProfile.fromJson(response.dataAsMap!);
        return ProfileResult.success(profile);
      } catch (e) {
        return ProfileResult.failure('خطأ في تحليل بيانات المستخدم');
      }
    }

    if (response.statusCode == 401) {
      return ProfileResult.failure('يجب تسجيل الدخول أولاً');
    }

    return ProfileResult.failure(response.error ?? 'خطأ غير متوقع');
  }

  /// جلب بيانات ملف المزود (فقط إذا كان المستخدم مزود)
  static Future<ProfileResult<ProviderProfileModel>> fetchProviderProfile() async {
    final response = await ApiClient.get('/api/providers/me/profile/');

    if (response.isSuccess && response.dataAsMap != null) {
      try {
        final profile = ProviderProfileModel.fromJson(response.dataAsMap!);
        return ProfileResult.success(profile);
      } catch (e) {
        return ProfileResult.failure('خطأ في تحليل بيانات المزود');
      }
    }

    if (response.statusCode == 401) {
      return ProfileResult.failure('يجب تسجيل الدخول أولاً');
    }

    if (response.statusCode == 404) {
      return ProfileResult.failure('لا يوجد ملف مزود');
    }

    return ProfileResult.failure(response.error ?? 'خطأ غير متوقع');
  }

  /// تحديث بيانات المستخدم
  static Future<ProfileResult<UserProfile>> updateMyProfile(Map<String, dynamic> data) async {
    final response = await ApiClient.patch('/api/accounts/me/', body: data);

    if (response.isSuccess && response.dataAsMap != null) {
      try {
        final profile = UserProfile.fromJson(response.dataAsMap!);
        return ProfileResult.success(profile);
      } catch (e) {
        return ProfileResult.failure('خطأ في تحليل الاستجابة');
      }
    }

    return ProfileResult.failure(response.error ?? 'خطأ في التحديث');
  }

  /// تحديث بيانات ملف المزود
  static Future<ProfileResult<ProviderProfileModel>> updateProviderProfile(
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.patch('/api/providers/me/profile/', body: data);

    if (response.isSuccess && response.dataAsMap != null) {
      try {
        final profile = ProviderProfileModel.fromJson(response.dataAsMap!);
        return ProfileResult.success(profile);
      } catch (e) {
        return ProfileResult.failure('خطأ في تحليل الاستجابة');
      }
    }

    return ProfileResult.failure(response.error ?? 'خطأ في التحديث');
  }

  /// جلب بيانات المحفظة
  static Future<ApiResponse> fetchWallet() {
    return ApiClient.get('/api/accounts/wallet/');
  }
}

/// نتيجة عملية البروفايل
class ProfileResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  ProfileResult._({this.data, this.error, required this.isSuccess});

  factory ProfileResult.success(T data) =>
      ProfileResult._(data: data, isSuccess: true);

  factory ProfileResult.failure(String error) =>
      ProfileResult._(error: error, isSuccess: false);
}
