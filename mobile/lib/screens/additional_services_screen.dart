import 'package:flutter/material.dart';

import '../services/extras_service.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/platform_top_bar.dart';

class AdditionalServicesScreen extends StatefulWidget {
  const AdditionalServicesScreen({super.key});

  @override
  State<AdditionalServicesScreen> createState() =>
      _AdditionalServicesScreenState();
}

class _AdditionalServicesScreenState extends State<AdditionalServicesScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _catalogItems = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _myExtras = <Map<String, dynamic>>[];
  final Set<String> _buyingSkus = <String>{};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _asText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  List<Map<String, dynamic>> _extractList(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((item) =>
              item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
    }
    if (payload is Map && payload['results'] is List) {
      final list = payload['results'] as List;
      return list
          .whereType<Map>()
          .map((item) =>
              item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  String _statusLabel(String statusCode) {
    switch (statusCode.trim().toLowerCase()) {
      case 'pending_payment':
        return 'بانتظار الدفع';
      case 'active':
        return 'نشط';
      case 'consumed':
        return 'مستهلك';
      case 'expired':
        return 'منتهي';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير معروف';
    }
  }

  Color _statusColor(String statusCode) {
    switch (statusCode.trim().toLowerCase()) {
      case 'pending_payment':
        return Colors.amber.shade700;
      case 'active':
        return Colors.green.shade700;
      case 'consumed':
        return Colors.blue.shade700;
      case 'expired':
        return Colors.grey.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.black54;
    }
  }

  String _formatDate(String raw) {
    if (raw.trim().isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _priceLabel(dynamic value) {
    if (value == null) return '0 ر.س';
    final text = value.toString().trim();
    if (text.isEmpty) return '0 ر.س';
    return '$text ر.س';
  }

  Map<String, Map<String, dynamic>> _latestPurchaseBySku() {
    final sorted = List<Map<String, dynamic>>.from(_myExtras);
    sorted.sort((a, b) => _asInt(b['id']).compareTo(_asInt(a['id'])));
    final latest = <String, Map<String, dynamic>>{};
    for (final purchase in sorted) {
      final sku = _asText(purchase['sku']);
      if (sku.isEmpty) continue;
      latest.putIfAbsent(sku, () => purchase);
    }
    return latest;
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final responses = await Future.wait([
      ExtrasService.fetchCatalog(),
      ExtrasService.fetchMyExtras(),
    ]);

    if (!mounted) return;

    final catalogRes = responses[0];
    final myExtrasRes = responses[1];

    final catalog = catalogRes.isSuccess
        ? _extractList(catalogRes.data)
        : const <Map<String, dynamic>>[];
    final myExtras = myExtrasRes.isSuccess
        ? _extractList(myExtrasRes.data)
        : const <Map<String, dynamic>>[];

    setState(() {
      _catalogItems = catalog;
      _myExtras = myExtras;
      _isLoading = false;
      _errorMessage = catalogRes.isSuccess
          ? null
          : (catalogRes.error ?? 'تعذر تحميل كتالوج الخدمات الإضافية');
    });
  }

  Future<void> _buyExtra({
    required String sku,
    required String title,
  }) async {
    if (sku.isEmpty || _buyingSkus.contains(sku)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'تأكيد الطلب',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: Text(
            'هل تريد طلب خدمة "$title"؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'تأكيد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _buyingSkus.add(sku);
    });

    final result = await ExtrasService.buy(sku);
    if (!mounted) return;

    setState(() {
      _buyingSkus.remove(sku);
    });

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ?? 'فشل تنفيذ الطلب',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final data = result.dataAsMap;
    final code = _asText(data?['unified_request_code']);
    final msg = code.isEmpty
        ? 'تم إرسال طلب الخدمة بنجاح'
        : 'تم إرسال طلب الخدمة بنجاح ($code)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.green,
      ),
    );

    await _loadData(silent: true);
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'خدمات إضافية مرتبطة بالنظام',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF9A3412),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'يمكنك طلب الإضافات المتاحة لحسابك ومتابعة حالتها مباشرة كما تظهر في لوحة التحكم.',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF7C2D12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogCard(
    Map<String, dynamic> item,
    Map<String, dynamic>? purchase,
  ) {
    final sku = _asText(item['sku']);
    final title = _asText(item['title'], fallback: sku);
    final price = _priceLabel(item['price']);
    final statusCode = _asText(purchase?['status']).toLowerCase();
    final statusLabel = purchase == null ? null : _statusLabel(statusCode);
    final statusColor = _statusColor(statusCode);
    final isLocked = statusCode == 'active' || statusCode == 'pending_payment';
    final isBuying = _buyingSkus.contains(sku);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'SKU: $sku',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: Colors.black45,
                ),
              ),
              const Spacer(),
              if (statusLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (sku.isEmpty || isBuying || isLocked)
                  ? null
                  : () => _buyExtra(sku: sku, title: title),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                disabledBackgroundColor: Colors.deepPurple.withAlpha(70),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(double.infinity, 42),
              ),
              child: isBuying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isLocked
                          ? (statusCode == 'pending_payment'
                              ? 'قيد المعالجة'
                              : 'مفعّلة حالياً')
                          : 'طلب الخدمة',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyExtraCard(Map<String, dynamic> purchase) {
    final title = _asText(purchase['title'], fallback: 'خدمة إضافية');
    final sku = _asText(purchase['sku']);
    final statusCode = _asText(purchase['status']).toLowerCase();
    final status = _statusLabel(statusCode);
    final statusColor = _statusColor(statusCode);
    final createdAt = _formatDate(_asText(purchase['created_at']));
    final invoice = _asText(purchase['invoice'], fallback: '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SKU: $sku • فاتورة: $invoice • $createdAt',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    }

    if (_errorMessage != null && _catalogItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 54, color: Colors.grey[400]),
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final latestBySku = _latestPurchaseBySku();

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      color: Colors.deepPurple,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 14),
          const Text(
            'الكتالوج المتاح',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (_catalogItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'لا توجد خدمات إضافية متاحة حالياً.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  color: Colors.black54,
                ),
              ),
            )
          else
            ..._catalogItems.map((item) {
              final sku = _asText(item['sku']);
              return _buildCatalogCard(item, latestBySku[sku]);
            }),
          const SizedBox(height: 12),
          const Text(
            'طلباتي السابقة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (_myExtras.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'لا توجد طلبات خدمات إضافية بعد.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  color: Colors.black54,
                ),
              ),
            )
          else
            ..._myExtras.map(_buildMyExtraCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F8),
        appBar: PlatformTopBar(
          pageLabel: 'الخدمات الإضافية',
          showBackButton: true,
          trailingActions: [
            IconButton(
              onPressed: _isLoading ? null : () => _loadData(silent: true),
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _buildContent(),
        bottomNavigationBar: const CustomBottomNav(currentIndex: 3),
      ),
    );
  }
}
