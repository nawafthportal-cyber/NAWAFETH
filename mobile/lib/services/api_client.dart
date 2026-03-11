/// خدمة HTTP الأساسية للاتصال بالـ Backend API
///
/// تتعامل مع:
/// - إضافة headers المصادقة تلقائياً
/// - تجديد التوكن عند انتهاء صلاحيته
/// - معالجة الأخطاء بشكل موحد
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_env.dart';
import 'auth_service.dart';

class ApiClient {
  static String get baseUrl => AppEnv.apiBaseUrl;
  static http.Client _httpClient = http.Client();
  static Future<_RefreshAttemptResult>? _refreshing;

  static Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(baseUrl).resolve(normalizedPath);
  }

  static void debugSetHttpClient(http.Client client) {
    _httpClient = client;
    _refreshing = null;
  }

  static void debugResetHttpClient() {
    _httpClient = http.Client();
    _refreshing = null;
  }

  /// GET request مع مصادقة
  static Future<ApiResponse> get(String path) async {
    return _request('GET', path);
  }

  /// POST request مع مصادقة
  static Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) async {
    return _request('POST', path, body: body);
  }

  /// PATCH request مع مصادقة
  static Future<ApiResponse> patch(String path, {Map<String, dynamic>? body}) async {
    return _request('PATCH', path, body: body);
  }

  /// PUT request مع مصادقة
  static Future<ApiResponse> put(String path, {Map<String, dynamic>? body}) async {
    return _request('PUT', path, body: body);
  }

  /// DELETE request مع مصادقة
  static Future<ApiResponse> delete(String path) async {
    return _request('DELETE', path);
  }

  /// ─── الطلب الرئيسي ───
  static Future<ApiResponse> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool isRetry = false,
    bool skipAuth = false,
  }) async {
    final url = _buildUri(path);
    final token = skipAuth ? null : await AuthService.getAccessToken();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      http.Response response;

      switch (method) {
        case 'GET':
          response = await _httpClient
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 15));
          break;
        case 'POST':
          response = await _httpClient
              .post(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'PATCH':
          response = await _httpClient
              .patch(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'PUT':
          response = await _httpClient
              .put(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'DELETE':
          response = await _httpClient
              .delete(url, headers: headers)
              .timeout(const Duration(seconds: 15));
          break;
        default:
          return ApiResponse(statusCode: 0, error: 'طريقة HTTP غير مدعومة');
      }

      if (response.statusCode == 401 && !isRetry && !_isRefreshPath(path)) {
        final refreshResult = await _refreshAccessToken();
        if (refreshResult.ok) {
          return _request(method, path, body: body, isRetry: true);
        }
        if (refreshResult.terminal) {
          return _request(
            method,
            path,
            body: body,
            isRetry: true,
            skipAuth: true,
          );
        }
      }

      return parseResponse(response);
    } on TimeoutException {
      return ApiResponse(
        statusCode: 0,
        error: 'انتهت مهلة الاتصال بالخادم. تحقق من تشغيل الـ API.',
      );
    } on SocketException {
      return ApiResponse(
        statusCode: 0,
        error: 'تعذر الوصول إلى الخادم. تحقق من عنوان الـ API والشبكة.',
      );
    } catch (e) {
      return ApiResponse(statusCode: 0, error: 'خطأ في الاتصال: $e');
    }
  }

  static bool _isRefreshPath(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return normalizedPath.contains('/api/accounts/token/refresh/');
  }

  static Future<_RefreshAttemptResult> _refreshAccessToken() async {
    if (_refreshing != null) {
      return _refreshing!;
    }
    _refreshing = _performRefresh().whenComplete(() {
      _refreshing = null;
    });
    return _refreshing!;
  }

  static Future<_RefreshAttemptResult> _performRefresh() async {
    final refreshToken = await AuthService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await AuthService.logout();
      return const _RefreshAttemptResult(ok: false, terminal: true);
    }

    try {
      final url = _buildUri('/api/accounts/token/refresh/');
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final newAccess = data['access'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await AuthService.saveTokens(
            access: newAccess,
            refresh: refreshToken,
          );
          return const _RefreshAttemptResult(ok: true, terminal: false);
        }
      }

      if (response.statusCode == 400 || response.statusCode == 401) {
        await AuthService.logout();
        return const _RefreshAttemptResult(ok: false, terminal: true);
      }
    } on TimeoutException {
      return const _RefreshAttemptResult(ok: false, terminal: false);
    } on SocketException {
      return const _RefreshAttemptResult(ok: false, terminal: false);
    } catch (_) {
      return const _RefreshAttemptResult(ok: false, terminal: false);
    }

    return const _RefreshAttemptResult(ok: false, terminal: false);
  }

  /// تحليل الاستجابة (public for multipart usage)
  static ApiResponse parseResponse(http.Response response) {
    final statusCode = response.statusCode;
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();

    dynamic data;
    if (body.isNotEmpty) {
      final looksLikeJson = body.startsWith('{') || body.startsWith('[');
      if (contentType.contains('json') || looksLikeJson) {
        try {
          data = jsonDecode(body);
        } catch (_) {
          data = null;
        }
      }
    }

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResponse(statusCode: statusCode, data: data);
    }

    String errorMessage = _defaultErrorMessage(statusCode);
    if (data is Map) {
      errorMessage = data['detail'] as String? ??
          data['error'] as String? ??
          data.toString();
    } else if (body.isNotEmpty) {
      final plain = body
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (plain.isNotEmpty) {
        errorMessage = plain.length > 220
            ? '${plain.substring(0, 220)}...'
            : plain;
      }
    }

    return ApiResponse(
      statusCode: statusCode,
      data: data,
      error: errorMessage,
    );
  }

  static String _defaultErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'البيانات المرسلة غير صحيحة';
      case 401:
        return 'انتهت الجلسة، يرجى تسجيل الدخول مرة أخرى';
      case 403:
        return 'ليس لديك صلاحية لتنفيذ هذا الإجراء';
      case 404:
        return 'العنصر المطلوب غير موجود';
      case 413:
        return 'حجم الملف كبير جدًا';
      case 415:
        return 'صيغة الملف غير مدعومة';
      case 429:
        return 'تم تجاوز الحد المسموح من الطلبات، حاول لاحقًا';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'حدث خطأ في الخادم، حاول مرة أخرى';
      default:
        return 'حدث خطأ غير متوقع';
    }
  }

  /// بناء URL كامل لملف وسائط (صورة/فيديو)
  static String? buildMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return _buildUri(path).toString();
  }

  /// إرسال طلب multipart مع مصادقة + تجديد توكن تلقائي
  ///
  /// [method] عادة 'POST' أو 'PATCH'.
  /// [path] مسار الـ API مثل '/api/support/tickets/5/attachments/'.
  /// [prepareRequest] دالة تضيف الحقول والملفات على الـ MultipartRequest.
  /// يعيد [ApiResponse] كأي طلب آخر.
  static Future<ApiResponse> sendMultipart(
    String method,
    String path,
    Future<void> Function(http.MultipartRequest request) prepareRequest, {
    Duration timeout = const Duration(seconds: 30),
    bool isRetry = false,
    bool skipAuth = false,
  }) async {
    final uri = _buildUri(path);
    final token = skipAuth ? null : await AuthService.getAccessToken();

    final request = http.MultipartRequest(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    await prepareRequest(request);

    try {
      final streamed = await _httpClient.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401 && !isRetry && !_isRefreshPath(path)) {
        final refreshResult = await _refreshAccessToken();
        if (refreshResult.ok) {
          return sendMultipart(
            method,
            path,
            prepareRequest,
            timeout: timeout,
            isRetry: true,
          );
        }
        if (refreshResult.terminal) {
          return sendMultipart(
            method,
            path,
            prepareRequest,
            timeout: timeout,
            isRetry: true,
            skipAuth: true,
          );
        }
      }

      return parseResponse(response);
    } on TimeoutException {
      return ApiResponse(
        statusCode: 0,
        error: 'انتهت مهلة الاتصال بالخادم.',
      );
    } on SocketException {
      return ApiResponse(
        statusCode: 0,
        error: 'تعذر الوصول إلى الخادم. تحقق من الاتصال.',
      );
    } catch (e) {
      return ApiResponse(statusCode: 0, error: 'خطأ في الاتصال: $e');
    }
  }
}

class _RefreshAttemptResult {
  final bool ok;
  final bool terminal;

  const _RefreshAttemptResult({
    required this.ok,
    required this.terminal,
  });
}

/// نموذج الاستجابة الموحد
class ApiResponse {
  final int statusCode;
  final dynamic data;
  final String? error;

  ApiResponse({
    required this.statusCode,
    this.data,
    this.error,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic>? get dataAsMap {
    if (data is Map<String, dynamic>) return data as Map<String, dynamic>;
    return null;
  }

  List<dynamic>? get dataAsList {
    if (data is List) return data as List<dynamic>;
    return null;
  }
}
