import 'package:flutter/material.dart';

import '../services/subscriptions_service.dart';
import '../widgets/platform_top_bar.dart';
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

  static const List<String> _preferredTextKeys = <String>[
    'ar',
    'text',
    'label',
    'title',
    'name',
    'value',
    'display_name',
    'display',
    'value_text',
    'display_value',
    'message',
    'en',
  ];

  String _displayText(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;

    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? fallback : text;
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is List) {
      final parts = value
          .map((item) => _displayText(item))
          .where((item) => item.isNotEmpty)
          .toList();
      return parts.isEmpty ? fallback : parts.join('، ');
    }

    if (value is Map) {
      for (final key in _preferredTextKeys) {
        if (value.containsKey(key)) {
          final text = _displayText(value[key]);
          if (text.isNotEmpty) return text;
        }
      }

      for (final entry in value.entries) {
        final text = _displayText(entry.value);
        if (text.isNotEmpty) return text;
      }

      return fallback;
    }

    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = _displayText(value).toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

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
    final state = _displayText(action['state']).toLowerCase();
    switch (state) {
      case 'current':
      case 'pending':
        return _displayText(action['label']);
      case 'unavailable':
        return 'باقة أقل من الحالية';
      default:
        return '';
    }
  }

  List<Color> _gradientForTier(Map<String, dynamic> plan) {
    final tier = _displayText(
      SubscriptionsService.planOffer(plan)['tier'] ?? plan['canonical_tier'],
    ).toLowerCase();
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth <= 390;
    final veryCompact = screenWidth <= 360;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        appBar: const PlatformTopBar(
          pageLabel: 'باقات اشتراك مقدم الخدمة',
          showBackButton: true,
          showNotificationAction: false,
          showChatAction: false,
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
                : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 12,
                          compact ? 10 : 14,
                          compact ? 10 : 12,
                          0,
                        ),
                        child: const Text(
                          'اختر الباقة المناسبة لإكمال الترقية.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 12,
                      compact ? 10 : 14,
                      compact ? 10 : 12,
                      compact ? 10 : 12,
                    ),
                    itemCount: _plans.length,
                    itemBuilder: (context, index) => _planCard(
                      _plans[index],
                      compact: compact,
                      veryCompact: veryCompact,
                    ),
                  ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _planCard(
    Map<String, dynamic> plan, {
    required bool compact,
    required bool veryCompact,
  }) {
    final offer = SubscriptionsService.planOffer(plan);
    final action = _actionForPlan(plan);
    final rows = _rowsForPlan(plan);
    final colors = _gradientForTier(plan);
    final planName = _displayText(
      SubscriptionsService.planDisplayTitle(plan),
      fallback: 'الباقة',
    );
    final description = _displayText(offer['description']);
    final annualPrice = _displayText(offer['annual_price_label'], fallback: 'مجانية');
    final verificationEffect = _displayText(offer['verification_effect_label']);
    final buttonLabel = _displayText(action['label'], fallback: 'ترقية');
    final canOpen = _asBool(action['enabled']);
    final badgeText = _statusBadgeText(action);

    Widget priceChip({required bool fullWidth}) {
      return Container(
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? null
            : BoxConstraints(minWidth: compact ? 96 : 110),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(34),
          borderRadius: BorderRadius.circular(compact ? 16 : 18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'السعر السنوي',
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 11 : 12,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            Text(
              annualPrice,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 12 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 20 : 26),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: compact ? 18 : 24,
            offset: Offset(0, compact ? 10 : 14),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (veryCompact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        planName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: veryCompact ? 18 : (compact ? 20 : 24),
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      if (badgeText.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 9 : 10,
                            vertical: compact ? 4 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: colors.last,
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.7,
                      fontSize: compact ? 13 : 14,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  priceChip(fullWidth: true),
                ],
              )
            else
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: veryCompact ? 18 : (compact ? 20 : 24),
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            if (badgeText.isNotEmpty)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 9 : 10,
                                  vertical: compact ? 4 : 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(220),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: colors.last,
                                    fontSize: compact ? 11 : 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.7,
                            fontSize: compact ? 13 : 14,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  priceChip(fullWidth: false),
                ],
              ),
            SizedBox(height: compact ? 14 : 18),
            Container(
              padding: EdgeInsets.all(compact ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
              ),
              child: Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _displayText(
                                  row['label'] ?? row['title'] ?? row['name'],
                                ),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: compact ? 12 : 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            SizedBox(width: compact ? 10 : 12),
                            Expanded(
                              child: Text(
                                _displayText(
                                  row['value'] ?? row['text'] ?? row['amount'],
                                ),
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 12 : 13,
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
            SizedBox(height: compact ? 14 : 18),
            Text(
              'أثر الباقة على التوثيق: $verificationEffect',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.7,
                fontSize: compact ? 13 : 14,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: compact ? 12 : 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canOpen ? () => _openSummary(plan) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colors.last,
                  disabledBackgroundColor: Colors.white24,
                  disabledForegroundColor: Colors.white70,
                  padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  ),
                ),
                child: Text(
                  buttonLabel,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 14 : 15,
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
