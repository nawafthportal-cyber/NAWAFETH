import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _seenKey = 'has_seen_onboarding_v2';

  /// Returns true the first time the app is opened each local day.
  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStamp();
    final storedValue = prefs.get(_seenKey);

    if (storedValue is String) {
      return storedValue != today;
    }

    if (storedValue is bool && storedValue) {
      await prefs.setString(_seenKey, today);
      return false;
    }

    return true;
  }

  /// Marks onboarding as seen for the current local day.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey, _todayStamp());
  }

  static String _todayStamp() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
