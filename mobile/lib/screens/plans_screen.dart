import 'package:flutter/material.dart';
import '../services/subscriptions_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _currentSubscription;
  bool _loading = true;
  String? _error;
  bool _subscribing = false;

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _translateFeatureKey(String key) {
    switch (key.trim().toLowerCase()) {
      case 'verify_blue':
      case 'verify_green':
        return 'رسوم التوثيق تعتمد على فئة الباقة';
      case 'promo_ads':
        return 'إعلانات وترويج';
      case 'priority_support':
        return 'دعم أولوية';
      case 'extra_uploads':
        return 'سعة مرفقات إضافية';
      case 'advanced_analytics':
        return 'تحليلات متقدمة';
      default:
        return key.replaceAll('_', ' ').trim();
    }
  }

  List<String> _extractFeatures(Map<String, dynamic> plan) {
    final labels = plan['feature_labels'];
    if (labels is List) {
      final parsed = labels
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }

    final rawFeatures = plan['features'];
    if (rawFeatures is! List) return const <String>[];
    final extracted = rawFeatures
        .map((item) {
          if (item is String) return _translateFeatureKey(item);
          if (item is Map) {
            return (item['title'] ?? item['name'] ?? '').toString().trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList();
    return extracted.toSet().toList();
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
    final results = await Future.wait<List<Map<String, dynamic>>>([
      SubscriptionsService.getPlans(),
      SubscriptionsService.mySubscriptions(),
    ]);
    final plans = results[0];
    final mySubscriptions = results[1];

    if (!mounted) return;

    if (plans.isEmpty) {
      setState(() {
        _error = 'لا توجد باقات متاحة حالياً';
        _currentSubscription =
            SubscriptionsService.selectPreferredSubscription(mySubscriptions);
        _loading = false;
      });
      return;
    }
    setState(() {
      _plans = plans;
      _currentSubscription =
          SubscriptionsService.selectPreferredSubscription(mySubscriptions);
      _loading = false;
    });
  }

  Future<void> _subscribe(int planId, String planTitle) async {
    setState(() => _subscribing = true);
    final res = await SubscriptionsService.subscribe(planId);
    if (!mounted) return;
    setState(() => _subscribing = false);

    if (res.isSuccess) {
      await showDialog(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 30),
              SizedBox(width: 10),
              Text('تم الاشتراك'),
            ]),
            content: Text(
              'تم الاشتراك في باقة $planTitle بنجاح.',
              style: const TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      await _loadPlans();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error ?? 'فشل الاشتراك',
            style: const TextStyle(fontFamily: 'Cairo')),
      ));
    }
  }

  // Cycle gradient and icon per index
  static const _gradients = [
    [Color(0xFF42A5F5), Color(0xFF1565C0)], // blue
    [Color(0xFF7E57C2), Color(0xFF4527A0)], // purple
    [Color(0xFFFFA726), Color(0xFFE65100)], // orange
    [Color(0xFF26A69A), Color(0xFF00695C)], // teal
  ];
  static const _icons = [
    Icons.star_border,
    Icons.workspace_premium,
    Icons.verified,
    Icons.diamond,
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('الباقات المدفوعة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
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
                      Text(_error!,
                          style: const TextStyle(fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _loadPlans,
                          child: const Text('إعادة المحاولة',
                              style: TextStyle(fontFamily: 'Cairo'))),
                    ]))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: ListView.builder(
                      itemCount: _plans.length,
                      itemBuilder: (context, index) {
                        final plan = _plans[index];
                        final g = _gradients[index % _gradients.length];
                        final icon = _icons[index % _icons.length];
                        return _planCard(plan, g[0], g[1], icon);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _planCard(
      Map<String, dynamic> plan, Color c1, Color c2, IconData icon) {
    final width = MediaQuery.of(context).size.width;
    final compact = width <= 430;
    final cardRadius = compact ? 18.0 : 24.0;
    final cardPadding = compact ? 14.0 : 20.0;
    final titleFont = compact ? 17.0 : 22.0;
    final descFont = compact ? 10.5 : 12.0;
    final featureFont = compact ? 12.0 : 14.0;
    final featureIconSize = compact ? 17.0 : 20.0;
    final priceFont = compact ? 13.0 : 14.0;
    final actionFont = compact ? 13.0 : 15.0;
    final avatarRadius = compact ? 21.0 : 26.0;

    final id = _toInt(plan['id']) ?? 0;
    final title = (plan['title'] ?? plan['name'] ?? 'باقة').toString();
    final description = (plan['description'] ?? '').toString();
    final price = plan['price'];
    final period = (plan['period'] ?? '').toString();
    final periodLabel = (plan['period_label'] ?? '').toString().trim();
    final features = _extractFeatures(plan);

    final currentSub = _currentSubscription;
    final currentPlanId = _toInt(
      currentSub?['plan'] is Map
          ? (currentSub?['plan'] as Map)['id']
          : currentSub?['plan_id'],
    );
    final currentStatusCode =
        (currentSub?['status'] ?? '').toString().trim().toLowerCase();
    final isCurrentPlan = currentPlanId != null && currentPlanId == id;
    final isCurrentLocked = isCurrentPlan &&
        const {'active', 'grace', 'pending_payment'}
            .contains(currentStatusCode);
    final currentStatusLabel = isCurrentPlan
        ? SubscriptionsService.subscriptionStatusLabel(currentStatusCode)
        : null;

    final priceDisplay = price == null || price.toString() == '0.00'
        ? 'مجاني'
        : '$price ر.س / ${periodLabel.isNotEmpty ? periodLabel : (period == 'year' ? 'سنة' : 'شهر')}';
    final buttonLabel = isCurrentLocked
        ? (currentStatusCode == 'pending_payment'
            ? 'قيد التفعيل'
            : 'الباقة الحالية')
        : 'اشترك الآن';

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 12 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        gradient: LinearGradient(
            colors: [c1, c2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(
              color: c2.withAlpha(75),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardRadius),
          color: Colors.white.withAlpha(40),
        ),
        child: Padding(
          padding: EdgeInsets.all(cardPadding),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Colors.white.withAlpha(50),
                child: Icon(icon, size: compact ? 22 : 28, color: Colors.white),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: titleFont,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    if (description.isNotEmpty)
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: descFont,
                              color: Colors.white70)),
                    if (isCurrentPlan)
                      Padding(
                        padding: EdgeInsets.only(top: compact ? 6 : 8),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 10,
                              vertical: compact ? 3 : 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            currentStatusLabel ?? 'الباقة المختارة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 10 : 11,
                              color: c2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withAlpha(230),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(priceDisplay,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: priceFont,
                        color: c2)),
              ),
            ]),
            SizedBox(height: compact ? 12 : 20),

            // Features
            if (features.isNotEmpty)
              ...features.map((f) => Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
                    child: Row(children: [
                      Icon(Icons.check_circle,
                          size: featureIconSize, color: Colors.white),
                      SizedBox(width: compact ? 6 : 8),
                      Expanded(
                          child: Text(f,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: featureFont,
                                  color: Colors.white))),
                    ]),
                  )),
            SizedBox(height: compact ? 12 : 20),

            // Subscribe button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_subscribing || id <= 0 || isCurrentLocked)
                    ? null
                    : () => _subscribe(id, title),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(compact ? 12 : 14)),
                  minimumSize: Size(double.infinity, compact ? 44 : 50),
                ),
                child: _subscribing
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c2))
                    : Text(buttonLabel,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: actionFont,
                            color: c2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
