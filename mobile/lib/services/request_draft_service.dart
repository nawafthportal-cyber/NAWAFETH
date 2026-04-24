import 'local_cache_service.dart';

class RequestDraftService {
  RequestDraftService._();

  static const Duration _draftTtl = Duration(days: 3);

  static Future<void> saveDraft(
    String key,
    Map<String, dynamic> payload,
  ) async {
    final sanitized = <String, dynamic>{};
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      sanitized[entry.key] = value;
    }
    await LocalCacheService.writeJson(key, sanitized);
  }

  static Future<Map<String, dynamic>?> loadDraft(String key) async {
    final envelope = await LocalCacheService.readJson(key);
    if (envelope == null) {
      return null;
    }
    if (!envelope.isFresh(_draftTtl)) {
      await LocalCacheService.remove(key);
      return null;
    }
    final payload = envelope.payload;
    if (payload is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(payload);
  }

  static Future<void> clearDraft(String key) {
    return LocalCacheService.remove(key);
  }

  static String readString(Map<String, dynamic> payload, String key) {
    return (payload[key] as String? ?? '').trim();
  }

  static int? readInt(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}