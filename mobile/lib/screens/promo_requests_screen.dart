import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../services/billing_api.dart';
import '../services/payment_checkout.dart';
import '../services/promo_api.dart';
import '../utils/auth_guard.dart';
import '../widgets/bottom_nav.dart';

class PromoRequestsScreen extends StatefulWidget {
  const PromoRequestsScreen({super.key});

  @override
  State<PromoRequestsScreen> createState() => _PromoRequestsScreenState();
}

class _PromoRequestsScreenState extends State<PromoRequestsScreen> {
  final BillingApi _billingApi = BillingApi();
  final PromoApi _promoApi = PromoApi();

  late Future<List<Map<String, dynamic>>> _myPromoFuture;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _targetCategoryCtrl = TextEditingController();
  final TextEditingController _targetCityCtrl = TextEditingController();
  final TextEditingController _redirectUrlCtrl = TextEditingController();

  DateTime? _startAt;
  DateTime? _endAt;
  String _adType = 'banner_home';
  String _frequency = '60s';
  String _position = 'normal';
  bool _submittingPromo = false;

  static const Map<String, String> _adTypeLabels = {
    'banner_home': 'بانر الرئيسية',
    'banner_category': 'بانر القسم',
    'banner_search': 'بانر البحث',
    'popup_home': 'نافذة منبثقة رئيسية',
    'popup_category': 'نافذة منبثقة داخل القسم',
    'featured_top5': 'تمييز ضمن أول 5',
    'featured_top10': 'تمييز ضمن أول 10',
    'boost_profile': 'تعزيز الملف',
    'push_notification': 'إشعار Push',
  };

  static const Map<String, String> _frequencyLabels = {
    '10s': 'كل 10 ثواني',
    '20s': 'كل 20 ثانية',
    '30s': 'كل 30 ثانية',
    '60s': 'كل 60 ثانية',
  };

  static const Map<String, String> _positionLabels = {
    'first': 'الأول',
    'second': 'الثاني',
    'top5': 'ضمن أول 5',
    'top10': 'ضمن أول 10',
    'normal': 'عادي',
  };

  @override
  void initState() {
    super.initState();
    _myPromoFuture = Future.value(const <Map<String, dynamic>>[]);
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
    _titleCtrl.dispose();
    _targetCategoryCtrl.dispose();
    _targetCityCtrl.dispose();
    _redirectUrlCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _myPromoFuture = _promoApi.getMyRequests();
    });
  }

  Future<void> _createPromo() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _startAt == null || _endAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكمل عنوان الحملة وتواريخ البداية والنهاية.', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    if (!_endAt!.isAfter(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاريخ النهاية يجب أن يكون بعد تاريخ البداية.', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    setState(() => _submittingPromo = true);
    try {
      final payload = {
        'title': title,
        'ad_type': _adType,
        'start_at': _startAt!.toUtc().toIso8601String(),
        'end_at': _endAt!.toUtc().toIso8601String(),
        'frequency': _frequency,
        'position': _position,
        'target_category': _targetCategoryCtrl.text.trim(),
        'target_city': _targetCityCtrl.text.trim(),
        'redirect_url': _redirectUrlCtrl.text.trim(),
      };

      final created = await _promoApi.createRequest(payload);
      if (!mounted) return;
      final invoiceId = _asInt(created['invoice']);
      if (invoiceId != null) {
        await PaymentCheckout.initAndOpen(
          context: context,
          billingApi: _billingApi,
          invoiceId: invoiceId,
          idempotencyKey: 'promo-${created['id'] ?? title}-${DateTime.now().millisecondsSinceEpoch}',
          successMessage: 'تم إنشاء طلب الترويج وفتح صفحة الدفع.',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إنشاء طلب الترويج: ${created['code'] ?? '#${created['id'] ?? '-'}'}',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }

      _titleCtrl.clear();
      _targetCategoryCtrl.clear();
      _targetCityCtrl.clear();
      _redirectUrlCtrl.clear();
      setState(() {
        _startAt = null;
        _endAt = null;
      });
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(e, fallback: 'تعذر إنشاء طلب الترويج.'), style: const TextStyle(fontFamily: 'Cairo'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء طلب الترويج.', style: TextStyle(fontFamily: 'Cairo'))),
      );
    } finally {
      if (mounted) setState(() => _submittingPromo = false);
    }
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
      } else {
        _endAt = dt;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'الترويج',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _myPromoFuture,
        builder: (context, snapshot) {
          final promoItems = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
                _PromoHero(onRefresh: _reload),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'إنشاء حملة ترويجية',
                  icon: Icons.campaign_outlined,
                  child: Column(
                    children: [
                      _inputField(
                        controller: _titleCtrl,
                        label: 'عنوان الحملة',
                        icon: Icons.title_outlined,
                      ),
                      const SizedBox(height: 10),
                      _dropdownField(
                        label: 'نوع الإعلان',
                        value: _adType,
                        icon: Icons.ads_click_outlined,
                        items: _adTypeLabels,
                        onChanged: (v) => setState(() => _adType = v ?? _adType),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _dropdownField(
                              label: 'التكرار',
                              value: _frequency,
                              icon: Icons.timer_outlined,
                              items: _frequencyLabels,
                              onChanged: (v) => setState(() => _frequency = v ?? _frequency),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dropdownField(
                              label: 'الموضع',
                              value: _position,
                              icon: Icons.vertical_align_top_outlined,
                              items: _positionLabels,
                              onChanged: (v) => setState(() => _position = v ?? _position),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DateButton(
                              label: _startAt == null ? 'تاريخ البداية' : _formatDateTime(_startAt!),
                              icon: Icons.event_available_outlined,
                              onTap: () => _pickDateTime(isStart: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DateButton(
                              label: _endAt == null ? 'تاريخ النهاية' : _formatDateTime(_endAt!),
                              icon: Icons.event_busy_outlined,
                              onTap: () => _pickDateTime(isStart: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _targetCategoryCtrl,
                        label: 'الفئة المستهدفة (اختياري)',
                        icon: Icons.category_outlined,
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _targetCityCtrl,
                        label: 'المدينة المستهدفة (اختياري)',
                        icon: Icons.location_city_outlined,
                      ),
                      const SizedBox(height: 10),
                      _inputField(
                        controller: _redirectUrlCtrl,
                        label: 'رابط التحويل (اختياري)',
                        icon: Icons.link_outlined,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submittingPromo ? null : _createPromo,
                          icon: _submittingPromo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            _submittingPromo ? 'جارٍ إرسال الطلب...' : 'إرسال طلب الترويج',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'طلباتي الترويجية',
                  icon: Icons.list_alt_outlined,
                  child: Builder(
                    builder: (context) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return _InlineStateMessage(
                          text: 'تعذر تحميل طلبات الترويج.',
                          action: 'إعادة المحاولة',
                          onTap: _reload,
                        );
                      }
                      if (promoItems.isEmpty) {
                        return _InlineStateMessage(
                          text: 'لا توجد طلبات ترويج حالياً.',
                          action: 'تحديث',
                          onTap: _reload,
                        );
                      }

                      return Column(
                        children: promoItems.map((item) {
                          final status = (item['status'] ?? '-').toString();
                          final style = _statusStyle(status);
                          final title = (item['title'] ?? item['code'] ?? 'طلب ترويج').toString();
                          final code = (item['code'] ?? '').toString();
                          final invoice = (item['invoice'] ?? '-').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: style.$1.withValues(alpha: 0.20)),
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
                              subtitle: Text(
                                'الحالة: ${_statusLabel(status)}${code.isEmpty ? '' : '\nالكود: $code'}\nالفاتورة: $invoice',
                                style: const TextStyle(fontFamily: 'Cairo', height: 1.4),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.deepPurple),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      style: const TextStyle(fontFamily: 'Cairo'),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required IconData icon,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.deepPurple),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items.entries
          .map(
            (e) => DropdownMenuItem<String>(
              value: e.key,
              child: Text(e.value, style: const TextStyle(fontFamily: 'Cairo')),
            ),
          )
          .toList(),
    );
  }

  String _formatDateTime(DateTime value) {
    final date = '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final time = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
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

class _PromoHero extends StatelessWidget {
  final VoidCallback onRefresh;

  const _PromoHero({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1F5C25)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F5C25).withValues(alpha: 0.18),
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
            child: const Icon(Icons.campaign_outlined, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إدارة حملات الترويج',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'أنشئ طلب ترويج جديد وتابع حالة حملاتك من صفحة مستقلة.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.35,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deepPurple.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.deepPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.deepPurple, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _InlineStateMessage extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onTap;

  const _InlineStateMessage({
    required this.text,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(text, style: const TextStyle(fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(fontFamily: 'Cairo'))),
        ],
      ),
    );
  }
}
