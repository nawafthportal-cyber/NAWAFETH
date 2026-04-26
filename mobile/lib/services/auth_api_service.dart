/// خدمة المصادقة عبر الـ API — إرسال OTP + التحقق + إكمال التسجيل
///
/// الـ Endpoints:
/// - POST /api/accounts/otp/send/      → إرسال رمز التحقق
/// - POST /api/accounts/otp/verify/    → التحقق من الرمز → JWT tokens
/// - POST /api/accounts/complete/      → إكمال بيانات التسجيل (phone_only → client)
library;

import 'package:flutter/foundation.dart';

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

    final data = resp.dataAsMap;

    if (resp.isSuccess) {
      return OtpSendResult(
        success: true,
        devCode: _readString(data?['dev_code']),
        cooldownSeconds: _readInt(data?['cooldown_seconds']),
        retryAfterSeconds: _readInt(data?['retry_after_seconds']),
        retryAfterText: _readString(data?['retry_after_text']),
      );
    }

    return OtpSendResult(
      success: false,
      error: _extractError(resp),
      cooldownSeconds: _readInt(data?['cooldown_seconds']),
      retryAfterSeconds: _readInt(data?['retry_after_seconds']),
      retryAfterText: _readString(data?['retry_after_text']),
    );
  }

  // ────────────────────────────────────────
  // 🔑 التحقق من الرمز
  // ────────────────────────────────────────

  /// التحقق من رمز OTP → حفظ التوكنات ← إرجاع بيانات المستخدم
  static Future<OtpVerifyResult> verifyOtp(String phone, String code) async {
    final body = <String, dynamic>{
      'phone': phone,
      'code': code,
    };
    if (kDebugMode) {
      body['mobile_any_otp'] = true;
    }
    final resp = await ApiClient.post(
      '/api/accounts/otp/verify/',
      body: body,
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

    if ((access ?? '').trim().isEmpty) {
      return OtpVerifyResult(
        success: false,
        error: 'لم يتم استلام بيانات الجلسة من الخادم',
      );
    }

    // ✅ حفظ التوكنات وبيانات المستخدم
    await AuthService.saveTokens(access: access!, refresh: refresh);

    final userId = data['user_id'] as int?;
    final roleState = data['role_state'] as String? ?? 'phone_only';
    if (userId != null) {
      await AuthService.saveUserBasicInfo(
        userId: userId,
        roleState: roleState,
      );
    }
    await AuthService.saveLastLoginPhone(phone);

    return OtpVerifyResult(
      success: true,
      userId: userId,
      roleState: roleState,
      isNewUser: data['is_new_user'] as bool? ?? false,
      needsCompletion: data['needs_completion'] as bool? ?? false,
    );
  }

  // ────────────────────────────────────────
  // 👤 فحص توفر اسم المستخدم
  // ────────────────────────────────────────

  static Future<UsernameAvailabilityResult> checkUsernameAvailability(
    String username,
  ) async {
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return UsernameAvailabilityResult(
        available: false,
        message: 'اسم المستخدم مطلوب',
      );
    }

    final encoded = Uri.encodeQueryComponent(normalized);
    final resp = await ApiClient.get(
      '/api/accounts/username-availability/?username=$encoded',
    );

    final data = resp.dataAsMap;
    if (resp.statusCode == 0) {
      return UsernameAvailabilityResult(
        available: false,
        message: 'تعذر الاتصال بالخادم أثناء فحص اسم المستخدم',
      );
    }

    if (resp.statusCode == 404) {
      return UsernameAvailabilityResult(
        available: false,
        message: 'خدمة فحص اسم المستخدم غير مفعلة على الخادم الحالي',
      );
    }

    if (data == null) {
      return UsernameAvailabilityResult(
        available: false,
        message: 'تعذر قراءة استجابة الخادم لفحص اسم المستخدم',
      );
    }

    if (resp.isSuccess) {
      return UsernameAvailabilityResult(
        available: data['available'] == true,
        message: (data['detail'] as String?) ??
            ((data['available'] == true)
                ? 'اسم المستخدم متاح'
                : 'اسم المستخدم محجوز'),
      );
    }

    return UsernameAvailabilityResult(
      available: false,
      message: (data['detail'] as String?) ?? _extractError(resp),
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

  /// تخطي إكمال البيانات مع الإبقاء على الحساب كمستخدم عميل
  static Future<CompleteResult> skipCompletion() async {
    final resp =
        await ApiClient.post('/api/accounts/skip-completion/', body: {});

    if (resp.isSuccess) {
      final data = resp.dataAsMap;
      final newRole = data?['role_state'] as String? ?? 'client';
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
  // � المصادقة البيومترية (Face ID / بصمة)
  // ────────────────────────────────────────

  /// تسجيل جهاز بيومتري → يعيد device_token يُحفظ محلياً
  static Future<BiometricEnrollResult> biometricEnroll() async {
    final resp =
        await ApiClient.post('/api/accounts/biometric/enroll/', body: {});

    if (resp.isSuccess) {
      final data = resp.dataAsMap;
      final token = data?['device_token'] as String?;
      if (token != null && token.isNotEmpty) {
        return BiometricEnrollResult(success: true, deviceToken: token);
      }
    }
    return BiometricEnrollResult(success: false, error: _extractError(resp));
  }

  /// تسجيل الدخول بالبايومتري → phone + device_token → JWT tokens
  static Future<OtpVerifyResult> biometricLogin(
      String phone, String deviceToken) async {
    final resp = await ApiClient.post(
      '/api/accounts/biometric/login/',
      body: {'phone': phone, 'device_token': deviceToken},
    );

    if (!resp.isSuccess) {
      return OtpVerifyResult(success: false, error: _extractError(resp));
    }

    final data = resp.dataAsMap;
    if (data == null) {
      return OtpVerifyResult(success: false, error: 'استجابة غير صالحة');
    }

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if ((access ?? '').trim().isEmpty) {
      return OtpVerifyResult(
        success: false,
        error: 'لم يتم استلام بيانات الجلسة من الخادم',
      );
    }

    await AuthService.saveTokens(access: access!, refresh: refresh);
    final userId = data['user_id'] as int?;
    final roleState = data['role_state'] as String? ?? 'phone_only';
    if (userId != null) {
      await AuthService.saveUserBasicInfo(userId: userId, roleState: roleState);
    }
    await AuthService.saveLastLoginPhone(phone);

    return OtpVerifyResult(
      success: true,
      userId: userId,
      roleState: roleState,
      isNewUser: data['is_new_user'] as bool? ?? false,
      needsCompletion: data['needs_completion'] as bool? ?? false,
    );
  }

  /// إلغاء تسجيل البايومتري على السيرفر
  static Future<bool> biometricRevoke() async {
    final resp =
        await ApiClient.post('/api/accounts/biometric/revoke/', body: {});
    return resp.isSuccess;
  }

  // ────────────────────────────────────────
  // �🛠️ مساعدات
  // ────────────────────────────────────────

  static String _extractError(ApiResponse resp) {
    if ((resp.error ?? '').trim().isNotEmpty) {
      return resp.error!.trim();
    }
    final data = resp.dataAsMap;
    if (data != null) {
      final detail = _readString(data['detail'] ?? data['error']);
      if (detail != null) {
        return detail;
      }
      final fields = _extractFieldErrors(resp);
      if (fields != null && fields.isNotEmpty) {
        return fields.values.first;
      }
    }
    switch (resp.statusCode) {
      case 0:
        return 'تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.';
      case 400:
      case 422:
        return 'البيانات المدخلة غير صحيحة.';
      case 401:
        return 'انتهت الجلسة أو الرمز غير صالح. أعد المحاولة.';
      case 403:
        return 'لا يمكنك تنفيذ هذا الإجراء حالياً.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'الخادم غير متاح حالياً. حاول مرة أخرى بعد قليل.';
      default:
        return 'تعذر إكمال العملية حالياً. حاول مرة أخرى.';
    }
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

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _readString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

// ══════════════════════════════════════════
//  نماذج النتائج
// ══════════════════════════════════════════

class OtpSendResult {
  final bool success;
  final String? devCode;
  final int? cooldownSeconds;
  final int? retryAfterSeconds;
  final String? retryAfterText;
  final String? error;

  OtpSendResult({
    required this.success,
    this.devCode,
    this.cooldownSeconds,
    this.retryAfterSeconds,
    this.retryAfterText,
    this.error,
  });
}

class UsernameAvailabilityResult {
  final bool available;
  final String message;

  UsernameAvailabilityResult({
    required this.available,
    required this.message,
  });
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

class BiometricEnrollResult {
  final bool success;
  final String? deviceToken;
  final String? error;

  BiometricEnrollResult({required this.success, this.deviceToken, this.error});
}
