import 'package:flutter/material.dart';

import '../services/subscriptions_service.dart';
import '../widgets/platform_top_bar.dart';

class PlanSummaryScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const PlanSummaryScreen({
    super.key,
    required this.plan,
  });

  @override
  State<PlanSummaryScreen> createState() => _PlanSummaryScreenState();
}

class _PlanSummaryScreenState extends State<PlanSummaryScreen> {
  bool _submitting = false;

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Future<void> _submit() async {
    final action = SubscriptionsService.planAction(widget.plan);
    if (action['enabled'] != true) return;

    final planId = _toInt(widget.plan['id']);
    if (planId == null || planId <= 0) return;

    setState(() => _submitting = true);
    final result = await SubscriptionsService.subscribe(planId);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'تعذر إنشاء طلب الاشتراك')),
      );
      return;
    }

    final offer = SubscriptionsService.planOffer(widget.plan);
    final amountLabel =
        (offer['final_payable_label'] ?? offer['annual_price_label'] ?? 'مجانية')
            .toString();

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تم تسجيل الاشتراك بنجاح'),
          content: Text('سيتم إشعاركم بتفعيل الاشتراك بعد مراجعة فريق الاشتراكات. المبلغ النهائي: $amountLabel'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final offer = SubscriptionsService.planOffer(widget.plan);
    final action = SubscriptionsService.planAction(widget.plan);
    final rows = _mapList(offer['summary_rows']);
    final features = (offer['feature_bullets'] is List)
        ? (offer['feature_bullets'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : const <String>[];

    final planName = SubscriptionsService.planDisplayTitle(widget.plan);
    final billingCycle = (offer['billing_cycle_label'] ?? 'سنوي').toString();
    final annualPrice = (offer['annual_price_label'] ?? 'مجانية').toString();
    final finalAmount = (offer['final_payable_label'] ?? annualPrice).toString();
    final verificationEffect =
        (offer['verification_effect_label'] ?? '—').toString();
    final taxNote = (offer['tax_note'] ?? '').toString();
    final buttonLabel = (action['label'] ?? 'ترقية').toString();
    final canSubmit = action['enabled'] == true && !_submitting;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        appBar: const PlatformTopBar(
          pageLabel: 'ملخص طلب الترقية والتكلفة',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F4C5C), Color(0xFF2A9D8F)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x220F4C5C),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    planName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (offer['description'] ?? '').toString(),
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.7,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(32),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المبلغ النهائي',
                          style: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          finalAmount,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          billingCycle,
                          style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'تفاصيل الاشتراك',
              child: Column(
                children: [
                  _infoRow('الباقة المختارة', planName),
                  _infoRow('دورة الفوترة', billingCycle),
                  _infoRow('سعر الباقة', annualPrice),
                  _infoRow('أثر التوثيق', verificationEffect),
                  _infoRow('المبلغ النهائي المستحق', finalAmount, emphasize: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'المزايا الرئيسية',
              child: Column(
                children: features
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '•',
                              style: TextStyle(
                                color: Color(0xFF0F766E),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  height: 1.7,
                                  color: Color(0xFF1E293B),
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'تفاصيل المقارنة',
              child: Column(
                children: rows
                    .map(
                      (row) => _infoRow(
                        (row['label'] ?? '').toString(),
                        (row['value'] ?? '').toString(),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ملاحظة الضريبة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    taxNote,
                    style: const TextStyle(
                      height: 1.8,
                      color: Color(0xFF475569),
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: emphasize ? const Color(0xFF0F766E) : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
