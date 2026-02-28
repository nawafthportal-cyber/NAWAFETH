import 'package:shared_preferences/shared_preferences.dart';

class AccountModeService {
  static const String _isProviderKey = 'isProvider';

  static Future<bool> isProviderMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isProviderKey) ?? false;
  }

  static Future<void> setProviderMode(bool isProvider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isProviderKey, isProvider);
  }

  static Future<String> apiMode() async {
    final isProvider = await isProviderMode();
    return isProvider ? 'provider' : 'client';
  }
}
