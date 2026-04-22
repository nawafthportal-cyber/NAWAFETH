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
}
