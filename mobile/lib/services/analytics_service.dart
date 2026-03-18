import 'dart:async';

import 'api_client.dart';

class AnalyticsService {
  static final Set<String> _sentDedupeKeys = <String>{};

  static Future<void> track({
    required String eventName,
    String channel = 'flutter',
    String surface = '',
    String sourceApp = '',
    String objectType = '',
    String objectId = '',
    String sessionId = '',
    String dedupeKey = '',
    Map<String, dynamic>? payload,
  }) async {
    final normalizedDedupeKey = dedupeKey.trim();
    if (normalizedDedupeKey.isNotEmpty &&
        !_sentDedupeKeys.add(normalizedDedupeKey)) {
      return;
    }

    try {
      await ApiClient.post(
        '/api/analytics/events/',
        body: {
          'event_name': eventName,
          'channel': channel,
          'surface': surface,
          'source_app': sourceApp,
          'object_type': objectType,
          'object_id': objectId,
          'session_id': sessionId,
          'dedupe_key': normalizedDedupeKey,
          'payload': payload ?? const <String, dynamic>{},
        },
      );
    } catch (_) {
      // Analytics is best-effort and must not affect user flows.
    }
  }

  static void trackFireAndForget({
    required String eventName,
    String channel = 'flutter',
    String surface = '',
    String sourceApp = '',
    String objectType = '',
    String objectId = '',
    String sessionId = '',
    String dedupeKey = '',
    Map<String, dynamic>? payload,
  }) {
    unawaited(
      track(
        eventName: eventName,
        channel: channel,
        surface: surface,
        sourceApp: sourceApp,
        objectType: objectType,
        objectId: objectId,
        sessionId: sessionId,
        dedupeKey: dedupeKey,
        payload: payload,
      ),
    );
  }
}
