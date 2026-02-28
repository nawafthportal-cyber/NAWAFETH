/// خدمة المصادقة عبر الـ API — إرسال OTP + التحقق + إكمال التسجيل
///
/// الـ Endpoints:
/// - POST /api/accounts/otp/send/      → إرسال رمز التحقق
/// - POST /api/accounts/otp/verify/    → التحقق من الرمز → JWT tokens
/// - POST /api/accounts/complete/      → إكمال بيانات التسجيل (phone_only → client)
library;

import 'api_client.dart';
import 'auth_service.dart';

class AuthApiService {
  // ────────────────────────────────────────
  // 📱 إرسال رمز التحقق
  // ────────────────────────────────────────

  /// إرسال OTP إلى رقم الجوال
  /// يعيد dev_code في بيئة التطوير
  static Future<OtpSendResult> sendOtp(String phone) async {
    final resp = await ApiClient.post(
      '/api/accounts/otp/send/',
      body: {'phone': phone},
    );

    if (resp.isSuccess) {
      final data = resp.dataAsMap;
      return OtpSendResult(
        success: true,
        devCode: data?['dev_code'] as String?,
      );
    }

    return OtpSendResult(
      success: false,
      error: _extractError(resp),
    );
  }

  // ────────────────────────────────────────
  // 🔑 التحقق من الرمز
  // ────────────────────────────────────────

  /// التحقق من رمز OTP → حفظ التوكنات ← إرجاع بيانات المستخدم
  static Future<OtpVerifyResult> verifyOtp(String phone, String code) async {
    final resp = await ApiClient.post(
      '/api/accounts/otp/verify/',
      body: {'phone': phone, 'code': code},
    );

    if (!resp.isSuccess) {
      return OtpVerifyResult(
        success: false,
        error: _extractError(resp),
      );
    }

    final data = resp.dataAsMap;
    if (data == null) {
      return OtpVerifyResult(success: false, error: 'استجابة غير صالحة');
    }

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;

    if (access == null || refresh == null) {
      return OtpVerifyResult(success: false, error: 'لم يتم استلام التوكنات');
    }

    // ✅ حفظ التوكنات وبيانات المستخدم
    await AuthService.saveTokens(access: access, refresh: refresh);

    final userId = data['user_id'] as int?;
    final roleState = data['role_state'] as String? ?? 'phone_only';
    if (userId != null) {
      await AuthService.saveUserBasicInfo(
        userId: userId,
        roleState: roleState,
      );
    }

    return OtpVerifyResult(
      success: true,
      userId: userId,
      roleState: roleState,
      isNewUser: data['is_new_user'] as bool? ?? false,
      needsCompletion: data['needs_completion'] as bool? ?? false,
    );
  }

  // ────────────────────────────────────────
  // 📝 إكمال التسجيل
  // ────────────────────────────────────────

  /// إكمال بيانات التسجيل (ترقية من phone_only إلى client)
  static Future<CompleteResult> completeRegistration({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String city,
    required String password,
    required String passwordConfirm,
    bool acceptTerms = true,
  }) async {
    final resp = await ApiClient.post(
      '/api/accounts/complete/',
      body: {
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'email': email,
        'city': city,
        'password': password,
        'password_confirm': passwordConfirm,
        'accept_terms': acceptTerms,
      },
    );

    if (resp.isSuccess) {
      final data = resp.dataAsMap;
      final newRole = data?['role_state'] as String? ?? 'client';
      // ✅ تحديث الدور المحلي
      final userId = await AuthService.getUserId();
      if (userId != null) {
        await AuthService.saveUserBasicInfo(
          userId: userId,
          roleState: newRole,
        );
      }
      return CompleteResult(success: true, roleState: newRole);
    }

    return CompleteResult(
      success: false,
      error: _extractError(resp),
      fieldErrors: _extractFieldErrors(resp),
    );
  }

  // ────────────────────────────────────────
  // 🛠️ مساعدات
  // ────────────────────────────────────────

  static String _extractError(ApiResponse resp) {
    if (resp.error != null) return resp.error!;
    final data = resp.dataAsMap;
    if (data != null && data.containsKey('detail')) {
      return data['detail'] as String? ?? 'خطأ غير معروف';
    }
    return 'خطأ في الاتصال (${resp.statusCode})';
  }

  static Map<String, String>? _extractFieldErrors(ApiResponse resp) {
    final data = resp.dataAsMap;
    if (data == null) return null;

    final errors = <String, String>{};
    for (final entry in data.entries) {
      if (entry.key == 'detail') continue;
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        errors[entry.key] = value.first.toString();
      } else if (value is String) {
        errors[entry.key] = value;
      }
    }
    return errors.isNotEmpty ? errors : null;
  }
}

// ══════════════════════════════════════════
//  نماذج النتائج
// ══════════════════════════════════════════

class OtpSendResult {
  final bool success;
  final String? devCode;
  final String? error;

  OtpSendResult({required this.success, this.devCode, this.error});
}

class OtpVerifyResult {
  final bool success;
  final int? userId;
  final String? roleState;
  final bool isNewUser;
  final bool needsCompletion;
  final String? error;

  OtpVerifyResult({
    required this.success,
    this.userId,
    this.roleState,
    this.isNewUser = false,
    this.needsCompletion = false,
    this.error,
  });
}

class CompleteResult {
  final bool success;
  final String? roleState;
  final String? error;
  final Map<String, String>? fieldErrors;

  CompleteResult({
    required this.success,
    this.roleState,
    this.error,
    this.fieldErrors,
  });
}
