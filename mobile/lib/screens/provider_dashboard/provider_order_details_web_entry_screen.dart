import 'package:flutter/material.dart';

import '../../models/provider_order.dart';
import '../../services/marketplace_api.dart';
import 'provider_order_details_screen.dart';

class ProviderOrderDetailsWebEntryScreen extends StatefulWidget {
  const ProviderOrderDetailsWebEntryScreen({
    super.key,
    required this.requestId,
  });

  final int requestId;

  @override
  State<ProviderOrderDetailsWebEntryScreen> createState() =>
      _ProviderOrderDetailsWebEntryScreenState();
}

class _ProviderOrderDetailsWebEntryScreenState
    extends State<ProviderOrderDetailsWebEntryScreen> {
  late Future<_ResolvedProviderOrderDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ResolvedProviderOrderDetail> _load() async {
    final data = await MarketplaceApi().getProviderRequestDetail(
      requestId: widget.requestId,
    );
    if (data == null) {
      throw StateError('تعذر تحميل تفاصيل الطلب.');
    }

    final details = Map<String, dynamic>.from(data);
    final rawStatus = _rawStatus(details);
    final order = _toProviderOrder(details);
    final requestType = (details['request_type'] ?? '').toString();
    final statusLogs = (details['status_logs'] is List)
        ? (details['status_logs'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];

    return _ResolvedProviderOrderDetail(
      order: order,
      rawStatus: rawStatus,
      requestType: requestType,
      statusLogs: statusLogs,
    );
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedProviderOrderDetail>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError || snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الطلب')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 44),
                    const SizedBox(height: 10),
                    const Text(
                      'تعذر تحميل تفاصيل الطلب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'رقم الطلب: ${widget.requestId}',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'إعادة المحاولة',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final resolved = snap.data!;
        return ProviderOrderDetailsScreen(
          order: resolved.order,
          requestId: widget.requestId,
          rawStatus: resolved.rawStatus,
          requestType: resolved.requestType,
          statusLogs: resolved.statusLogs,
        );
      },
    );
  }

  ProviderOrder _toProviderOrder(Map<String, dynamic> req) {
    DateTime parseDate(dynamic raw) =>
        DateTime.tryParse((raw ?? '').toString()) ?? DateTime.now();

    final attachmentsRaw = req['attachments'];
    final attachments = <ProviderOrderAttachment>[];
    if (attachmentsRaw is List) {
      for (final item in attachmentsRaw) {
        if (item is! Map) continue;
        final type = (item['file_type'] ?? 'file').toString();
        final url = (item['file_url'] ?? '').toString();
        attachments.add(
          ProviderOrderAttachment(
            name: url.isEmpty ? 'ملف مرفق' : url,
            type: type,
          ),
        );
      }
    }

    final estimatedAmount = _asDouble(req['estimated_service_amount']);
    final receivedAmount = _asDouble(req['received_amount']);
    final remainingAmount = (estimatedAmount != null && receivedAmount != null)
        ? (estimatedAmount - receivedAmount)
        : null;

    final statusAr = (req['status_label'] ?? '').toString().trim().isNotEmpty
        ? (req['status_label'] ?? '').toString().trim()
        : _mapStatus((req['status'] ?? '').toString());

    return ProviderOrder(
      id: '#${(_asInt(req['id'] ?? req['request_id']) ?? '').toString()}',
      serviceCode: (req['subcategory_name'] ?? '').toString(),
      createdAt: parseDate(req['created_at']),
      status: statusAr,
      clientName: (req['client_name'] ?? '-').toString(),
      clientHandle: '',
      clientPhone: (req['client_phone'] ?? '').toString(),
      clientCity: (req['city'] ?? '').toString(),
      title: (req['title'] ?? '').toString(),
      details: (req['description'] ?? '').toString(),
      attachments: attachments,
      expectedDeliveryAt: DateTime.tryParse(
        (req['expected_delivery_at'] ?? '').toString(),
      ),
      estimatedServiceAmountSR: estimatedAmount,
      receivedAmountSR: receivedAmount,
      remainingAmountSR: remainingAmount,
      deliveredAt: DateTime.tryParse((req['delivered_at'] ?? '').toString()),
      actualServiceAmountSR: _asDouble(req['actual_service_amount']),
      canceledAt: DateTime.tryParse((req['canceled_at'] ?? '').toString()),
      cancelReason: (req['cancel_reason'] ?? '').toString().trim().isEmpty
          ? null
          : (req['cancel_reason'] ?? '').toString(),
    );
  }

  String _rawStatus(Map<String, dynamic> req) {
    final raw = (req['status'] ?? '').toString().trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    final group = (req['status_group'] ?? '').toString().trim().toLowerCase();
    if (group == 'new') return 'new';
    if (group == 'in_progress') return 'in_progress';
    if (group == 'completed') return 'completed';
    if (group == 'cancelled') return 'cancelled';
    return '';
  }

  String _mapStatus(String status) {
    switch (status.toString().trim().toLowerCase()) {
      case 'open':
      case 'pending':
      case 'new':
      case 'sent':
        return 'جديد';
      case 'accepted':
        return 'بانتظار اعتماد العميل';
      case 'in_progress':
        return 'تحت التنفيذ';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
      case 'canceled':
      case 'expired':
        return 'ملغي';
      default:
        return 'جديد';
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString());
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }
}

class _ResolvedProviderOrderDetail {
  const _ResolvedProviderOrderDetail({
    required this.order,
    required this.rawStatus,
    required this.requestType,
    required this.statusLogs,
  });

  final ProviderOrder order;
  final String rawStatus;
  final String requestType;
  final List<Map<String, dynamic>> statusLogs;
}
