/// خدمة الفوترة — /api/billing/*
library;

import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

class BillingService {
  /// جلب فواتيري
  static Future<ApiResponse> fetchMyInvoices() {
    return ApiClient.get('/api/billing/invoices/my/');
  }

  /// جلب تفاصيل فاتورة
  static Future<ApiResponse> fetchInvoiceDetail(int invoiceId) {
    return ApiClient.get('/api/billing/invoices/$invoiceId/');
  }

  /// بدء عملية الدفع
  static Future<ApiResponse> initPayment({
    required int invoiceId,
    String provider = 'mock',
    String? idempotencyKey,
    String? paymentMethod,
  }) async {
    final body = <String, dynamic>{
      'provider': provider,
    };
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotency_key'] = idempotencyKey;
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      body['payment_method'] = paymentMethod;
    }
    return ApiClient.post(
      '/api/billing/invoices/$invoiceId/init-payment/',
      body: body,
    );
  }

  /// إتمام الدفع التجريبي وربط الـ webhook الداخلي
  static Future<ApiResponse> completeMockPayment({
    required int invoiceId,
    String? idempotencyKey,
    String? paymentMethod,
  }) {
    final body = <String, dynamic>{};
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotency_key'] = idempotencyKey;
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      body['payment_method'] = paymentMethod;
    }
    return ApiClient.post(
      '/api/billing/invoices/$invoiceId/complete-mock-payment/',
      body: body,
    );
  }

  static Uri buildAppPaymentReturnUri({
    required String requestCode,
  }) {
    return Uri(
      scheme: 'nawafeth',
      host: 'payment-return',
      queryParameters: {
        if (requestCode.trim().isNotEmpty) 'request_code': requestCode.trim(),
      },
    );
  }

  static Uri checkoutUriWithReturn({
    required String checkoutUrl,
    required String requestCode,
  }) {
    var checkoutUri = Uri.parse(checkoutUrl);
    checkoutUri = _normalizeCheckoutOriginForApp(checkoutUri);
    final params = Map<String, String>.from(checkoutUri.queryParameters);
    params['next'] = buildAppPaymentReturnUri(
      requestCode: requestCode,
    ).toString();
    return checkoutUri.replace(queryParameters: params);
  }

  static Future<bool> openCheckout({
    required String checkoutUrl,
    required String requestCode,
  }) {
    final uri = checkoutUriWithReturn(
      checkoutUrl: checkoutUrl,
      requestCode: requestCode,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Uri _normalizeCheckoutOriginForApp(Uri checkoutUri) {
    final apiBase = Uri.tryParse(ApiClient.baseUrl);
    if (apiBase == null || !apiBase.hasAuthority) return checkoutUri;

    final checkoutHost = checkoutUri.host.trim().toLowerCase();
    final apiHost = apiBase.host.trim().toLowerCase();
    final shouldUseApiOrigin = checkoutHost == '127.0.0.1' ||
        checkoutHost == 'localhost' ||
        checkoutHost == '10.0.2.2' ||
        checkoutHost.isEmpty;
    if (!shouldUseApiOrigin || checkoutHost == apiHost) return checkoutUri;

    final authorityHostPort = apiBase.authority.split('@').last;
    final hasExplicitPort = RegExp(r':\d+$').hasMatch(authorityHostPort);
    return Uri(
      scheme: apiBase.scheme,
      userInfo: checkoutUri.userInfo,
      host: apiBase.host,
      port: hasExplicitPort ? apiBase.port : null,
      path: checkoutUri.path,
      queryParameters: checkoutUri.queryParameters.isEmpty
          ? null
          : checkoutUri.queryParameters,
      fragment: checkoutUri.fragment.isEmpty ? null : checkoutUri.fragment,
    );
  }
}
