import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../services/billing_api.dart';
import '../services/extras_api.dart';
import '../services/payment_checkout.dart';
import '../utils/auth_guard.dart';
import '../widgets/bottom_nav.dart';

class ExtraServicesScreen extends StatefulWidget {
  const ExtraServicesScreen({super.key});

  @override
  State<ExtraServicesScreen> createState() => _ExtraServicesScreenState();
}

class _ExtraServicesScreenState extends State<ExtraServicesScreen>
    with SingleTickerProviderStateMixin {
  final BillingApi _billingApi = BillingApi();
  final ExtrasApi _extrasApi = ExtrasApi();

  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _catalogFuture;
  late Future<List<Map<String, dynamic>>> _myExtrasFuture;
  final Set<String> _buyingSkus = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _catalogFuture = Future.value(const <Map<String, dynamic>>[]);
    _myExtrasFuture = Future.value(const <Map<String, dynamic>>[]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ok = await checkAuth(context);
      if (!ok && mounted) {
        Navigator.of(context).maybePop();
        return;
      }
      _reload();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _catalogFuture = _extrasApi.getCatalog();
      _myExtrasFuture = _extrasApi.getMyExtras();
    });
  }

  Future<void> _buyExtra(Map<String, dynamic> item) async {
    final sku = (item['sku'] ?? '').toString().trim();
    if (sku.isEmpty || _buyingSkus.contains(sku)) return;

    setState(() => _buyingSkus.add(sku));
    try {
      final purchase = await _extrasApi.buy(sku);
      if (!mounted) return;

      final unifiedCode = (purchase['unified_request_code'] ?? '').toString().trim();
      final invoiceId = _asInt(purchase['invoice']);
      if (invoiceId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              unifiedCode.isNotEmpty
                  ? 'تم إنشاء طلب الإضافة ($unifiedCode) لكن رقم الفاتورة غير متوفر.'
                  : 'تم إنشاء طلب الإضافة لكن رقم الفاتورة غير متوفر.',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
        _reload();
        return;
      }

      await PaymentCheckout.initAndOpen(
        context: context,
        billingApi: _billingApi,
        invoiceId: invoiceId,
        idempotencyKey: 'extra-$sku-${DateTime.now().millisecondsSinceEpoch}',
        successMessage: unifiedCode.isNotEmpty
            ? 'تم إنشاء طلب الإضافة ($unifiedCode) وفتح صفحة الدفع.'
            : 'تم إنشاء طلب الإضافة وفتح صفحة الدفع.',
      );
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _extractError(e, fallback: 'تعذر شراء الإضافة.'),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر شراء الإضافة.', style: TextStyle(fontFamily: 'Cairo'))),
      );
    } finally {
      if (mounted) {
        setState(() => _buyingSkus.remove(sku));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'الخدمات الإضافية',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _HeaderBanner(
            title: 'خدمات إضافية مدفوعة',
            subtitle: 'اشترِ إضافات احترافية لحسابك وتابع مشترياتك من شاشة مستقلة.',
            icon: Icons.add_box_outlined,
            colors: const [Color(0xFFF07B2A), Color(0xFFE35A20)],
            onRefresh: _reload,
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.deepPurple,
              unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65),
              indicatorColor: AppColors.deepPurple,
              labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
              tabs: const [
                Tab(text: 'كتالوج الإضافات'),
                Tab(text: 'مشترياتي'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCatalogTab(isDark: isDark),
                _buildMyExtrasTab(isDark: isDark),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
    );
  }

  Widget _buildCatalogTab({required bool isDark}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.error_outline,
            text: 'تعذر تحميل كتالوج الخدمات الإضافية.',
            action: 'إعادة المحاولة',
            onTap: _reload,
          );
        }

        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) {
          return _StateMessage(
            icon: Icons.inventory_2_outlined,
            text: 'لا توجد إضافات متاحة حالياً.',
            action: 'تحديث',
            onTap: _reload,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final sku = (item['sku'] ?? '').toString().trim();
              final title = (item['title'] ?? sku.isEmpty ? 'إضافة' : sku).toString();
              final desc = (item['description'] ?? item['summary'] ?? '').toString().trim();
              final price = (item['price'] ?? '-').toString();
              final buying = sku.isNotEmpty && _buyingSkus.contains(sku);

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Colors.white.withValues(alpha: 0.03), Colors.white.withValues(alpha: 0.01)]
                        : [Colors.white, const Color(0xFFFFF7F1)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.10)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.deepPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.auto_awesome_outlined, color: AppColors.deepPurple),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$price ر.س',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w800,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (sku.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'SKU: $sku',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          desc,
                          style: const TextStyle(fontFamily: 'Cairo', height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: sku.isEmpty || buying ? null : () => _buyExtra(item),
                          icon: buying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.shopping_cart_checkout_outlined),
                          label: Text(
                            buying ? 'جارٍ إنشاء الطلب...' : 'شراء الإضافة',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMyExtrasTab({required bool isDark}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _myExtrasFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.receipt_long_outlined,
            text: 'تعذر تحميل مشتريات الخدمات الإضافية.',
            action: 'إعادة المحاولة',
            onTap: _reload,
          );
        }

        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) {
          return _StateMessage(
            icon: Icons.shopping_bag_outlined,
            text: 'لا توجد مشتريات إضافات حالياً.',
            action: 'تحديث',
            onTap: _reload,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final title = (item['title'] ?? item['sku'] ?? 'إضافة').toString();
              final status = (item['status'] ?? '-').toString();
              final invoice = (item['invoice'] ?? '-').toString();
              final style = _statusStyle(status);
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: style.$1.withValues(alpha: 0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: style.$1.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(style.$2, color: style.$1, size: 20),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'الحالة: ${_statusLabel(status)}\nرقم الفاتورة: $invoice',
                      style: const TextStyle(fontFamily: 'Cairo', height: 1.4),
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: style.$1.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        color: style.$1,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  (Color, IconData) _statusStyle(String status) {
    final s = status.trim().toLowerCase();
    if ({'rejected', 'failed', 'cancelled', 'canceled', 'expired'}.contains(s)) {
      return (Colors.red.shade700, Icons.cancel_outlined);
    }
    if ({'pending', 'submitted', 'processing', 'unpaid', 'new', 'created'}.contains(s)) {
      return (Colors.orange.shade800, Icons.schedule_outlined);
    }
    if ({'approved', 'active', 'paid', 'completed'}.contains(s)) {
      return (Colors.green.shade700, Icons.check_circle_outline);
    }
    return (AppColors.deepPurple, Icons.info_outline);
  }

  String _statusLabel(String raw) {
    const labels = <String, String>{
      'pending': 'قيد المراجعة',
      'submitted': 'تم الإرسال',
      'processing': 'قيد المعالجة',
      'unpaid': 'غير مدفوع',
      'paid': 'مدفوع',
      'approved': 'مقبول',
      'active': 'نشط',
      'completed': 'مكتمل',
      'rejected': 'مرفوض',
      'failed': 'فشل',
      'cancelled': 'ملغي',
      'canceled': 'ملغي',
      'expired': 'منتهي',
      'new': 'جديد',
      'created': 'منشأ',
    };
    final key = raw.trim().toLowerCase();
    return labels[key] ?? raw;
  }

  String _extractError(DioException e, {required String fallback}) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
      for (final value in data.values) {
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is List && value.isNotEmpty && value.first is String) {
          final first = (value.first as String).trim();
          if (first.isNotEmpty) return first;
        }
      }
    }
    return fallback;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

class _HeaderBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onRefresh;

  const _HeaderBanner({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  const _StateMessage({
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.deepPurple, size: 28),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: onTap,
              child: Text(action, style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }
}
