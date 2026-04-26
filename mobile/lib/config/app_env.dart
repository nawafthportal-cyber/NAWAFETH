import 'package:flutter/foundation.dart';

/// إعدادات البيئة الخاصة بتطبيق Flutter.
///
/// يمكن التحكم بعنوان الـ API وقت التشغيل عبر `--dart-define`:
/// - API_TARGET=local|render|auto
/// - API_BASE_URL=https://example.com
/// - API_LOCAL_BASE_URL=http://192.168.1.10:8000
/// - API_RENDER_BASE_URL=https://www.nawafthportal.com
class AppEnv {
  static const String _apiTargetDefine = String.fromEnvironment(
    'API_TARGET',
    defaultValue: '',
  );
  static const String _apiBaseUrlDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _apiLocalBaseUrlDefine = String.fromEnvironment(
    'API_LOCAL_BASE_URL',
    defaultValue: '',
  );
  static const String _apiRenderBaseUrlDefine = String.fromEnvironment(
    'API_RENDER_BASE_URL',
    defaultValue: 'https://www.nawafthportal.com',
  );

  static String get apiBaseUrl {
    final target = _apiTargetDefine.trim().toLowerCase();

    if (target == 'local') {
      return _localBaseUrl;
    }
    if (target == 'render') {
      return _renderBaseUrl;
    }

    if (target == 'auto' || target.isEmpty) {
      final explicit = _normalize(_apiBaseUrlDefine);
      if (explicit != null) {
        return explicit;
      }
      return kReleaseMode ? _renderBaseUrl : _localBaseUrl;
    }

    final explicit = _normalize(_apiBaseUrlDefine);
    if (explicit != null) {
      return explicit;
    }

    return kReleaseMode ? _renderBaseUrl : _localBaseUrl;
  }

  static String get _localBaseUrl {
    final localOverride = _normalize(_apiLocalBaseUrlDefine);
    if (localOverride != null) {
      return localOverride;
    }

    if (kIsWeb) {
      return 'http://localhost:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:8000';
    }
  }

  static String get _renderBaseUrl {
    return _normalize(_apiRenderBaseUrlDefine) ??
        'https://www.nawafthportal.com';
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    if (v.endsWith('/')) return v.substring(0, v.length - 1);
    return v;
  }
}
