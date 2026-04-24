import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheService {
  LocalCacheService._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> _ensurePrefs() async {
    final prefs = _prefs;
    if (prefs != null) {
      return prefs;
    }
    final loaded = await SharedPreferences.getInstance();
    _prefs = loaded;
    return loaded;
  }

  static CachedJsonEnvelope? readJsonSync(String key) {
    final prefs = _prefs;
    if (prefs == null) {
      return null;
    }
    return _decodeEnvelope(prefs.getString(key));
  }

  static Future<CachedJsonEnvelope?> readJson(String key) async {
    final prefs = await _ensurePrefs();
    return _decodeEnvelope(prefs.getString(key));
  }

  static Future<void> writeJson(String key, Object value) async {
    final prefs = await _ensurePrefs();
    final payload = jsonEncode({
      'cached_at': DateTime.now().toUtc().toIso8601String(),
      'payload': value,
    });
    await prefs.setString(key, payload);
  }

  static Future<void> remove(String key) async {
    final prefs = await _ensurePrefs();
    await prefs.remove(key);
  }

  static void debugReset() {
    _prefs = null;
  }

  static CachedJsonEnvelope? _decodeEnvelope(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final cachedAtRaw = map['cached_at']?.toString();
      final cachedAt =
          cachedAtRaw == null ? null : DateTime.tryParse(cachedAtRaw);
      if (cachedAt == null) {
        return null;
      }
      return CachedJsonEnvelope(
        payload: map['payload'],
        cachedAt: cachedAt.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

class CachedJsonEnvelope {
  final dynamic payload;
  final DateTime cachedAt;

  const CachedJsonEnvelope({
    required this.payload,
    required this.cachedAt,
  });

  bool isFresh(Duration ttl) {
    return DateTime.now().toUtc().difference(cachedAt) <= ttl;
  }
}
