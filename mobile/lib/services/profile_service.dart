/// خدمة البروفايل — جلب وتحديث بيانات المستخدم والمزود
library;

import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';
import '../models/provider_profile_model.dart';
import 'api_client.dart';
import 'account_mode_service.dart';
import 'upload_optimizer.dart';

class ProfileService {
  static Future<String> _optimizeImagePath(String path) async {
    final sourcePath = path.trim();
    if (sourcePath.isEmpty) return path;
    try {
      final optimized = await UploadOptimizer.optimizeForUpload(
        File(sourcePath),
        declaredType: 'image',
      );
      return optimized.path;
    } catch (_) {
      return sourcePath;
    }
  }

  static Future<String> _mePathWithMode() async {
    final mode = await AccountModeService.apiMode();
    return '/api/accounts/me/?mode=$mode';
  }

  /// جلب بيانات المستخدم الحالي (عميل أو مزود)
  static Future<ProfileResult<UserProfile>> fetchMyProfile() async {
    final mePath = await _mePathWithMode();
    final response = await ApiClient.get(mePath);

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
  static Future<ProfileResult<ProviderProfileModel>>
      fetchProviderProfile() async {
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
  static Future<ProfileResult<UserProfile>> updateMyProfile(
      Map<String, dynamic> data) async {
    final mePath = await _mePathWithMode();
    final response = await ApiClient.patch(mePath, body: data);

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

    final res = await ApiClient.sendMultipart(
      'PATCH',
      await _mePathWithMode(),
      (request) async {
        if (profileImagePath != null && profileImagePath.isNotEmpty) {
          final optimizedProfilePath = await _optimizeImagePath(profileImagePath);
          request.files.add(
            await http.MultipartFile.fromPath(
                'profile_image', optimizedProfilePath),
          );
        }
        if (coverImagePath != null && coverImagePath.isNotEmpty) {
          final optimizedCoverPath = await _optimizeImagePath(coverImagePath);
          request.files.add(
            await http.MultipartFile.fromPath('cover_image', optimizedCoverPath),
          );
        }
      },
    );

    if (res.isSuccess) {
      final payload = res.dataAsMap;
      if (payload != null) {
        try {
          final profile = UserProfile.fromJson(payload);
          return ProfileResult.success(profile);
        } catch (_) {
          // Fallback below: some environments return incomplete body after upload.
        }
      }

      final fresh = await fetchMyProfile();
      if (fresh.isSuccess && fresh.data != null) {
        return ProfileResult.success(fresh.data!);
      }
      return ProfileResult.failure(
        fresh.error ?? 'تم رفع الصور لكن تعذر جلب البيانات المحدثة',
      );
    }
    return ProfileResult.failure(res.error ?? 'فشل رفع الصور');
  }

  /// رفع صورة الملف الشخصي/الخلفية لملف المزود (multipart)
  static Future<ProfileResult<ProviderProfileModel>>
      uploadProviderProfileImages({
    String? profileImagePath,
    String? coverImagePath,
  }) async {
    if ((profileImagePath == null || profileImagePath.isEmpty) &&
        (coverImagePath == null || coverImagePath.isEmpty)) {
      return ProfileResult.failure('لم يتم اختيار صورة للرفع');
    }

    final res = await ApiClient.sendMultipart(
      'PATCH',
      '/api/providers/me/profile/',
      (request) async {
        if (profileImagePath != null && profileImagePath.isNotEmpty) {
          final optimizedProfilePath = await _optimizeImagePath(profileImagePath);
          request.files.add(
            await http.MultipartFile.fromPath(
                'profile_image', optimizedProfilePath),
          );
        }
        if (coverImagePath != null && coverImagePath.isNotEmpty) {
          final optimizedCoverPath = await _optimizeImagePath(coverImagePath);
          request.files.add(
            await http.MultipartFile.fromPath('cover_image', optimizedCoverPath),
          );
        }
      },
    );

    if (res.isSuccess) {
      final payload = res.dataAsMap;
      if (payload != null) {
        try {
          final profile = ProviderProfileModel.fromJson(payload);
          return ProfileResult.success(profile);
        } catch (_) {
          // Fallback below: some environments return incomplete body after upload.
        }
      }

      final fresh = await fetchProviderProfile();
      if (fresh.isSuccess && fresh.data != null) {
        return ProfileResult.success(fresh.data!);
      }
      return ProfileResult.failure(
        fresh.error ?? 'تم رفع الصور لكن تعذر جلب البيانات المحدثة',
      );
    }
    return ProfileResult.failure(res.error ?? 'فشل رفع الصور');
  }

  /// رفع عنصر جديد إلى معرض أعمال المزود (Portfolio) (multipart)
  static Future<ProfileResult<Map<String, dynamic>>>
      uploadProviderPortfolioItem({
    required String filePath,
    String fileType = 'image',
    String? caption,
  }) async {
    if (filePath.trim().isEmpty) {
      return ProfileResult.failure('لم يتم اختيار ملف للرفع');
    }

    final res = await ApiClient.sendMultipart(
      'POST',
      '/api/providers/me/portfolio/',
      (request) async {
        request.fields['file_type'] = fileType;
        if (caption != null && caption.trim().isNotEmpty) {
          request.fields['caption'] = caption.trim();
        }
        var uploadPath = filePath;
        if (fileType.trim().toLowerCase() == 'image') {
          uploadPath = await _optimizeImagePath(filePath);
        }
        request.files.add(await http.MultipartFile.fromPath('file', uploadPath));
      },
    );

    if (res.isSuccess) {
      return ProfileResult.success(res.dataAsMap ?? <String, dynamic>{});
    }
    return ProfileResult.failure(res.error ?? 'فشل رفع العنصر');
  }

  /// رفع لمحة (Spotlight) واحدة لملف المزود (multipart)
  static Future<ProfileResult<Map<String, dynamic>>> uploadProviderSpotlight({
    required String filePath,
    String fileType = 'video',
    String? caption,
  }) async {
    if (filePath.trim().isEmpty) {
      return ProfileResult.failure('لم يتم اختيار ملف للرفع');
    }

    final res = await ApiClient.sendMultipart(
      'POST',
      '/api/providers/me/spotlights/',
      (request) async {
        request.fields['file_type'] = fileType;
        if (caption != null && caption.trim().isNotEmpty) {
          request.fields['caption'] = caption.trim();
        }
        var uploadPath = filePath;
        if (fileType.trim().toLowerCase() == 'image') {
          uploadPath = await _optimizeImagePath(filePath);
        }
        request.files.add(await http.MultipartFile.fromPath('file', uploadPath));
      },
    );

    if (res.isSuccess) {
      return ProfileResult.success(res.dataAsMap ?? <String, dynamic>{});
    }
    return ProfileResult.failure(res.error ?? 'فشل رفع اللمحة');
  }

  /// تحديث بيانات ملف المزود
  static Future<ProfileResult<ProviderProfileModel>> updateProviderProfile(
    Map<String, dynamic> data,
  ) async {
    final response =
        await ApiClient.patch('/api/providers/me/profile/', body: data);

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
    final response =
        await ApiClient.post('/api/providers/register/', body: data);

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
