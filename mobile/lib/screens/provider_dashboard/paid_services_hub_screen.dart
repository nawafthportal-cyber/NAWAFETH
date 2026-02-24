import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../services/extras_api.dart';
import '../../services/promo_api.dart';
import '../../services/providers_api.dart';
import '../../services/subscriptions_api.dart';
import '../../services/verification_api.dart';
import '../../utils/auth_guard.dart';
import '../extra_services_screen.dart';
import '../plans_screen.dart';
import '../promo_requests_screen.dart';
import '../verification_screen.dart';

class PaidServicesHubScreen extends StatefulWidget {
  const PaidServicesHubScreen({super.key});

  @override
  State<PaidServicesHubScreen> createState() => _PaidServicesHubScreenState();
}

class _PaidServicesHubScreenState extends State<PaidServicesHubScreen> {
  final ProvidersApi _providersApi = ProvidersApi();
  final VerificationApi _verificationApi = VerificationApi();
  final SubscriptionsApi _subscriptionsApi = SubscriptionsApi();
  final ExtrasApi _extrasApi = ExtrasApi();
  final PromoApi _promoApi = PromoApi();

  late Future<_PaidServicesSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = Future.value(_PaidServicesSummary.empty());
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

  void _reload() {
    setState(() {
      _summaryFuture = _loadSummary();
    });
  }

  Future<_PaidServicesSummary> _loadSummary() async {
    Map<String, dynamic>? profile;
    List<Map<String, dynamic>> verificationRequests = const [];
    List<Map<String, dynamic>> plans = const [];
    List<Map<String, dynamic>> subscriptions = const [];
    List<Map<String, dynamic>> extrasCatalog = const [];
    List<Map<String, dynamic>> myExtras = const [];
    List<Map<String, dynamic>> promoRequests = const [];

    await Future.wait([
      () async {
        try {
          profile = await _providersApi.getMyProviderProfile();
        } catch (_) {}
      }(),
      () async {
        try {
          verificationRequests = await _verificationApi.getMyRequests();
        } catch (_) {}
      }(),
      () async {
        try {
          plans = await _subscriptionsApi.getPlans();
        } catch (_) {}
      }(),
      () async {
        try {
          subscriptions = await _subscriptionsApi.getMySubscriptions();
        } catch (_) {}
      }(),
      () async {
        try {
          extrasCatalog = await _extrasApi.getCatalog();
        } catch (_) {}
      }(),
      () async {
        try {
          myExtras = await _extrasApi.getMyExtras();
        } catch (_) {}
      }(),
      () async {
        try {
          promoRequests = await _promoApi.getMyRequests();
        } catch (_) {}
      }(),
    ]);

    final profileMap = profile ?? const <String, dynamic>{};
    final verifiedBlue = _asBool(profileMap['is_verified_blue']);
    final verifiedGreen = _asBool(profileMap['is_verified_green']);

    return _PaidServicesSummary(
      isVerifiedBlue: verifiedBlue,
      isVerifiedGreen: verifiedGreen,
      verificationRequestsCount: verificationRequests.length,
      verificationStatus: _latestStatus(verificationRequests),
      plansAvailableCount: plans.length,
      subscriptionsCount: subscriptions.length,
      subscriptionStatus: _latestStatus(subscriptions),
      extrasCatalogCount: extrasCatalog.length,
      myExtrasCount: myExtras.length,
      extrasStatus: _latestStatus(myExtras),
      promoRequestsCount: promoRequests.length,
      promoStatus: _latestStatus(promoRequests),
    );
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    final s = (value ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  String? _latestStatus(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final sorted = [...rows];
    sorted.sort((a, b) {
      final da = _parseDate(a['created_at']);
      final db = _parseDate(b['created_at']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    final latest = sorted.first;
    final status = (latest['status'] ?? latest['state'] ?? latest['payment_status'] ?? '')
        .toString()
        .trim();
    if (status.isEmpty) return null;
    return _statusLabel(status);
  }

  DateTime? _parseDate(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _statusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    const labels = <String, String>{
      'pending': 'قيد المراجعة',
      'submitted': 'تم الإرسال',
      'approved': 'مقبول',
      'rejected': 'مرفوض',
      'paid': 'مدفوع',
      'unpaid': 'غير مدفوع',
      'active': 'نشط',
      'inactive': 'غير نشط',
      'expired': 'منتهي',
      'cancelled': 'ملغي',
      'completed': 'مكتمل',
      'processing': 'قيد المعالجة',
      'draft': 'مسودة',
    };
    return labels[s] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الخدمات المدفوعة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<_PaidServicesSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HubStateMessage(
              text: 'تعذر تحميل بيانات الخدمات المدفوعة.',
              action: 'إعادة المحاولة',
              onTap: _reload,
            );
          }

          final summary = snapshot.data ?? _PaidServicesSummary.empty();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                _buildHeaderCard(summary, cs),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 560;
                    final ratio = isWide ? 1.55 : 1.08;
                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: ratio,
                      children: [
                        _featureCard(
                          title: 'توثيق',
                          subtitle: summary.verificationRequestsCount == 0
                              ? 'ابدأ طلب التوثيق'
                              : 'طلبات: ${summary.verificationRequestsCount}',
                          status: summary.verificationStatus ??
                              (summary.isVerifiedBlue || summary.isVerifiedGreen
                                  ? 'موثق'
                                  : 'غير موثق'),
                          icon: Icons.verified_outlined,
                          colors: const [Color(0xFF4D9DE0), Color(0xFF2A6FD1)],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const VerificationScreen()),
                            );
                          },
                        ),
                        _featureCard(
                          title: 'ترقية',
                          subtitle: 'الباقات المتاحة: ${summary.plansAvailableCount}',
                          status: summary.subscriptionStatus ??
                              (summary.subscriptionsCount > 0 ? 'لديك اشتراكات' : 'بدون اشتراك'),
                          icon: Icons.arrow_circle_up_outlined,
                          colors: const [Color(0xFFF7C100), Color(0xFFE7A900)],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PlansScreen()),
                            );
                          },
                        ),
                        _featureCard(
                          title: 'ترويج',
                          subtitle: summary.promoRequestsCount == 0
                              ? 'أنشئ حملة ترويجية'
                              : 'طلبات: ${summary.promoRequestsCount}',
                          status: summary.promoStatus ?? 'لا توجد طلبات',
                          icon: Icons.campaign_outlined,
                          colors: const [Color(0xFF2E7D32), Color(0xFF1F5C25)],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PromoRequestsScreen(),
                              ),
                            );
                          },
                        ),
                        _featureCard(
                          title: 'الخدمات الإضافية',
                          subtitle: 'المتاحة: ${summary.extrasCatalogCount}',
                          status: summary.extrasStatus ??
                              (summary.myExtrasCount > 0 ? 'لديك مشتريات' : 'بدون مشتريات'),
                          icon: Icons.add_box_outlined,
                          colors: const [Color(0xFFF07B2A), Color(0xFFE35A20)],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExtraServicesScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ملاحظات',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'تم ربط هذه الصفحة ببيانات التوثيق والباقات والترويج والخدمات الإضافية من الـ API. اسحب للتحديث لتحديث الملخصات.',
                          style: TextStyle(fontFamily: 'Cairo', height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(_PaidServicesSummary summary, ColorScheme cs) {
    final chips = <Widget>[
      _statusChip(
        label: 'شارة زرقاء',
        active: summary.isVerifiedBlue,
        activeColor: Colors.blue,
      ),
      _statusChip(
        label: 'شارة خضراء',
        active: summary.isVerifiedGreen,
        activeColor: Colors.green,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppColors.deepPurple,
            AppColors.deepPurple.withValues(alpha: 0.82),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepPurple.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
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
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.workspace_premium_outlined, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'مركز الخدمات المدفوعة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'إدارة التوثيق والترقية والترويج والإضافات من شاشة واحدة بدون تكرار.',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white.withValues(alpha: 0.90),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required bool active,
    required Color activeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.65) : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: active ? activeColor : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(
            active ? '$label: مفعلة' : '$label: غير مفعلة',
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureCard({
    required String title,
    required String subtitle,
    required String status,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
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
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaidServicesSummary {
  final bool isVerifiedBlue;
  final bool isVerifiedGreen;
  final int verificationRequestsCount;
  final String? verificationStatus;
  final int plansAvailableCount;
  final int subscriptionsCount;
  final String? subscriptionStatus;
  final int extrasCatalogCount;
  final int myExtrasCount;
  final String? extrasStatus;
  final int promoRequestsCount;
  final String? promoStatus;

  const _PaidServicesSummary({
    required this.isVerifiedBlue,
    required this.isVerifiedGreen,
    required this.verificationRequestsCount,
    required this.verificationStatus,
    required this.plansAvailableCount,
    required this.subscriptionsCount,
    required this.subscriptionStatus,
    required this.extrasCatalogCount,
    required this.myExtrasCount,
    required this.extrasStatus,
    required this.promoRequestsCount,
    required this.promoStatus,
  });

  factory _PaidServicesSummary.empty() => const _PaidServicesSummary(
        isVerifiedBlue: false,
        isVerifiedGreen: false,
        verificationRequestsCount: 0,
        verificationStatus: null,
        plansAvailableCount: 0,
        subscriptionsCount: 0,
        subscriptionStatus: null,
        extrasCatalogCount: 0,
        myExtrasCount: 0,
        extrasStatus: null,
        promoRequestsCount: 0,
        promoStatus: null,
      );
}

class _HubStateMessage extends StatelessWidget {
  final String text;
  final String action;
  final VoidCallback onTap;

  const _HubStateMessage({
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
