/// خدمة الفوترة — /api/billing/*
library;

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
  }) async {
    final body = <String, dynamic>{
      'provider': provider,
    };
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotency_key'] = idempotencyKey;
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
  }) {
    final body = <String, dynamic>{};
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      body['idempotency_key'] = idempotencyKey;
    }
    return ApiClient.post(
      '/api/billing/invoices/$invoiceId/complete-mock-payment/',
      body: body,
    );
  }
}
