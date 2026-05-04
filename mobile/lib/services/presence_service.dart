import 'dart:async';

import 'api_client.dart';
import 'auth_service.dart';
import 'app_logger.dart';

/// Sends a periodic heartbeat to the backend so the user's `last_seen`
/// timestamp stays fresh. The backend throttles writes (60s) so it's safe
/// to call frequently. We tick every 60s while running.
class PresenceService {
  static const _heartbeatPath = '/api/accounts/heartbeat/';
  static const Duration _interval = Duration(seconds: 60);

  static Timer? _timer;
  static bool _started = false;

  /// Start ticking. Safe to call multiple times — only the first call wires
  /// up the timer.
  static void start() {
    if (_started) return;
    _started = true;
    _send();
    _timer = Timer.periodic(_interval, (_) => _send());
  }

  /// Stop the heartbeat (e.g., on logout).
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// Force a single heartbeat (useful right after login or app resume).
  static Future<void> ping() => _send();

  static Future<void> _send() async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null || token.isEmpty) return; // not signed in
      await ApiClient.post(_heartbeatPath, body: <String, dynamic>{});
    } catch (e) {
      AppLogger.warn('Presence heartbeat failed: $e');
    }
  }
}
