import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _seenKey = 'has_seen_onboarding_v2';

  /// Returns today's date stamp (e.g. "2026-04-21").
  /// Matches the same daily-reset logic used in onboardingOverlay.js (web).
  static String _todayStamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Returns true only on the first open of each calendar day.
  static Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate: old versions stored a bool — remove it if present.
    if (prefs.containsKey(_seenKey) && prefs.get(_seenKey) is bool) {
      await prefs.remove(_seenKey);
    }
    return prefs.getString(_seenKey) != _todayStamp();
  }

  /// Marks onboarding as seen for today.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey, _todayStamp());
  }
}
