import 'package:flutter/material.dart';

import '../services/subscriptions_service.dart';
import 'plan_summary_screen.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rowsForPlan(Map<String, dynamic> plan) {
    final offer = SubscriptionsService.planOffer(plan);
    final rows = offer['card_rows'];
    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Map<String, dynamic> _actionForPlan(Map<String, dynamic> plan) {
    return SubscriptionsService.planAction(plan);
  }

  String _statusBadgeText(Map<String, dynamic> action) {
    final state = (action['state'] ?? '').toString();
    switch (state) {
      case 'current':
      case 'pending':
        return (action['label'] ?? '').toString();
      case 'unavailable':
        return 'باقة أقل من الحالية';
      default:
        return '';
    }
  }

  List<Color> _gradientForTier(Map<String, dynamic> plan) {
    final tier =
        (SubscriptionsService.planOffer(plan)['tier'] ?? plan['canonical_tier'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    switch (tier) {
      case 'professional':
        return const [Color(0xFF123C32), Color(0xFF0F766E)];
      case 'pioneer':
        return const [Color(0xFF0F4C5C), Color(0xFF2A9D8F)];
      default:
        return const [Color(0xFF5F6F52), Color(0xFFA3B18A)];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final plans = await SubscriptionsService.getPlans();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _loading = false;
      if (plans.isEmpty) {
        _error = 'لا توجد باقات متاحة حالياً';
      }
    });
  }

  Future<void> _openSummary(Map<String, dynamic> plan) async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlanSummaryScreen(plan: plan),
      ),
    );
    if (refreshed == true && mounted) {
      await _loadPlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        appBar: AppBar(
          title: const Text(
            'باقات اشتراك مقدم الخدمة',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(fontFamily: 'Cairo')),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadPlans,
                          child: const Text(
                            'إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    itemCount: _plans.length,
                    itemBuilder: (context, index) => _planCard(_plans[index]),
                  ),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final offer = SubscriptionsService.planOffer(plan);
    final action = _actionForPlan(plan);
    final rows = _rowsForPlan(plan);
    final colors = _gradientForTier(plan);
    final planName = SubscriptionsService.planDisplayTitle(plan);
    final description = (offer['description'] ?? '').toString();
    final verificationEffect = (offer['verification_effect_label'] ?? '').toString();
    final buttonLabel = (action['label'] ?? 'ترقية').toString();
    final canOpen = action['enabled'] == true;
    final badgeText = _statusBadgeText(action);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            planName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          if (badgeText.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(220),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  color: colors.last,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.8,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(34),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'السعر السنوي',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (offer['annual_price_label'] ?? 'مجانية').toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                (row['label'] ?? '').toString(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                (row['value'] ?? '').toString(),
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
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
            const SizedBox(height: 18),
            Text(
              'أثر الباقة على التوثيق: $verificationEffect',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.8,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canOpen ? () => _openSummary(plan) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colors.last,
                  disabledBackgroundColor: Colors.white24,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
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
}
