import 'package:flutter/material.dart';

import '../services/billing_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/subscriptions_service.dart';
import '../widgets/platform_top_bar.dart';
import 'login_screen.dart';
import 'plans_screen.dart';

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
  bool _checkingAccess = true;
  bool _isLoggedIn = true;
  bool _loadingSummary = true;
  bool _submitting = false;
  int _durationCount = 1;
  String _accountHandle = 'الحساب الحالي';
  String? _summaryError;
  Map<String, dynamic>? _resolvedPlan;

  @override
  void initState() {
    super.initState();
    _loadAccessContext();
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  double _toMoney(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  double _roundMoney(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  String _moneyLabel(double value) {
    return value.toStringAsFixed(2);
  }

  String _periodUnit(dynamic value) {
    return (_asString(value) ?? '').toLowerCase() == 'month' ? 'شهر' : 'سنة';
  }

  bool _looksLikePhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s\-\+\(\)@]'), '');
    return RegExp(r'^0\d{8,12}$').hasMatch(normalized) ||
        RegExp(r'^9665\d{8}$').hasMatch(normalized) ||
        RegExp(r'^5\d{8}$').hasMatch(normalized);
  }

  String _safeHandleValue(String? value, {bool prefixAt = false}) {
    final text = (value ?? '').trim();
    if (text.isEmpty || _looksLikePhone(text)) {
      return '';
    }
    if (!prefixAt) return text;
    return text.startsWith('@') ? text : '@$text';
  }

  Future<void> _loadAccessContext() async {
    final loggedIn = await AuthService.isLoggedIn();
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _checkingAccess = false;
        _isLoggedIn = false;
        _loadingSummary = false;
        _accountHandle = 'الحساب الحالي';
        _summaryError = null;
        _resolvedPlan = null;
      });
      return;
    }

    var accountHandle = 'الحساب الحالي';
    try {
      final profileResult = await ProfileService.fetchMyProfile();
      final profile = profileResult.data;
      if (profileResult.isSuccess && profile != null) {
        final candidates = <String>[
          _safeHandleValue(profile.username, prefixAt: true),
          _safeHandleValue(profile.providerDisplayName),
          _safeHandleValue(profile.displayName),
        ];
        for (final candidate in candidates) {
          if (candidate.isNotEmpty) {
            accountHandle = candidate;
            break;
          }
        }
      }
    } catch (_) {
      // Keep fallback handle.
    }

    Map<String, dynamic>? resolvedPlan;
    String? summaryError;
    try {
      resolvedPlan = await _resolveLatestPlan();
      if (resolvedPlan == null) {
        summaryError = 'تعذر العثور على الباقة المطلوبة';
      }
    } catch (_) {
      summaryError = 'تعذر تحميل تفاصيل الباقة';
    }

    if (!mounted) return;
    setState(() {
      _checkingAccess = false;
      _isLoggedIn = true;
      _loadingSummary = false;
      _accountHandle = accountHandle;
      _summaryError = summaryError;
      _resolvedPlan = resolvedPlan;
    });
  }

  Future<Map<String, dynamic>?> _resolveLatestPlan() async {
    final planId = _toInt(widget.plan['id']);
    if (planId == null || planId <= 0) {
      return widget.plan.isEmpty ? null : Map<String, dynamic>.from(widget.plan);
    }
    final plans = await SubscriptionsService.getPlans();
    for (final plan in plans) {
      final candidateId = _toInt(plan['id']);
      if (candidateId == planId) {
        return Map<String, dynamic>.from(plan);
      }
    }
    return null;
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          redirectTo: PlanSummaryScreen(plan: widget.plan),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _checkingAccess = true;
      _loadingSummary = true;
      _summaryError = null;
    });
    await _loadAccessContext();
  }

  String _actionHint(Map<String, dynamic> plan) {
    final action = SubscriptionsService.planAction(plan);
    final stateCode = (_asString(action['state']) ?? '').toLowerCase();
    if (stateCode == 'current') {
      return 'هذه هي باقتك الحالية بالفعل.';
    }
    if (stateCode == 'unavailable') {
      return 'لا يمكن تخفيض الباقة من هذا المسار.';
    }
    if (stateCode == 'pending' && _asString(action['label']) == 'بانتظار المراجعة') {
      return 'هذا الطلب مدفوع بالفعل وينتظر مراجعة فريق الاشتراكات.';
    }
    if (stateCode == 'pending') {
      return 'يوجد طلب سابق غير مكتمل لهذه الباقة، ويمكنك متابعة الدفع منه.';
    }
    return '';
  }

  String _submitLabel(Map<String, dynamic> plan) {
    final action = SubscriptionsService.planAction(plan);
    final stateCode = (_asString(action['state']) ?? '').toLowerCase();
    if (stateCode == 'pending') {
      return 'استمرار إلى الدفع';
    }
    return 'استمرار';
  }

  ({double subtotal, double vat, double total}) _pricingSummary(
    Map<String, dynamic> plan,
  ) {
    final offer = SubscriptionsService.planOffer(plan);
    final unitPrice = _toMoney(
      offer['final_payable_amount'] ?? plan['price'] ?? offer['annual_price'],
    );
    final vatPercent = _toMoney(offer['additional_vat_percent']);
    final durationCount = _durationCount.clamp(1, 10);
    final subtotal = _roundMoney(unitPrice * durationCount);
    final vat = _roundMoney(subtotal * (vatPercent / 100));
    final total = _roundMoney(subtotal + vat);
    return (subtotal: subtotal, vat: vat, total: total);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  bool _requiresPayment(Map<String, dynamic>? subscription) {
    if (subscription == null) return false;
    final invoiceSummary = subscription['invoice_summary'];
    final summary = invoiceSummary is Map
        ? Map<String, dynamic>.from(invoiceSummary)
        : const <String, dynamic>{};

    final invoiceId = _toInt(subscription['invoice'] ?? summary['id']) ?? 0;
    final statusCode = (_asString(
              subscription['provider_status_code'] ?? subscription['status'],
            ) ??
            '')
        .toLowerCase();
    final invoiceStatus = (_asString(summary['status']) ?? '').toLowerCase();
    final invoicePaid =
        invoiceStatus == 'paid' || summary['payment_effective'] == true;
    final total = _toMoney(summary['total']);

    return invoiceId > 0 &&
        statusCode == 'pending_payment' &&
        !invoicePaid &&
        total > 0;
  }

  String _requestCodeFromSubscription(Map<String, dynamic> subscription) {
    final requestCode = _asString(subscription['request_code']);
    if (requestCode != null) return requestCode;
    final subscriptionId = _toInt(subscription['id']);
    if (subscriptionId != null && subscriptionId > 0) {
      return 'SD${subscriptionId.toString().padLeft(6, '0')}';
    }
    return '';
  }

  Future<void> _startPaymentFlow(Map<String, dynamic> subscription) async {
    final invoiceSummary = subscription['invoice_summary'];
    final summary = invoiceSummary is Map
        ? Map<String, dynamic>.from(invoiceSummary)
        : const <String, dynamic>{};
    final invoiceId = _toInt(subscription['invoice'] ?? summary['id']);
    if (invoiceId == null || invoiceId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فاتورة مرتبطة بطلب الاشتراك')),
      );
      return;
    }

    final subscriptionId = _toInt(subscription['id']) ?? 0;
    final initRes = await BillingService.initPayment(
      invoiceId: invoiceId,
      idempotencyKey: 'subscription-checkout-$subscriptionId-$invoiceId',
    );
    if (!mounted) return;

    if (!initRes.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(initRes.error ?? 'تعذر فتح صفحة الدفع')),
      );
      return;
    }

    final attempt = Map<String, dynamic>.from(initRes.dataAsMap ?? const {});
    final checkoutUrl = _asString(attempt['checkout_url']) ?? '';
    if (checkoutUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحصول على رابط صفحة الدفع')),
      );
      return;
    }

    final opened = await BillingService.openCheckout(
      checkoutUrl: checkoutUrl,
      requestCode: _requestCodeFromSubscription(subscription),
    );
    if (!mounted) return;

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح صفحة الدفع الموحدة')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم فتح صفحة الدفع الموحدة. بعد إتمام السداد ستعود للتطبيق تلقائيًا.',
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final currentPlan = _resolvedPlan ?? widget.plan;
    final action = SubscriptionsService.planAction(currentPlan);
    if (action['enabled'] != true) return;

    final planId = _toInt(currentPlan['id']);
    if (planId == null || planId <= 0) return;

    setState(() => _submitting = true);
    final result = await SubscriptionsService.subscribe(
      planId,
      durationCount: _durationCount,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'تعذر إنشاء طلب الاشتراك')),
      );
      return;
    }

    final subscription =
        Map<String, dynamic>.from(result.dataAsMap ?? const {});
    if (_requiresPayment(subscription)) {
      await _startPaymentFlow(subscription);
      return;
    }

    final offer = SubscriptionsService.planOffer(currentPlan);
    final amountLabel = (offer['final_payable_label'] ??
            offer['annual_price_label'] ??
            'مجانية')
        .toString();

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تم تسجيل الاشتراك بنجاح'),
          content: Text(
              'سيتم إشعاركم بتفعيل الاشتراك بعد مراجعة فريق الاشتراكات. المبلغ النهائي: $amountLabel'),
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
    final plan = _resolvedPlan ?? widget.plan;
    final offer = SubscriptionsService.planOffer(plan);
    final action = SubscriptionsService.planAction(plan);
    final rows = _mapList(offer['summary_rows']);
    final features = (offer['feature_bullets'] is List)
        ? (offer['feature_bullets'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : const <String>[];
    final pricing = _pricingSummary(plan);
    final actionHint = _actionHint(plan);

    final planName = SubscriptionsService.planDisplayTitle(plan);
    final billingCycle = (offer['billing_cycle_label'] ?? 'سنوي').toString();
    final unitLabel = _periodUnit(plan['period']);
    final annualPrice = (offer['annual_price_label'] ?? 'مجانية').toString();
    final finalAmount = _moneyLabel(pricing.total);
    final verificationEffect =
        (offer['verification_effect_label'] ?? '—').toString();
    final taxNote = (offer['tax_note'] ?? '').toString();
    final buttonLabel = _submitLabel(plan);
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
        body: _checkingAccess
            ? const Center(child: CircularProgressIndicator())
            : !_isLoggedIn
                ? _buildAuthGate()
            : _loadingSummary
              ? _buildLoadingState()
              : _resolvedPlan == null
                ? _buildEmptyState()
                : ListView(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(32),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المبلغ النهائي',
                          style: TextStyle(
                              color: Colors.white70, fontFamily: 'Cairo'),
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
                          style: const TextStyle(
                              color: Colors.white70, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'اسم المستخدم',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6D28D9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _accountHandle,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
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
                  _infoRow('المدة', '$_durationCount $unitLabel'),
                  _infoRow('دورة الفوترة', billingCycle),
                  _infoRow('سعر الباقة', annualPrice),
                  _infoRow('أثر التوثيق', verificationEffect),
                  _infoRow('المبلغ النهائي المستحق', finalAmount,
                      emphasize: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'احتساب التكلفة',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'عدد مرات الاشتراك',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _durationCount > 1
                                  ? () => setState(() => _durationCount--)
                                  : null,
                              icon: const Icon(Icons.remove_rounded),
                              color: const Color(0xFF0F766E),
                            ),
                            Text(
                              '$_durationCount',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            IconButton(
                              onPressed: _durationCount < 10
                                  ? () => setState(() => _durationCount++)
                                  : null,
                              icon: const Icon(Icons.add_rounded),
                              color: const Color(0xFF0F766E),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'يمكنك اختيار من 1 إلى 10 $unitLabel وسيتم احتساب المبلغ تلقائيًا.',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Color(0xFF64748B),
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _infoRow(
                    'المجموع',
                    '${_moneyLabel(pricing.subtotal)} ريال',
                  ),
                  _infoRow(
                    'VAT',
                    '${_moneyLabel(pricing.vat)} ريال',
                  ),
                  _infoRow(
                    'التكلفة الكلية',
                    '${_moneyLabel(pricing.total)} ريال',
                    emphasize: true,
                  ),
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
            if (actionHint.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        actionHint,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Color(0xFF475569),
                          height: 1.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  Widget _buildAuthGate() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFFDF2F8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF3E8FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x147C2D8B),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0x147C2D8B),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF7C2D8B),
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'تسجيل الدخول مطلوب',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF581C87),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'يجب تسجيل الدخول لإكمال ملخص طلب الترقية والمتابعة إلى الاشتراك.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C2D8B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF0F766E)),
            SizedBox(height: 14),
            Text(
              'جاري تجهيز ملخص الطلب...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFD97706),
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _summaryError ?? 'تعذر العثور على الباقة المطلوبة',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const PlansScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'العودة إلى الاشتراكات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w800,
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
                color: emphasize
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF0F172A),
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
