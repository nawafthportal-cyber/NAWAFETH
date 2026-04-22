/// خدمة المصادقة — إدارة التوكنات وحالة تسجيل الدخول
///
/// تخزن access و refresh tokens في SharedPreferences
/// وتوفر واجهة موحدة للتحقق من حالة المصادقة
library;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

typedef AuthLogoutListener = void Function();

class AuthService {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _roleStateKey = 'role_state';
  static const String _faceIdEnabledKey = 'nw_faceid_enabled';
  static const String _faceIdPhoneKey = 'nw_faceid_phone';
  static const String _faceIdDeviceTokenKey = 'nw_faceid_device_token';
  static const String _securityPinKey = 'nw_security_pin';
  static const String _lastLoginPhoneKey = 'last_login_phone';
  static final Set<AuthLogoutListener> _logoutListeners = <AuthLogoutListener>{};

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static void addLogoutListener(AuthLogoutListener listener) {
    _logoutListeners.add(listener);
  }

  static void removeLogoutListener(AuthLogoutListener listener) {
    _logoutListeners.remove(listener);
  }

  /// حفظ التوكنات بعد تسجيل الدخول
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _secureStorage.write(key: _accessTokenKey, value: access);
    await _secureStorage.write(key: _refreshTokenKey, value: refresh);
  }

  /// حفظ بيانات المستخدم الأساسية
  static Future<void> saveUserBasicInfo({
    required int userId,
    required String roleState,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
    await prefs.setString(_roleStateKey, roleState);
  }

  /// استرجاع access token
  static Future<String?> getAccessToken() async {
    return _secureStorage.read(key: _accessTokenKey);
  }

  /// استرجاع refresh token
  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  /// التحقق من حالة تسجيل الدخول
  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// استرجاع معرف المستخدم
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  /// استرجاع حالة الدور
  static Future<String?> getRoleState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleStateKey);
  }

  static Future<bool> needsCompletion() async {
    final role = (await getRoleState())?.trim().toLowerCase() ?? '';
    return role == 'phone_only' || role == 'visitor';
  }

  static String? normalizePhoneLocal05(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (RegExp(r'^05\d{8}$').hasMatch(digits)) {
      return digits;
    }
    if (digits.length == 9 && digits.startsWith('5')) {
      return '0$digits';
    }
    if (digits.length == 12 && digits.startsWith('9665')) {
      return '0${digits.substring(3)}';
    }
    if (digits.length == 13 && digits.startsWith('009665')) {
      return '0${digits.substring(5)}';
    }
    return null;
  }

  static Future<void> saveLastLoginPhone(String phone) async {
    final normalized = normalizePhoneLocal05(phone);
    if (normalized == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLoginPhoneKey, normalized);
  }

  static Future<String?> getLastLoginPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePhoneLocal05(prefs.getString(_lastLoginPhoneKey));
  }

  static Future<void> saveBiometricCredentials({
    required String phone,
    required String deviceToken,
  }) async {
    final normalizedPhone = normalizePhoneLocal05(phone);
    final normalizedToken = deviceToken.trim();
    if (normalizedPhone == null || normalizedToken.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_faceIdEnabledKey, true);
    await _secureStorage.write(key: _faceIdPhoneKey, value: normalizedPhone);
    await _secureStorage.write(key: _faceIdDeviceTokenKey, value: normalizedToken);
  }

  static Future<BiometricAuthData?> getBiometricCredentials({
    bool clearInvalid = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_faceIdEnabledKey) ?? false;
    final phone = normalizePhoneLocal05(await _secureStorage.read(key: _faceIdPhoneKey));
    final deviceToken = ((await _secureStorage.read(key: _faceIdDeviceTokenKey)) ?? '').trim();

    if (enabled && phone != null && deviceToken.isNotEmpty) {
      return BiometricAuthData(phone: phone, deviceToken: deviceToken);
    }

    if (clearInvalid && enabled) {
      await clearBiometricCredentials();
    }
    return null;
  }

  static Future<bool> isBiometricEnabled() async {
    return (await getBiometricCredentials()) != null;
  }

  static Future<void> clearBiometricCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_faceIdEnabledKey, false);
    await _secureStorage.delete(key: _faceIdPhoneKey);
    await _secureStorage.delete(key: _faceIdDeviceTokenKey);
  }

  static Future<void> saveSecurityPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return;
    await _secureStorage.write(key: _securityPinKey, value: pin);
  }

  static Future<String?> getSecurityPin() async {
    final pin = ((await _secureStorage.read(key: _securityPinKey)) ?? '').trim();
    if (RegExp(r'^\d{4,6}$').hasMatch(pin)) return pin;
    return null;
  }

  static Future<bool> verifySecurityPin(String input) async {
    final stored = await getSecurityPin();
    return stored != null && stored == input;
  }

  static Future<void> clearSecurityPin() async {
    await _secureStorage.delete(key: _securityPinKey);
  }

  /// تسجيل الخروج — مسح جميع البيانات المحفوظة
  static Future<void> logout() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_roleStateKey);
    // نبقي isProvider و isProviderRegistered لأنها تُحدّث من API
    await prefs.remove('isProvider');
    await prefs.remove('isProviderRegistered');
    for (final listener in List<AuthLogoutListener>.from(_logoutListeners)) {
      scheduleMicrotask(() {
        try {
          listener();
        } catch (error, stackTrace) {
          AppLogger.warn(
            'AuthService.logout listener failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      });
    }
  }
}

class BiometricAuthData {
  final String phone;
  final String deviceToken;

  const BiometricAuthData({
    required this.phone,
    required this.deviceToken,
  });
}
