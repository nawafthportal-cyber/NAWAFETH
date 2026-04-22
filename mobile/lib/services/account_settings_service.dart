library;

import 'api_client.dart';

class AccountSettingsService {
  static Future<ApiResponse> changeUsername(String username) {
    return ApiClient.post(
      '/api/accounts/change-username/',
      body: {'username': username.trim()},
    );
  }

  static Future<ApiResponse> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return ApiClient.post(
      '/api/accounts/change-password/',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirm': confirmPassword,
      },
    );
  }

  static Future<ApiResponse> requestPhoneChange(String phone) {
    return ApiClient.post(
      '/api/accounts/me/request-phone-change/',
      body: {'phone': phone.trim()},
    );
  }

  static Future<ApiResponse> confirmPhoneChange({
    required String phone,
    required String code,
  }) {
    return ApiClient.post(
      '/api/accounts/me/confirm-phone-change/',
      body: {
        'phone': phone.trim(),
        'code': code.trim(),
      },
    );
  }
}
