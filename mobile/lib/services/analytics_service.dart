import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_client.dart';

class AnalyticsService {
  static final Set<String> _sentDedupeKeys = <String>{};
  static final List<Map<String, dynamic>> _buffer = <Map<String, dynamic>>[];
  static Timer? _flushTimer;
  static Future<void>? _flushInFlight;
  static const Duration _flushInterval = Duration(seconds: 6);
  static const int _maxBatchSize = 20;
  static final WidgetsBindingObserver _lifecycleObserver =
      _AnalyticsLifecycleObserver();
  static bool _lifecycleHookAttached = false;

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
    _ensureLifecycleHook();
    final normalizedDedupeKey = dedupeKey.trim();
    if (normalizedDedupeKey.isNotEmpty &&
        !_sentDedupeKeys.add(normalizedDedupeKey)) {
      return;
    }

    _buffer.add({
      'event_name': eventName,
      'channel': channel,
      'surface': surface,
      'source_app': sourceApp,
      'object_type': objectType,
      'object_id': objectId,
      'session_id': sessionId,
      'dedupe_key': normalizedDedupeKey,
      'payload': payload ?? const <String, dynamic>{},
    });
    _scheduleFlush();
    if (_buffer.length >= _maxBatchSize) {
      await flush();
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

  static Future<void> flush() {
    if (_flushInFlight != null) {
      return _flushInFlight!;
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushInFlight = _flushInternal().whenComplete(() {
      _flushInFlight = null;
    });
    return _flushInFlight!;
  }

  static void _scheduleFlush() {
    _flushTimer ??= Timer(_flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  static void _ensureLifecycleHook() {
    if (_lifecycleHookAttached) {
      return;
    }
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleHookAttached = true;
  }

  static Future<void> _flushInternal() async {
    if (_buffer.isEmpty) {
      return;
    }
    final payload = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      final response = await ApiClient.post(
        '/api/analytics/events/',
        body: {'events': payload},
      );
      if (!response.isSuccess &&
          (response.statusCode == 0 || response.statusCode >= 500)) {
        _buffer.insertAll(0, payload);
      }
    } catch (_) {
      _buffer.insertAll(0, payload);
    }
  }
}

class _AnalyticsLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(AnalyticsService.flush());
    }
  }
}
