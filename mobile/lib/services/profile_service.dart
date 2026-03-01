/// خدمة البروفايل — جلب وتحديث بيانات المستخدم والمزود
library;

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';
import '../models/provider_profile_model.dart';
import 'api_client.dart';
import 'auth_service.dart';

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

  /// رفع صورة الملف الشخصي/الخلفية للمستخدم (multipart)
  static Future<ProfileResult<UserProfile>> uploadMyProfileImages({
    String? profileImagePath,
    String? coverImagePath,
  }) async {
    if ((profileImagePath == null || profileImagePath.isEmpty) &&
        (coverImagePath == null || coverImagePath.isEmpty)) {
      return ProfileResult.failure('لم يتم اختيار صورة للرفع');
    }

    final token = await AuthService.getAccessToken();
    if (token == null || token.isEmpty) {
      return ProfileResult.failure('يجب تسجيل الدخول أولاً');
    }

    final uri = Uri.parse(ApiClient.baseUrl).resolve('/api/accounts/me/');
    final request = http.MultipartRequest('PATCH', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    if (profileImagePath != null && profileImagePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('profile_image', profileImagePath));
    }
    if (coverImagePath != null && coverImagePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('cover_image', coverImagePath));
    }

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401) {
        final refreshed = await _tryRefreshToken();
        if (refreshed) {
          return uploadMyProfileImages(
            profileImagePath: profileImagePath,
            coverImagePath: coverImagePath,
          );
        }
      }

      final parsed = ApiClient.parseResponse(response);
      if (parsed.isSuccess && parsed.dataAsMap != null) {
        try {
          final profile = UserProfile.fromJson(parsed.dataAsMap!);
          return ProfileResult.success(profile);
        } catch (_) {
          return ProfileResult.failure('خطأ في تحليل الاستجابة');
        }
      }

      return ProfileResult.failure(parsed.error ?? 'فشل رفع الصور');
    } on SocketException {
      return ProfileResult.failure('تعذر الوصول إلى الخادم. تحقق من الاتصال.');
    } catch (e) {
      return ProfileResult.failure('خطأ أثناء الرفع: $e');
    }
  }

  static Future<bool> _tryRefreshToken() async {
    final refreshToken = await AuthService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final uri = Uri.parse(ApiClient.baseUrl).resolve('/api/accounts/token/refresh/');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh': refreshToken}),
      );

      final parsed = ApiClient.parseResponse(response);
      if (parsed.isSuccess && parsed.dataAsMap != null) {
        final access = parsed.dataAsMap!['access'] as String?;
        if (access != null && access.isNotEmpty) {
          await AuthService.saveTokens(access: access, refresh: refreshToken);
          return true;
        }
      }
    } catch (_) {}

    await AuthService.logout();
    return false;
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

  /// تسجيل ملف مزود جديد
  static Future<ProfileResult<ProviderProfileModel>> registerProvider(
    Map<String, dynamic> data,
  ) async {
    final response = await ApiClient.post('/api/providers/register/', body: data);

    if (response.isSuccess && response.dataAsMap != null) {
      try {
        final profile = ProviderProfileModel.fromJson(response.dataAsMap!);
        return ProfileResult.success(profile);
      } catch (e) {
        return ProfileResult.failure('خطأ في تحليل الاستجابة');
      }
    }

    if (response.statusCode == 400) {
      // حاول استخراج أول رسالة خطأ من الاستجابة
      final errorMap = response.dataAsMap;
      if (errorMap != null) {
        for (final value in errorMap.values) {
          if (value is List && value.isNotEmpty) {
            return ProfileResult.failure(value.first.toString());
          }
          if (value is String) {
            return ProfileResult.failure(value);
          }
        }
      }
      return ProfileResult.failure('بيانات غير مكتملة');
    }

    return ProfileResult.failure(response.error ?? 'فشل في تسجيل ملف المزود');
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
