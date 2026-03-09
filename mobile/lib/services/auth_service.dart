/// خدمة المصادقة — إدارة التوكنات وحالة تسجيل الدخول
///
/// تخزن access و refresh tokens في SharedPreferences
/// وتوفر واجهة موحدة للتحقق من حالة المصادقة
library;

import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _roleStateKey = 'role_state';

  /// حفظ التوكنات بعد تسجيل الدخول
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, access);
    await prefs.setString(_refreshTokenKey, refresh);
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// استرجاع refresh token
  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
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

  /// تسجيل الخروج — مسح جميع البيانات المحفوظة
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_roleStateKey);
    // نبقي isProvider و isProviderRegistered لأنها تُحدّث من API
    await prefs.remove('isProvider');
    await prefs.remove('isProviderRegistered');
  }
}
