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

  static Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(baseUrl).resolve(normalizedPath);
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
  }) async {
    final url = _buildUri(path);
    final token = await AuthService.getAccessToken();

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
          response = await http.get(url, headers: headers).timeout(
            const Duration(seconds: 15),
          );
          break;
        case 'POST':
          response = await http
              .post(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'PATCH':
          response = await http
              .patch(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'PUT':
          response = await http
              .put(url, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'DELETE':
          response = await http.delete(url, headers: headers).timeout(
            const Duration(seconds: 15),
          );
          break;
        default:
          return ApiResponse(statusCode: 0, error: 'طريقة HTTP غير مدعومة');
      }

      // ✅ محاولة تجديد التوكن إذا انتهت صلاحيته
      if (response.statusCode == 401 && !isRetry) {
        await _tryRefreshToken();
        // إعادة المحاولة: بتوكن جديد إذا نجح التجديد، أو بدون توكن
        // (logout يمسح التوكنات) لتمرير AllowAny endpoints
        return _request(method, path, body: body, isRetry: true);
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

  /// محاولة تجديد التوكن
  static Future<bool> _tryRefreshToken() async {
    final refreshToken = await AuthService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final url = _buildUri('/api/accounts/token/refresh/');
      final response = await http.post(
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
          return true;
        }
      }
    } catch (_) {}

    // فشل التجديد - يجب إعادة تسجيل الدخول
    await AuthService.logout();
    return false;
  }

  /// تحليل الاستجابة (public for multipart usage)
  static ApiResponse parseResponse(http.Response response) {
    try {
      final body = utf8.decode(response.bodyBytes);
      final data = body.isNotEmpty ? jsonDecode(body) : null;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse(
          statusCode: response.statusCode,
          data: data,
        );
      } else {
        String errorMessage = 'خطأ غير معروف';
        if (data is Map) {
          errorMessage = data['detail'] as String? ??
              data['error'] as String? ??
              data.toString();
        }
        return ApiResponse(
          statusCode: response.statusCode,
          data: data,
          error: errorMessage,
        );
      }
    } catch (e) {
      return ApiResponse(
        statusCode: response.statusCode,
        error: 'خطأ في تحليل الاستجابة',
      );
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
  }) async {
    final uri = _buildUri(path);
    final token = await AuthService.getAccessToken();

    final request = http.MultipartRequest(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    await prepareRequest(request);

    try {
      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);

      // تجديد التوكن عند 401
      if (response.statusCode == 401 && !isRetry) {
        final refreshed = await _tryRefreshToken();
        if (refreshed) {
          return sendMultipart(method, path, prepareRequest,
              timeout: timeout, isRetry: true);
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
