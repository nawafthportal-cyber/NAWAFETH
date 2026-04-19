import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PaymentReturnPayload {
  final String status;
  final String invoiceCode;
  final String requestCode;
  final String message;

  const PaymentReturnPayload({
    required this.status,
    required this.invoiceCode,
    required this.requestCode,
    required this.message,
  });

  bool get isSuccess => status == 'success' || status == 'already_paid';

  static PaymentReturnPayload? fromUri(Uri uri) {
    if (uri.scheme != 'nawafeth' || uri.host != 'payment-return') return null;
    final status = (uri.queryParameters['payment'] ?? '').trim().toLowerCase();
    if (status.isEmpty) return null;

    final invoiceCode = (uri.queryParameters['invoice'] ??
            uri.queryParameters['invoice_code'] ??
            '')
        .trim();
    final requestCode = (uri.queryParameters['request_code'] ??
            uri.queryParameters['order_code'] ??
            '')
        .trim();

    final message = isSuccessStatus(status)
        ? 'تمت عملية الدفع بنجاح. رقم الطلب: ${requestCode.isNotEmpty ? requestCode : 'غير متوفر'}${invoiceCode.isNotEmpty ? '، ورقم الفاتورة: $invoiceCode' : ''}.'
        : status == 'cancelled'
            ? 'تم إلغاء عملية الدفع، ويمكنك إعادة المحاولة متى رغبت.'
            : 'تعذر إتمام عملية الدفع. لم يتم اعتماد السداد، ويمكنك إعادة المحاولة.';

    return PaymentReturnPayload(
      status: status,
      invoiceCode: invoiceCode,
      requestCode: requestCode,
      message: message,
    );
  }

  static bool isSuccessStatus(String status) {
    return status == 'success' || status == 'already_paid';
  }
}

class PaymentReturnService {
  static const MethodChannel _channel = MethodChannel('nawafeth/deep_links');
  static final StreamController<PaymentReturnPayload> _controller =
      StreamController<PaymentReturnPayload>.broadcast();

  static Stream<PaymentReturnPayload> get stream => _controller.stream;

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink' && call.arguments is String) {
        handleUriString(call.arguments as String);
      }
    });

    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.trim().isNotEmpty) {
        handleUriString(initial);
      }
    } catch (_) {}
  }

  static void handleUriString(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    final payload = PaymentReturnPayload.fromUri(uri);
    if (payload == null) return;
    _controller.add(payload);
  }

  static void showSnackBar(
    BuildContext context,
    PaymentReturnPayload payload,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            payload.message,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: payload.isSuccess
              ? const Color(0xFF0F766E)
              : const Color(0xFFB45309),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
  }
}
