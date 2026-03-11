import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

typedef AccountModeListener = void Function(bool isProvider);

class AccountModeService {
  static const String _isProviderKey = 'isProvider';
  static final Set<AccountModeListener> _listeners = <AccountModeListener>{};

  static void addListener(AccountModeListener listener) {
    _listeners.add(listener);
  }

  static void removeListener(AccountModeListener listener) {
    _listeners.remove(listener);
  }

  static Future<bool> isProviderMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isProviderKey) ?? false;
  }

  static Future<void> setProviderMode(bool isProvider) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getBool(_isProviderKey) ?? false;
    await prefs.setBool(_isProviderKey, isProvider);
    if (previous == isProvider) return;
    for (final listener in List<AccountModeListener>.from(_listeners)) {
      scheduleMicrotask(() {
        try {
          listener(isProvider);
        } catch (_) {}
      });
    }
  }

  static Future<String> apiMode() async {
    final isProvider = await isProviderMode();
    return isProvider ? 'provider' : 'client';
  }
}
